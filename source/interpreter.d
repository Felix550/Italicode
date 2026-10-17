module interpreter;

import std.stdio;
import std.format;
import std.array : appender, join;
import std.ascii : isDigit, isHexDigit, isASCII;
import std.conv : to, ConvException;
import std.string : strip;
import std.algorithm.comparison : max, min;
import std.algorithm.mutation : reverse;
import std.algorithm.sorting : sort;
import std.math : abs = fabs, ceil, cos, exp, floor, log, pow, round, sin, sqrt, tan;
import std.random;
import std.uni : isAlpha, isAlphaNum, isNumber, isWhite, isUpper, isLower, toUpper, toLower;
import lexer;
import parser;
import expr;
import semantic;

struct Value
{
    bool isString;
    bool isBool;
    bool isList;
    double num;
    string str;
    bool boolValue;
    Value[] list;

    static Value ofNumber(double n) { Value v; v.num = n; return v; }
    static Value ofString(string s) { Value v; v.isString = true; v.str = s; return v; }
    static Value ofBoolean(bool b) { Value v; v.isBool = true; v.boolValue = b; return v; }
    static Value ofList(Value[] items) { Value v; v.isList = true; v.list = items.dup; return v; }

    string toString() const
    {
        if (isBool) return boolValue ? "vero" : "falso";
        if (isString) return str;
        if (isList)
        {
            string[] parts;
            foreach (item; list)
                parts ~= item.toString();
            return "[" ~ parts.join(", ") ~ "]";
        }
        return numberToString(num);
    }
}

class RuntimeError : Exception
{
    this(string msg, size_t line, string file = __FILE__, size_t ln = __LINE__)
    {
        super(format("Errore runtime riga %s: %s", line, msg), file, ln);
    }
}

string formatValues(string fmt, Value[] args, size_t line)
{
    auto sb = appender!string();
    size_t next = 0;
    for (size_t i = 0; i < fmt.length; i++)
    {
        immutable char c = fmt[i];
        if (c != '%') { sb.put(c); continue; }
        if (i + 1 >= fmt.length)
            throw new RuntimeError("'%' finale senza specificatore", line);
        immutable char spec = fmt[++i];
        if (spec == '%') { sb.put('%'); continue; }
        if (spec != 's' && spec != 'd' && spec != 'f')
            throw new RuntimeError(format("specificatore '%%%s' sconosciuto", spec), line);
        if (next >= args.length)
            throw new RuntimeError("più specificatori che argomenti", line);
        Value v = args[next++];
        switch (spec)
        {
            case 's': sb.put(v.toString()); break;
            case 'd':
                if (v.isString || v.num != cast(long) v.num)
                    throw new RuntimeError("%d richiede un numero intero", line);
                sb.put(to!string(cast(long) v.num));
                break;
            default:
                if (v.isString) throw new RuntimeError("%f richiede un numero", line);
                sb.put(format("%f", v.num));
                break;
        }
    }
    if (next < args.length)
        throw new RuntimeError("più argomenti che specificatori", line);
    return sb.data;
}

struct FunctionDef
{
    string name;
    string[] params;
    string[] paramTypes;
    string returnType;
    Stmt[] body;
}

class Interpreter
{
private:
    Value[string][] varStack;
    string[string][] varTypes;
    FunctionDef[string] functions;
    Value returnValue;
    bool returnRequested;
    bool halted;
    bool loopBreakRequested;
    bool loopContinueRequested;
public:
    void run(Program program)
    {
        varStack = [(Value[string]).init];
        varTypes = [(string[string]).init];
        functions = null;
        returnRequested = false;
        returnValue = Value.init;
        halted = false;
        loopBreakRequested = false;
        loopContinueRequested = false;
        foreach (s; program.body)
        {
            exec(s);
            if (halted) break;
        }
    }
private:
    void pushScope()
    {
        varStack ~= (Value[string]).init;
        varTypes ~= (string[string]).init;
    }

    void popScope()
    {
        if (varStack.length > 0)
            varStack.length--;
        if (varTypes.length > 0)
            varTypes.length--;
    }

    Value* lookupVar(string name)
    {
        foreach_reverse (i; 0 .. varStack.length)
        {
            if (auto p = name in varStack[i])
                return p;
        }
        return null;
    }

    string lookupVarType(string name)
    {
        foreach_reverse (i; 0 .. varTypes.length)
        {
            if (auto p = name in varTypes[i])
                return *p;
        }
        return null;
    }

    static string normalizeTypeName(string raw)
    {
        if (raw.length == 0) return "";
        string s;
        foreach (ch; raw)
            s ~= cast(char) (ch >= 'A' && ch <= 'Z' ? ch + 32 : ch);
        switch (s)
        {
            case "intero": return "intero";
            case "reale": return "reale";
            case "stringa": return "stringa";
            case "booleano": return "booleano";
            case "vettore":
            case "lista":
            case "list":
                return "vettore";
            default: return s;
        }
    }

    static bool valueMatchesType(Value value, string typeName)
    {
        switch (normalizeTypeName(typeName))
        {
            case "intero":
                return !value.isString && !value.isBool && !value.isList && value.num == cast(long) value.num;
            case "reale":
                return !value.isString && !value.isBool && !value.isList;
            case "stringa":
                return value.isString;
            case "booleano":
                return value.isBool;
            case "vettore":
                return value.isList;
            default:
                return true;
        }
    }

    static int compareValues(Value left, Value right)
    {
        if (left.isBool || right.isBool)
            return boolValueOf(left) < boolValueOf(right) ? -1 : (boolValueOf(left) > boolValueOf(right) ? 1 : 0);
        if (left.isString || right.isString)
            return left.toString() < right.toString() ? -1 : (left.toString() > right.toString() ? 1 : 0);
        if (left.isList || right.isList)
            return left.toString() < right.toString() ? -1 : (left.toString() > right.toString() ? 1 : 0);
        if (left.num < right.num) return -1;
        if (left.num > right.num) return 1;
        return 0;
    }

    static bool isMutatingListMethod(string method)
    {
        switch (method)
        {
            case "push":
            case "aggiungi":
            case "pop":
            case "estrai":
            case "remove":
            case "rimuovi":
            case "insert":
            case "inserisci":
            case "set":
            case "imposta":
            case "clear":
            case "svuota":
            case "sort":
            case "ordina":
            case "reverse":
            case "inverti":
                return true;
            default:
                return false;
        }
    }

    static bool isNumericString(string s)
    {
        string t = strip(s);
        if (t.length == 0)
            return false;

        foreach (dchar ch; t)
        {
            if (!(ch == '+' || ch == '-' || ch == '.' || ch == 'e' || ch == 'E' || isDigit(ch)))
                return false;
        }

        if (t == "+" || t == "-" || t == ".")
            return false;

        try
        {
            to!double(t);
            return true;
        }
        catch (ConvException)
        {
            return false;
        }
    }

    static bool isAlphaString(string s)
    {
        if (s.length == 0)
            return false;
        foreach (dchar ch; s)
            if (!isAlpha(ch))
                return false;
        return true;
    }

    static bool isAlphaNumString(string s)
    {
        if (s.length == 0)
            return false;
        foreach (dchar ch; s)
            if (!(isAlpha(ch) || isDigit(ch)))
                return false;
        return true;
    }

    static bool isDigitString(string s)
    {
        if (s.length == 0)
            return false;
        foreach (dchar ch; s)
            if (!isDigit(ch))
                return false;
        return true;
    }

    static bool isWhiteString(string s)
    {
        if (s.length == 0)
            return false;
        foreach (dchar ch; s)
            if (!isWhite(ch))
                return false;
        return true;
    }

    static bool isUpperString(string s)
    {
        bool seen = false;
        foreach (dchar ch; s)
        {
            if (isAlpha(ch))
            {
                seen = true;
                if (!isUpper(ch))
                    return false;
            }
        }
        return seen;
    }

    static bool isLowerString(string s)
    {
        bool seen = false;
        foreach (dchar ch; s)
        {
            if (isAlpha(ch))
            {
                seen = true;
                if (!isLower(ch))
                    return false;
            }
        }
        return seen;
    }

    static bool isHexDigitString(string s)
    {
        if (s.length == 0)
            return false;
        foreach (dchar ch; s)
            if (!isHexDigit(ch))
                return false;
        return true;
    }

    static bool isAsciiString(string s)
    {
        foreach (dchar ch; s)
            if (ch > 0x7F)
                return false;
        return true;
    }

    static string toUpperString(string s)
    {
        string outStr;
        foreach (dchar ch; s)
            outStr ~= toUpper(ch);
        return outStr;
    }

    static string toLowerString(string s)
    {
        string outStr;
        foreach (dchar ch; s)
            outStr ~= toLower(ch);
        return outStr;
    }

    Value callStringMethod(Value receiver, string method, Value[] args, size_t line, out Value updatedReceiver)
    {
        if (!receiver.isString)
            throw new RuntimeError(format("il valore '%s' non è una stringa", receiver.toString()), line);

        updatedReceiver = receiver;
        switch (method)
        {
            case "isnumeric":
            case "ènumerico":
                if (args.length != 0)
                    throw new RuntimeError("IsNumeric/Numerico non richiede argomenti", line);
                return Value.ofBoolean(isNumericString(receiver.str));

            case "isalpha":
            case "èalfabetico":
                if (args.length != 0)
                    throw new RuntimeError("IsAlpha/Alfabetico non richiede argomenti", line);
                return Value.ofBoolean(isAlphaString(receiver.str));

            case "isalphaNum":
            case "èalfanumerico":
                if (args.length != 0)
                    throw new RuntimeError("IsAlphaNum/Alfanumerico non richiede argomenti", line);
                return Value.ofBoolean(isAlphaNumString(receiver.str));

            case "isdigit":
            case "ècifra":
                if (args.length != 0)
                    throw new RuntimeError("IsDigit/Cifra non richiede argomenti", line);
                return Value.ofBoolean(isDigitString(receiver.str));

            case "iswhite":
            case "isspace":
            case "èspazio":
                if (args.length != 0)
                    throw new RuntimeError("IsWhite/Spazio non richiede argomenti", line);
                return Value.ofBoolean(isWhiteString(receiver.str));

            case "isupper":
            case "èmaiuscolo":
                if (args.length != 0)
                    throw new RuntimeError("IsUpper/Maiuscolo non richiede argomenti", line);
                return Value.ofBoolean(isUpperString(receiver.str));

            case "islower":
            case "èminuscolo":
                if (args.length != 0)
                    throw new RuntimeError("IsLower/Minuscolo non richiede argomenti", line);
                return Value.ofBoolean(isLowerString(receiver.str));

            case "ishexdigit":
            case "èesadecimale":
                if (args.length != 0)
                    throw new RuntimeError("IsHexDigit/Esadecimale non richiede argomenti", line);
                return Value.ofBoolean(isHexDigitString(receiver.str));

            case "isascii":
            case "èascii":
                if (args.length != 0)
                    throw new RuntimeError("IsASCII/ASCII non richiede argomenti", line);
                return Value.ofBoolean(isAsciiString(receiver.str));

            case "toupper":
            case "maiuscolo":
            case "maiuscola":
                if (args.length != 0)
                    throw new RuntimeError("ToUpper/Maiuscolo non richiede argomenti", line);
                return Value.ofString(toUpperString(receiver.str));

            case "tolower":
            case "minuscolo":
            case "minuscola":
                if (args.length != 0)
                    throw new RuntimeError("ToLower/Minuscolo non richiede argomenti", line);
                return Value.ofString(toLowerString(receiver.str));

            default:
                throw new RuntimeError(format("metodo '%s' non supportato per stringhe", method), line);
        }
    }

    Value callListMethod(Value receiver, string method, Value[] args, size_t line, out Value updatedReceiver)
    {
        if (!receiver.isList)
            throw new RuntimeError(format("il valore '%s' non è un vettore", receiver.toString()), line);

        Value[] list = receiver.list.dup;
        updatedReceiver = receiver;
        switch (method)
        {
            case "push":
            case "aggiungi":
                if (args.length != 1)
                    throw new RuntimeError("Push/Aggiungi richiede 1 argomento", line);
                list ~= args[0];
                return Value.ofList(list);

            case "pop":
            case "estrai":
                if (args.length > 1)
                    throw new RuntimeError("Pop/Estrai richiede 0 o 1 argomento", line);
                if (list.length == 0)
                    throw new RuntimeError("impossibile estrarre da un vettore vuoto", line);
                long index = args.length == 1 ? cast(long) args[0].num : cast(long) list.length - 1;
                if (index < 0 || index >= list.length)
                    throw new RuntimeError("indice fuori range nel vettore", line);
                Value result = list[index];
                list = list[0 .. index] ~ list[index + 1 .. $];
                
                updatedReceiver = Value.ofList(list);

                return result;

            case "remove":
            case "rimuovi":
                if (args.length != 1)
                    throw new RuntimeError("Remove/Rimuovi richiede 1 argomento", line);
                long index = cast(long) args[0].num;
                if (index < 0 || index >= list.length)
                    throw new RuntimeError("indice fuori range nel vettore", line);
                list = list[0 .. index] ~ list[index + 1 .. $];
                return Value.ofList(list);

            case "length":
            case "lunghezza":
                if (args.length != 0)
                    throw new RuntimeError("Length/Lunghezza non richiede argomenti", line);
                return Value.ofNumber(list.length);

            case "insert":
            case "inserisci":
                if (args.length != 2)
                    throw new RuntimeError("Insert/Inserisci richiede 2 argomenti", line);
                long index = cast(long) args[0].num;
                if (index < 0 || index > list.length)
                    throw new RuntimeError("indice fuori range nel vettore", line);
                list = list[0 .. index] ~ args[1] ~ list[index .. $];
                return Value.ofList(list);

            case "get":
            case "ottieni":
                if (args.length != 1)
                    throw new RuntimeError("Get/Ottieni richiede 1 argomento", line);
                long index = cast(long) args[0].num;
                if (index < 0 || index >= list.length)
                    throw new RuntimeError("indice fuori range nel vettore", line);
                return list[index];

            case "set":
            case "imposta":
                if (args.length != 2)
                    throw new RuntimeError("Set/Imposta richiede 2 argomenti", line);
                long index = cast(long) args[0].num;
                if (index < 0 || index >= list.length)
                    throw new RuntimeError("indice fuori range nel vettore", line);
                list[index] = args[1];
                return Value.ofList(list);

            case "clear":
            case "svuota":
                if (args.length != 0)
                    throw new RuntimeError("Clear/Svuota non richiede argomenti", line);
                return Value.ofList([]);

            case "contains":
            case "contiene":
                if (args.length != 1)
                    throw new RuntimeError("Contains/Contiene richiede 1 argomento", line);
                foreach (item; list)
                    if (item.toString() == args[0].toString())
                        return Value.ofBoolean(true);
                return Value.ofBoolean(false);

            case "indexof":
            case "indiceof":
            case "indicedi":
                if (args.length != 1)
                    throw new RuntimeError("IndexOf/IndiceDi richiede 1 argomento", line);
                foreach (i, item; list)
                    if (item.toString() == args[0].toString())
                        return Value.ofNumber(cast(long) i);
                return Value.ofNumber(-1);

            case "sort":
            case "ordina":
                if (args.length != 0)
                    throw new RuntimeError("Sort/Ordina non richiede argomenti", line);
                sort!((a, b) => compareValues(a, b) < 0)(list);
                return Value.ofList(list);

            case "reverse":
            case "inverti":
                if (args.length != 0)
                    throw new RuntimeError("Reverse/Inverti non richiede argomenti", line);
                reverse(list);
                return Value.ofList(list);

            default:
                throw new RuntimeError(format("metodo '%s' non supportato per vettori", method), line);
        }
    }

    void assignVar(string name, Value value, size_t line = 0)
    {
        foreach_reverse (i; 0 .. varStack.length)
        {
            if (name in varStack[i])
            {
                auto declaredType = lookupVarType(name);
                if (declaredType.length && !valueMatchesType(value, declaredType))
                    throw new RuntimeError(
                        format("variabile '%s' è di tipo %s", name, declaredType), line ? line : 1);
                varStack[i][name] = value;
                return;
            }
        }

        auto declaredType = lookupVarType(name);
        if (declaredType.length && !valueMatchesType(value, declaredType))
            throw new RuntimeError(
                format("variabile '%s' è di tipo %s", name, declaredType), line ? line : 1);
        varStack[$ - 1][name] = value;
    }

    void assignTarget(Expr target, Value value, size_t line)
    {
        if (auto v = cast(VariableExpr) target)
        {
            assignVar(v.name, value, line);
            return;
        }

        if (auto idx = cast(IndexExpr) target)
        {
            Value container = eval(idx.target);
            if (!container.isList)
                throw new RuntimeError(format("'%s' non è un vettore", idx.target.toString()), line);

            Value indexVal = eval(idx.index);
            if (indexVal.isString || indexVal.isBool || indexVal.isList)
                throw new RuntimeError("l'indice del vettore deve essere numerico", line);

            long index = cast(long) indexVal.num;
            if (index < 0 || index >= container.list.length)
                throw new RuntimeError("indice fuori range nel vettore", line);

            auto list = container.list.dup;
            list[index] = value;

            if (auto v = cast(VariableExpr) idx.target)
                assignVar(v.name, Value.ofList(list), line);
            else
                throw new RuntimeError("solo una variabile può essere modificata con un indice", line);
            return;
        }

        throw new RuntimeError("destinazione non assegnabile", line);
    }

    void exec(Stmt s)
    {
        final switch (s.kind)
        {
            case StmtKind.Leggi:     execLeggi(cast(LeggiStmt) s);     break;
            case StmtKind.Scrivi:    execScrivi(cast(ScriviStmt) s);   break;
            case StmtKind.Calcola:   execCalcola(cast(CalcolaStmt) s); break;
            case StmtKind.Assegna:   execAssegna(cast(AssegnaStmt) s); break;
            case StmtKind.Fine:      halted = true; break;
            case StmtKind.Se:        execSe(cast(SeStmt) s); break;
            case StmtKind.Esegui:    execEsegui(cast(EseguiStmt) s); break;
            case StmtKind.Per:       execFor(cast(ForStmt) s); break;
            case StmtKind.Continua: loopContinueRequested = true; break;
            case StmtKind.Ferma:    loopBreakRequested = true; break;
            case StmtKind.Dichiara:  execDichiara(cast(DichiaraStmt) s); break;
            case StmtKind.Inizio:    break;
            case StmtKind.Funzione:  execFunzione(cast(FunzioneStmt) s); break;
            case StmtKind.Ritorna:   execRitorna(cast(RitornaStmt) s); break;
            case StmtKind.ExprStmt:
            {
                auto exprStmt = cast(ExprStmt) s;
                eval(exprStmt.expr);
                break;
            }
        }
    }

    void execDichiara(DichiaraStmt s)
    {
        foreach (name; s.names)
        {
            if (s.typeName.length)
                varTypes[$ - 1][name] = normalizeTypeName(s.typeName);
        }
    }

    void execFunzione(FunzioneStmt s)
    {
        functions[s.name] = FunctionDef(s.name, s.params, s.paramTypes, s.returnType, s.body);
    }

    void execRitorna(RitornaStmt s)
    {
        returnValue = eval(s.value);
        returnRequested = true;
    }

    void execBlock(Stmt[] body)
    {
        pushScope();
        scope (exit) popScope();

        foreach (s; body)
        {
            exec(s);
            if (halted || loopBreakRequested || loopContinueRequested || returnRequested)
                break;
        }
    }

    void execSe(SeStmt s)
    {
        if (isTrue(eval(s.condition)))
            execBlock(s.thenBody);
        else if (s.elseBody.length)
            execBlock(s.elseBody);
    }

    void execEsegui(EseguiStmt s)
    {
        if (s.infinite)
        {
            while (!halted)
            {
                loopBreakRequested = false;
                loopContinueRequested = false;
                execBlock(s.body);
                if (loopBreakRequested)
                {
                    loopBreakRequested = false;
                    break;
                }
                if (loopContinueRequested)
                {
                    loopContinueRequested = false;
                    continue;
                }
            }
            return;
        }

        if (s.doWhile)
        {
            do
            {
                loopBreakRequested = false;
                loopContinueRequested = false;
                execBlock(s.body);
                if (loopBreakRequested)
                {
                    loopBreakRequested = false;
                    break;
                }
                if (loopContinueRequested)
                {
                    loopContinueRequested = false;
                    continue;
                }
            }
            while (!halted && isTrue(eval(s.condition)));
            return;
        }

        while (!halted && isTrue(eval(s.condition)))
        {
            loopBreakRequested = false;
            loopContinueRequested = false;
            execBlock(s.body);
            if (loopBreakRequested)
            {
                loopBreakRequested = false;
                break;
            }
            if (loopContinueRequested)
            {
                loopContinueRequested = false;
                continue;
            }
        }
    }

    void execFor(ForStmt s)
    {
        Value startVal = eval(s.start);
        Value endVal = eval(s.end);
        if (startVal.isString || endVal.isString)
            throw new RuntimeError("la variabile del for deve essere numerica", s.line);

        double step = s.hasStep ? eval(s.step).num : 1;
        if (step == 0) throw new RuntimeError("passo zero nel for", s.line);

        double current = startVal.num;
        pushScope();
        scope (exit) popScope();
        varStack[$ - 1][s.varName] = startVal;

        if (step > 0)
        {
            while (current <= endVal.num && !halted)
            {
                assignVar(s.varName, Value.ofNumber(current));
                loopBreakRequested = false;
                loopContinueRequested = false;
                returnRequested = false;
                execBlock(s.body);
                if (halted || returnRequested) break;
                if (loopBreakRequested)
                {
                    loopBreakRequested = false;
                    break;
                }
                if (loopContinueRequested)
                {
                    loopContinueRequested = false;
                    current += step;
                    continue;
                }
                current += step;
            }
        }
        else
        {
            while (current >= endVal.num && !halted)
            {
                assignVar(s.varName, Value.ofNumber(current));
                loopBreakRequested = false;
                loopContinueRequested = false;
                returnRequested = false;
                execBlock(s.body);
                if (halted || returnRequested) break;
                if (loopBreakRequested)
                {
                    loopBreakRequested = false;
                    break;
                }
                if (loopContinueRequested)
                {
                    loopContinueRequested = false;
                    current += step;
                    continue;
                }
                current += step;
            }
        }

        varStack[$ - 1][s.varName] = Value.ofNumber(current);
    }

    void execLeggi(LeggiStmt s)
    {
        foreach (name; s.targets)
        {
            string input = readln();
            if (input is null) throw new RuntimeError("input terminato", s.line);
            assignVar(name, parseInput(strip(input)));
        }
    }

    void execAssegna(AssegnaStmt s)
    {
        if (s.destExpr !is null)
            assignTarget(s.destExpr, eval(s.src), s.line);
        else
            assignVar(s.dest, eval(s.src), s.line);
    }

    void execCalcola(CalcolaStmt s)
    {
        if (s.destExpr !is null)
            assignTarget(s.destExpr, eval(s.src), s.line);
        else
            assignVar(s.dest, eval(s.src), s.line);
    }

    void execScrivi(ScriviStmt s)
    {
        Value[] vals;
        foreach (a; s.args)
            vals ~= eval(a);

        if (!vals[0].isString)
            throw new RuntimeError("il primo argomento di scrivi deve essere una stringa", s.line);

        write(formatString(vals[0].str, vals[1 .. $], s.line));
    }

    string formatString(string fmt, Value[] args, size_t line)
    {
        bool hasBraces = false;
        foreach (ch; fmt)
            if (ch == '{' || ch == '}')
                hasBraces = true;

        if (!hasBraces)
            return formatValues(fmt, args, line);

        auto sb = appender!string();
        size_t positional = 0;
        size_t i = 0;

        while (i < fmt.length)
        {
            if (fmt[i] == '{')
            {
                if (i + 1 < fmt.length && fmt[i + 1] == '{')
                {
                    sb.put('{');
                    i += 2;
                    continue;
                }

                size_t end = i + 1;
                while (end < fmt.length && fmt[end] != '}')
                    end++;

                if (end >= fmt.length)
                    throw new RuntimeError("placeholder non chiuso in '}'", line);

                string inner = strip(fmt[i + 1 .. end]);
                if (inner.length == 0)
                {
                    if (positional >= args.length)
                        throw new RuntimeError("più placeholder che argomenti", line);
                    sb.put(args[positional++].toString());
                }
                else if (isDigit(inner[0]) || (inner.length > 1 && inner[0] == '-' && isDigit(inner[1])))
                {
                    long index = to!long(inner);
                    if (index < 0 || index >= args.length)
                        throw new RuntimeError(format("placeholder %s fuori range", inner), line);
                    sb.put(args[cast(size_t) index].toString());
                }
                else
                {
                    auto p = lookupVar(inner);
                    if (p is null)
                        throw new RuntimeError(format("variabile '%s' non trovata nel placeholder", inner), line);
                    sb.put((*p).toString());
                }

                i = end + 1;
                continue;
            }

            if (fmt[i] == '}')
            {
                if (i + 1 < fmt.length && fmt[i + 1] == '}')
                {
                    sb.put('}');
                    i += 2;
                    continue;
                }
                throw new RuntimeError("chiave '}' senza apertura '{'", line);
            }

            sb.put(fmt[i]);
            i++;
        }

        return sb.data;
    }

    // ---------- espressioni ----------

    Value evalCast(CastExpr c)
    {
        Value v = eval(c.value);
        switch (normalizeTypeName(c.targetType))
        {
            case "intero":
                if (v.isList)
                    throw new RuntimeError("non è possibile convertire un vettore in intero", c.line);
                if (v.isBool)
                    return Value.ofNumber(v.boolValue ? 1 : 0);
                if (v.isString)
                {
                    string s = strip(v.str);
                    if (s.length == 0)
                        throw new RuntimeError("impossibile convertire una stringa vuota in intero", c.line);
                    try return Value.ofNumber(to!long(s));
                    catch (ConvException)
                    {
                        throw new RuntimeError(format("impossibile convertire '%s' in intero", v.str), c.line);
                    }
                }
                return Value.ofNumber(cast(long) v.num);

            case "reale":
                if (v.isList)
                    throw new RuntimeError("non è possibile convertire un vettore in reale", c.line);
                if (v.isBool)
                    return Value.ofNumber(v.boolValue ? 1.0 : 0.0);
                if (v.isString)
                {
                    string s = strip(v.str);
                    if (s.length == 0)
                        throw new RuntimeError("impossibile convertire una stringa vuota in reale", c.line);
                    try return Value.ofNumber(to!double(s));
                    catch (ConvException)
                    {
                        throw new RuntimeError(format("impossibile convertire '%s' in reale", v.str), c.line);
                    }
                }
                return Value.ofNumber(v.num);

            case "stringa":
                return Value.ofString(v.toString());

            case "booleano":
                if (v.isBool) return v;
                if (v.isString)
                {
                    string s = toLower(strip(v.str));
                    return Value.ofBoolean(s.length > 0 && s != "0" && s != "false" && s != "falso");
                }
                if (v.isList)
                    return Value.ofBoolean(v.list.length > 0);
                return Value.ofBoolean(v.num != 0);

            default:
                throw new RuntimeError(format("tipo '%s' non supportato nel cast", c.targetType), c.line);
        }
    }

    Value eval(Expr e)
    {
        final switch (e.kind)
        {
            case ExprKind.Number:
                return Value.ofNumber((cast(NumberExpr) e).value);
            case ExprKind.String:
                return Value.ofString((cast(StringExpr) e).value);
            case ExprKind.Boolean:
                return Value.ofBoolean((cast(BooleanExpr) e).value);
            case ExprKind.List:
            {
                auto listExpr = cast(ListExpr) e;
                Value[] items;
                foreach (item; listExpr.items)
                    items ~= eval(item);
                return Value.ofList(items);
            }
            case ExprKind.Variable:
            {
                string name = (cast(VariableExpr) e).name;
                auto p = lookupVar(name);
                if (p is null)
                    throw new RuntimeError(
                        format("variabile '%s' usata prima di essere assegnata", name), e.line);
                return *p;
            }
            case ExprKind.Index:
            {
                auto idx = cast(IndexExpr) e;
                Value target = eval(idx.target);
                if (!target.isList)
                    throw new RuntimeError(format("'%s' non è un vettore", idx.target.toString()), e.line);
                Value indexVal = eval(idx.index);
                if (indexVal.isString || indexVal.isBool || indexVal.isList)
                    throw new RuntimeError("l'indice del vettore deve essere numerico", e.line);
                long index = cast(long) indexVal.num;
                if (index < 0 || index >= target.list.length)
                    throw new RuntimeError("indice fuori range nel vettore", e.line);
                return target.list[index];
            }
            case ExprKind.Call:
                return evalCall(cast(CallExpr) e);
            case ExprKind.Cast:
                return evalCast(cast(CastExpr) e);
            case ExprKind.BinOp:
                return evalBinOp(cast(BinOpExpr) e);
        }
    }

    Value evalCall(CallExpr c)
    {
        Value[] args;
        foreach (a; c.args)
            args ~= eval(a);

        if (c.receiver !is null)
        {
            Value receiver = eval(c.receiver);
            if (receiver.isList)
            {
                Value updatedReceiver;
                Value result = callListMethod(receiver, c.name, args, c.line, updatedReceiver);

                if (isMutatingListMethod(c.name) && c.receiver.kind == ExprKind.Variable)
                {
                    auto v = cast(VariableExpr) c.receiver;
                    assignVar(v.name, updatedReceiver, c.line);
                }

                return result;
            }

            if (receiver.isString)
            {
                Value updatedReceiver;
                Value result = callStringMethod(receiver, c.name, args, c.line, updatedReceiver);
                return result;
            }
            throw new RuntimeError(format("il valore '%s' non supporta il metodo '%s'", 
                                    receiver.toString(), c.name), c.line);
        }

        if (auto fn = c.name in functions)
        {
            if (args.length != (*fn).params.length)
                throw new RuntimeError(
                    format("funzione '%s' richiede %s argomenti", c.name, (*fn).params.length), c.line);

            pushScope();
            scope (exit) popScope();

            foreach (i, p; (*fn).params)
            {
                if (i < (*fn).paramTypes.length && (*fn).paramTypes[i].length && 
                    !valueMatchesType(args[i], (*fn).paramTypes[i]))
                    throw new RuntimeError(
                        format("parametro '%s' di '%s' deve essere di tipo %s", 
                                p, c.name, (*fn).paramTypes[i]), c.line);
                varStack[$ - 1][p] = args[i];
            }

            returnRequested = false;
            returnValue = Value.init;
            foreach (stmt; (*fn).body)
            {
                exec(stmt);
                if (returnRequested)
                {
                    Value result = returnValue;
                    if ((*fn).returnType.length && !valueMatchesType(result, (*fn).returnType))
                        throw new RuntimeError(
                            format("funzione '%s' deve restituire %s", c.name, (*fn).returnType), c.line);
                    returnRequested = false;
                    return result;
                }
                if (halted || loopBreakRequested || loopContinueRequested)
                    break;
            }

            throw new RuntimeError(format("funzione '%s' non restituisce un valore", c.name), c.line);
        }

        foreach (v; args)
            if (v.isString)
                throw new RuntimeError(format("la funzione '%s' richiede numeri", c.name), c.line);

        switch (c.name)
        {
            case "random":
                if (args.length != 2) throw new RuntimeError("random richiede 2 argomenti", c.line);
                return Value.ofNumber(uniform(args[0].num,args[1].num));
            case "abs":
                if (args.length != 1) throw new RuntimeError("abs richiede 1 argomento", c.line);
                return Value.ofNumber(abs(args[0].num));
            case "sqrt":
                if (args.length != 1) throw new RuntimeError("sqrt richiede 1 argomento", c.line);
                return Value.ofNumber(sqrt(args[0].num));
            case "sin":
                if (args.length != 1) throw new RuntimeError("sin richiede 1 argomento", c.line);
                return Value.ofNumber(sin(args[0].num));
            case "cos":
                if (args.length != 1) throw new RuntimeError("cos richiede 1 argomento", c.line);
                return Value.ofNumber(cos(args[0].num));
            case "tan":
                if (args.length != 1) throw new RuntimeError("tan richiede 1 argomento", c.line);
                return Value.ofNumber(tan(args[0].num));
            case "pow":
                if (args.length != 2) throw new RuntimeError("pow richiede 2 argomenti", c.line);
                return Value.ofNumber(pow(args[0].num, args[1].num));
            case "min":
                if (args.length != 2) throw new RuntimeError("min richiede 2 argomenti", c.line);
                return Value.ofNumber(min(args[0].num, args[1].num));
            case "max":
                if (args.length != 2) throw new RuntimeError("max richiede 2 argomenti", c.line);
                return Value.ofNumber(max(args[0].num, args[1].num));
            case "floor":
                if (args.length != 1) throw new RuntimeError("floor richiede 1 argomento", c.line);
                return Value.ofNumber(floor(args[0].num));
            case "ceil":
                if (args.length != 1) throw new RuntimeError("ceil richiede 1 argomento", c.line);
                return Value.ofNumber(ceil(args[0].num));
            case "round":
                if (args.length != 1) throw new RuntimeError("round richiede 1 argomento", c.line);
                return Value.ofNumber(round(args[0].num));
            case "log":
                if (args.length != 1) throw new RuntimeError("log richiede 1 argomento", c.line);
                return Value.ofNumber(log(args[0].num));
            case "exp":
                if (args.length != 1) throw new RuntimeError("exp richiede 1 argomento", c.line);
                return Value.ofNumber(exp(args[0].num));
            default:
                throw new RuntimeError(format("funzione '%s' non supportata", c.name), c.line);
        }
    }

    Value evalBinOp(BinOpExpr b)
    {
        Value l = eval(b.left);
        Value r = eval(b.right);

        // '+' con almeno una stringa = concatenazione
        if (b.op == BinOpKind.Add && (l.isString || r.isString))
            return Value.ofString(l.toString() ~ r.toString());

        switch (b.op)
        {
            case BinOpKind.Eq:
                if (l.isString || r.isString)
                    return Value.ofBoolean((l.toString() == r.toString()));
                if (l.isBool || r.isBool)
                    return Value.ofBoolean((boolValueOf(l) == boolValueOf(r)));
                return Value.ofBoolean((l.num == r.num));
            case BinOpKind.NotEq:
                if (l.isString || r.isString)
                    return Value.ofBoolean((l.toString() != r.toString()));
                if (l.isBool || r.isBool)
                    return Value.ofBoolean((boolValueOf(l) != boolValueOf(r)));
                return Value.ofBoolean((l.num != r.num));
            case BinOpKind.Less:
                if (l.isString || r.isString)
                    return Value.ofBoolean((l.toString() < r.toString()));
                return Value.ofBoolean((l.num < r.num));
            case BinOpKind.LessEq:
                if (l.isString || r.isString)
                    return Value.ofBoolean((l.toString() <= r.toString()));
                return Value.ofBoolean((l.num <= r.num));
            case BinOpKind.Greater:
                if (l.isString || r.isString)
                    return Value.ofBoolean((l.toString() > r.toString()));
                return Value.ofBoolean((l.num > r.num));
            case BinOpKind.GreaterEq:
                if (l.isString || r.isString)
                    return Value.ofBoolean((l.toString() >= r.toString()));
                return Value.ofBoolean((l.num >= r.num));
            case BinOpKind.And:
                return Value.ofBoolean((isTrue(l) && isTrue(r)));
            case BinOpKind.Or:
                return Value.ofBoolean((isTrue(l) || isTrue(r)));
            default:
                break;
        }

        if (l.isString || r.isString)
            throw new RuntimeError(
                format("l'operatore '%s' richiede due numeri", opSymbol(b.op)), b.line);

        final switch (b.op)
        {
            case BinOpKind.Add: return Value.ofNumber(l.num + r.num);
            case BinOpKind.Sub: return Value.ofNumber(l.num - r.num);
            case BinOpKind.Mul: return Value.ofNumber(l.num * r.num);
            case BinOpKind.Div:
                if (r.num == 0) throw new RuntimeError("divisione per zero", b.line);
                return Value.ofNumber(l.num / r.num);
            case BinOpKind.IntDiv:
                if (r.num == 0) throw new RuntimeError("divisione intera per zero", b.line);
                return Value.ofNumber(cast(long)(l.num / r.num));
            case BinOpKind.Mod:
                if (r.num == 0) throw new RuntimeError("modulo per zero", b.line);
                return Value.ofNumber(l.num % r.num);
            case BinOpKind.Eq:
            case BinOpKind.NotEq:
            case BinOpKind.Less:
            case BinOpKind.LessEq:
            case BinOpKind.Greater:
            case BinOpKind.GreaterEq:
            case BinOpKind.And:
            case BinOpKind.Or:
                assert(false, "booleani già gestiti sopra");
        }
    }

    static bool boolValueOf(Value v)
    {
        if (v.isBool) return v.boolValue;
        if (v.isString) return v.str.length > 0;
        return v.num != 0;
    }

    static bool isTrue(Value v)
    {
        return boolValueOf(v);
    }

    static Value parseInput(string s)
    {
        string trimmed = s.strip();
        string lower;
        foreach (ch; trimmed)
            lower ~= toLower(ch);

        if (lower == "vero" || lower == "true")
            return Value.ofBoolean(true);
        if (lower == "falso" || lower == "false")
            return Value.ofBoolean(false);
        try return Value.ofNumber(to!double(trimmed));
        catch (ConvException) return Value.ofString(trimmed);
    }
}
