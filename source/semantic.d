module semantic;

import std.format : format;
import std.array : join;
import parser;
import expr;

/// Programma già validato e strutturato: è ciò che riceve l'interprete.
class Program
{
    Stmt[] body;         /// da dopo 'inizio' fino a 'fine' compreso
    size_t inizioLine;
}

/// Contiene TUTTI gli errori semantici trovati, uno per riga.
class SemanticException : Exception
{
    this(string[] errors, string file = __FILE__, size_t ln = __LINE__)
    {
        super(errors.join("\n"), file, ln);
    }
}

/// Passo tra parser e interprete. Verifica:
///  - struttura:  inizio { qualsiasi istruzione } fine
///                'inizio' sempre PRIMA istruzione, un solo 'inizio' e un solo 'fine' (ultimo)
///  - variabili:  dichiarate (una volta sola) prima di essere usate
/// Se tutto è ok restituisce il Program pronto per l'esecuzione.
struct DeclaredVar
{
    size_t line;
    string typeName;
}

class SemanticChecker
{
private:
    DeclaredVar[string][] declaredAtStack; // stack di scope: scope corrente in fondo
    bool[string] declaredFunctions;
    bool inFunction;
    string currentFunctionReturnType;
    string[] errors;

public:
    Program analyze(Stmt[] stmts)
    {
        declaredAtStack = [(DeclaredVar[string]).init];
        declaredFunctions = null;
        inFunction = false;
        currentFunctionReturnType = "";
        errors = [];

        // ---------- struttura ----------
        long iIni = -1, iFine = -1;
        foreach (i, s; stmts)
        {
            if (s.kind == StmtKind.Inizio)
            {
                if (iIni < 0) iIni = cast(long) i;
                else err(s.line, format("'inizio' duplicato (già alla riga %s)", stmts[iIni].line));
            }
            else if (s.kind == StmtKind.Fine)
            {
                if (iFine < 0) iFine = cast(long) i;
                else err(s.line, format("'fine' duplicato (già alla riga %s)", stmts[iFine].line));
            }
        }

        if (iIni < 0)
            errGlobal("manca 'inizio'");
        else if (iIni != 0)
            err(stmts[0].line, format(
                "il programma deve iniziare con 'inizio' (trovato alla riga %s)", stmts[iIni].line));

        if (iFine < 0)
            errGlobal("manca 'fine'");

        if (iFine >= 0 && iFine != cast(long) stmts.length - 1)
            err(stmts[iFine + 1].line, "istruzioni dopo 'fine': non verrebbero mai eseguite");

        // ---------- variabili ----------
        foreach (s; stmts)
            visit(s);

        if (errors.length)
            throw new SemanticException(errors);

        auto prog = new Program;
        prog.body = stmts[1 .. $];
        prog.inizioLine = stmts[iIni].line;
        return prog;
    }

private:
    void err(size_t line, string msg)
    {
        errors ~= format("Errore semantico riga %s: %s", line, msg);
    }

    void errGlobal(string msg)
    {
        errors ~= "Errore semantico: " ~ msg;
    }

    void pushScope()
    {
        declaredAtStack ~= (DeclaredVar[string]).init;
    }

    void popScope()
    {
        if (declaredAtStack.length > 0)
            declaredAtStack.length--;
    }

    void declare(string name, size_t line, string typeName = "")
    {
        auto refr = &declaredAtStack[$ - 1];
        if (auto p = name in *refr)
            err(line, format("variabile '%s' già dichiarata (riga %s)", name, (*p).line));
        else
            (*refr)[name] = DeclaredVar(line, typeName);
    }

    void requireDeclared(string name, size_t line)
    {
        foreach_reverse (scopeIndex; 0 .. declaredAtStack.length)
        {
            if (name in declaredAtStack[scopeIndex])
                return;
        }
        err(line, format("variabile '%s' non dichiarata", name));
    }

    static bool isKnownFunction(string name)
    {
        switch (name)
        {
            case "abs":
            case "sqrt":
            case "sin":
            case "cos":
            case "tan":
            case "pow":
            case "min":
            case "max":
            case "floor":
            case "ceil":
            case "round":
            case "log":
            case "exp":
                return true;
            default:
                return false;
        }
    }

    /// Visita ricorsivamente l'espressione: ogni variabile deve essere dichiarata.
    void requireExpr(Expr e)
    {
        final switch (e.kind)
        {
            case ExprKind.Number:
            case ExprKind.String:
            case ExprKind.Boolean:
                break;
            case ExprKind.List:
            {
                auto l = cast(ListExpr) e;
                foreach (item; l.items)
                    requireExpr(item);
                break;
            }
            case ExprKind.Variable:
                requireDeclared((cast(VariableExpr) e).name, e.line);
                break;
            case ExprKind.Index:
            {
                auto idx = cast(IndexExpr) e;
                requireExpr(idx.target);
                requireExpr(idx.index);
                break;
            }
            case ExprKind.Call:
            {
                auto c = cast(CallExpr) e;
                if (c.receiver)
                    requireExpr(c.receiver);
                foreach (a; c.args)
                    requireExpr(a);
                break;
            }
            case ExprKind.BinOp:
            {
                auto b = cast(BinOpExpr) e;
                requireExpr(b.left);
                requireExpr(b.right);

                // divisione/modulo per zero letterale: errore statico
                if ((b.op == BinOpKind.Div || b.op == BinOpKind.Mod)
                    && b.right.kind == ExprKind.Number
                    && (cast(NumberExpr) b.right).value == 0)
                    err(b.line, "divisione per zero");
                break;
            }
        }
    }

    void visit(Stmt s)
    {
        final switch (s.kind)
        {
            case StmtKind.Dichiara:
            {
                auto st = cast(DichiaraStmt) s;
                foreach (n; st.names)
                    declare(n, s.line, st.typeName);
                break;
            }
            case StmtKind.Leggi:
            {
                auto st = cast(LeggiStmt) s;
                foreach (n; st.targets)
                    requireDeclared(n, s.line);
                break;
            }
            case StmtKind.Assegna:
            {
                auto st = cast(AssegnaStmt) s;
                if (st.destExpr !is null)
                    requireExpr(st.destExpr);
                else
                    requireDeclared(st.dest, s.line);
                requireExpr(st.src);
                break;
            }
            case StmtKind.Calcola:
            {
                auto st = cast(CalcolaStmt) s;
                if (st.destExpr !is null)
                    requireExpr(st.destExpr);
                else
                    requireDeclared(st.dest, s.line);
                requireExpr(st.src);
                break;
            }
            case StmtKind.Scrivi:
            {
                auto st = cast(ScriviStmt) s;
                foreach (a; st.args)
                    requireExpr(a);
                break;
            }
            case StmtKind.Se:
            {
                auto st = cast(SeStmt) s;
                requireExpr(st.condition);
                pushScope();
                foreach (b; st.thenBody)
                    visit(b);
                popScope();
                pushScope();
                foreach (b; st.elseBody)
                    visit(b);
                popScope();
                break;
            }
            case StmtKind.Esegui:
            {
                auto st = cast(EseguiStmt) s;
                if (!st.infinite)
                    requireExpr(st.condition);
                pushScope();
                foreach (b; st.body)
                    visit(b);
                popScope();
                break;
            }
            case StmtKind.Per:
            {
                auto st = cast(ForStmt) s;
                requireExpr(st.start);
                requireExpr(st.end);
                if (st.hasStep)
                    requireExpr(st.step);

                pushScope();
                declare(st.varName, st.line);
                foreach (b; st.body)
                    visit(b);
                popScope();
                break;
            }
            case StmtKind.Funzione:
            {
                auto st = cast(FunzioneStmt) s;
                if (st.name in declaredFunctions)
                    err(st.line, format("funzione '%s' già dichiarata", st.name));
                declaredFunctions[st.name] = true;

                pushScope();
                foreach (i, p; st.params)
                    declare(p, st.line, i < st.paramTypes.length ? st.paramTypes[i] : "");

                bool oldInFunction = inFunction;
                string oldReturnType = currentFunctionReturnType;
                inFunction = true;
                currentFunctionReturnType = st.returnType;
                foreach (b; st.body)
                    visit(b);
                currentFunctionReturnType = oldReturnType;
                inFunction = oldInFunction;
                popScope();
                break;
            }
            case StmtKind.Ritorna:
            {
                auto st = cast(RitornaStmt) s;
                if (!inFunction)
                    err(s.line, "ritorna fuori da una funzione");
                else
                {
                    requireExpr(st.value);
                    if (currentFunctionReturnType.length)
                    {
                        // controllo di compatibilità di tipo solo a livello di semantica
                        // le verifiche precise avvengono in runtime
                    }
                }
                break;
            }
            case StmtKind.ExprStmt:
            {
                auto st = cast(ExprStmt) s;
                requireExpr(st.expr);
                break;
            }
            case StmtKind.Continua, StmtKind.Ferma:
                break;
            case StmtKind.Inizio, StmtKind.Fine:
                break;
        }
    }
}