module parser;

import std.format;
import std.array;
import std.conv : to, ConvException;
import std.math : isFinite;
import std.uni : toLower;
import lexer;
import expr;

enum StmtKind
{
    Scrivi,
    Leggi,
    Inizio,
    Fine,
    Se,
    Esegui,
    Per,
    Continua,
    Ferma,
    Dichiara,
    Assegna,
    Calcola,
    Funzione,
    Ritorna,
    ExprStmt
}

class Stmt
{
    StmtKind kind;
    size_t line;
    this(StmtKind k)
    {
        this.kind = k;
    }
}

class ParseException : Exception
{
    this(string msg, Token at, string file = __FILE__, size_t ln = __LINE__)
    {
        super(format("Errore parser %s:%s: %s", at.line, at.column, msg), file, ln);
    }
}

class ScriviStmt : Stmt
{
    Expr[] args;

    this()
    {
        super(StmtKind.Scrivi);
    }

    override string toString()
    {
        string[] parts;
        foreach (a; args)
            parts ~= a.toString();
        return "SCRIVI " ~ parts.join(", ");
    }
}

class InizioStmt : Stmt
{
    this()
    {
        super(StmtKind.Inizio);
    }

    override string toString() const
    {
        return "INIZIO";
    }
}

class LeggiStmt : Stmt
{
    string[] targets;

    this()
    {
        super(StmtKind.Leggi);
    }

    override string toString() const
    {
        return "LEGGI " ~ targets.join(", ");
    }
}

class FineStmt : Stmt
{
    this()
    {
        super(StmtKind.Fine);
    }

    override string toString() const
    {
        return "FINE";
    }
}

class SeStmt : Stmt
{
    Expr condition;
    Stmt[] thenBody;
    Stmt[] elseBody;

    this()
    {
        super(StmtKind.Se);
    }

    override string toString()
    {
        return "SE " ~ condition.toString();
    }
}

class EseguiStmt : Stmt
{
    Expr condition;
    Stmt[] body;
    bool doWhile; // true => "esegui ... ripeti mentre cond"
    bool infinite; // true => "esegui ... ripeti" (loop infinito)

    this()
    {
        super(StmtKind.Esegui);
    }

    override string toString()
    {
        return "ESEGUI " ~ (condition ? condition.toString() : "");
    }
}

class ForStmt : Stmt
{
    string varName;
    Expr start;
    Expr end;
    Expr step;
    Stmt[] body;
    bool hasStep;

    this()
    {
        super(StmtKind.Per);
    }

    override string toString()
    {
        return format("PER %s DA %s A %s", varName, start.toString(), end.toString());
    }
}

class ContinuaStmt : Stmt
{
    this()
    {
        super(StmtKind.Continua);
    }

    override string toString() const
    {
        return "CONTINUA";
    }
}

class FermaStmt : Stmt
{
    this()
    {
        super(StmtKind.Ferma);
    }

    override string toString() const
    {
        return "FERMA";
    }
}

class DichiaraStmt : Stmt
{
    string[] names;
    string typeName;

    this()
    {
        super(StmtKind.Dichiara);
    }

    override string toString() const
    {
        if (typeName.length)
            return "DICHIARA " ~ names.join(", ") ~ ": " ~ typeName;
        return "DICHIARA " ~ names.join(", ");
    }
}

/// assegna dest = espressione
class AssegnaStmt : Stmt
{
    string dest;
    Expr destExpr;
    Expr src;

    this()
    {
        super(StmtKind.Assegna);
    }

    override string toString()
    {
        if (destExpr)
            return format("ASSEGNA %s = %s", destExpr.toString(), src.toString());
        return format("ASSEGNA %s = %s", dest, src.toString());
    }
}

class CalcolaStmt : Stmt
{
    string dest;
    Expr destExpr;
    Expr src;

    this()
    {
        super(StmtKind.Calcola);
    }

    override string toString()
    {
        return format("ASSEGNA %s = %s", dest, src.toString());
    }
}

class FunzioneStmt : Stmt
{
    string name;
    string[] params;
    string[] paramTypes;
    string returnType;
    Stmt[] body;

    this()
    {
        super(StmtKind.Funzione);
    }

    override string toString()
    {
        string[] parts;
        foreach (i, p; params)
        {
            if (i < paramTypes.length && paramTypes[i].length)
                parts ~= format("%s:%s", p, paramTypes[i]);
            else
                parts ~= p;
        }

        if (returnType.length)
            return format("FUNZIONE %s(%s):%s", name, parts.join(", "), returnType);
        return format("FUNZIONE %s(%s)", name, parts.join(", "));
    }
}

class RitornaStmt : Stmt
{
    Expr value;

    this()
    {
        super(StmtKind.Ritorna);
    }

    override string toString()
    {
        return format("RITORNA %s", value ? value.toString() : "");
    }
}

class ExprStmt : Stmt
{
    Expr expr;

    this(Expr e)
    {
        super(StmtKind.ExprStmt);
        this.expr = e;
    }

    override string toString()
    {
        return expr ? expr.toString() : "<expr>";
    }
}

// ---------------------------------------------------------------
// Grammatica
//
//   statement  = scrivi | leggi | dichiara | assegna | inizio | fine   (poi Endline)
//   scrivi     = "scrivi" expr { "," expr }
//   leggi      = "leggi" Identifier { "," Identifier }
//   dichiara   = "dichiara" Identifier { "," Identifier }
//   assegna    = "assegna" Identifier "=" unary
//   calcola    = "calcola" Identifier "=" expr
//
//   expr       = term    { ("+" | "-") term }        (precedenza bassa, sx->dx)
//   term       = unary   { ("*" | "/" | "%") unary } (precedenza alta,  sx->dx)
//   unary      = "-" unary | primary
//   primary    = Number | String | Identifier | "(" expr ")"
// ---------------------------------------------------------------

class Parser
{
private:
    Token[] tokens;
    size_t p;
public:
    this(Token[] tokens)
    {
        this.tokens = tokens;
    }

    Stmt[] parse()
    {
        Stmt[] program;
        while (!check(TokenType.Eof))
            program ~= statment();
        return program;
    }

private:
    Token peek()
    {
        return tokens[p];
    }

    bool check(TokenType t)
    {
        return peek.type == t;
    }

    Token advance()
    {
        Token t = tokens[p];
        if (t.type != TokenType.Eof)
            p++;
        return t;
    }

    bool match(TokenType t)
    {
        if (!check(t))
            return false;
        advance;
        return true;
    }

    Token expect(TokenType t, string what)
    {
        if (!check(t))
            throw new ParseException(
                format("atteso %s, trovato %s", what, describe(peek())), peek());
        return advance();
    }

    Token expect(TokenType[] types, string what...)
    {
        foreach (t; types)
            if (check(t))
                return advance();

        throw new ParseException(
            format("atteso %s, trovato %s", what, describe(peek())),
            peek()
        );
    }

    static string describe(Token t)
    {
        if (t.type == TokenType.Endline)
            return "fine riga";
        if (t.type == TokenType.Eof)
            return "fine file";
        return format("'%s'", t.text);
    }

    // ---------- statement ----------

    Stmt statment()
    {
        Token tok = peek;
        if (tok.type != TokenType.Keyword)
            throw new ParseException(format("atteso un'istruzione, trovato %s", describe(tok)), tok);
        advance;

        Stmt s;
        switch (tok.text)
        {
        case "scrivi":
            s = parseScrivi;
            break;
        case "leggi","immetti":
            s = parseLeggi;
            break;
        case "dichiara":
            s = parseDichiara;
            break;
        case "assegna":
            s = parseAssegna;
            break;
        case "calcola":
            s = parseCalcola;
            break;
        case "se":
            s = parseSe;
            break;
        case "inizio":
            s = new InizioStmt;
            break;
        case "fine":
            s = new FineStmt;
            break;
        case "esegui":
            if (peek.type == TokenType.Keyword && peek.text == "mentre")
                s = parseEsegui;
            else if (peek.type == TokenType.Endline)
                s = parseEsegui;
            else
            {
                auto expr = expression();
                s = new ExprStmt(expr);
                s.line = tok.line;
                if (peek.type == TokenType.Endline)
                    advance();
                return s;
            }
            break;
        case "per":
            s = parseFor;
            break;
        case "continua":
            s = new ContinuaStmt;
            break;
        case "ferma":
            s = new FermaStmt;
            break;
        case "funzione":
            s = parseFunzione;
            break;
        case "ritorna":
            s = parseRitorna;
            break;
        default:
            throw new ParseException(
                format("istruzione '%s' non implementata", tok.text), tok);
        }
        s.line = tok.line;
        if (s.kind != StmtKind.Se && s.kind != StmtKind.Esegui && s.kind != StmtKind.Per && s.kind != StmtKind.Funzione)
            expect(TokenType.Endline, "fine riga");
        return s;
    }

    ForStmt parseFor()
    {
        auto s = new ForStmt;
        s.varName = expect(TokenType.Identifier, "nome di variabile").text;
        expectKeyword("da");
        s.start = expression();
        expectKeywordOrIdentifier("a");
        s.end = expression();
        if (peek.type == TokenType.Keyword && peek.text == "passo")
        {
            advance();
            s.step = expression();
            s.hasStep = true;
        }
        if (peek.type == TokenType.Endline)
            advance();
        s.body = parseBlockUntil(["ripeti"]);
        expectKeyword("ripeti");
        if (peek.type == TokenType.Endline)
            advance();
        return s;
    }

    EseguiStmt parseEsegui()
    {
        auto s = new EseguiStmt;

        if (peek.type == TokenType.Keyword && peek.text == "mentre")
        {
            advance();
            s.condition = condition();
            if (peek.type == TokenType.Endline)
                advance();
            s.body = parseBlockUntil(["ripeti"]);
            expectKeyword("ripeti");
            if (peek.type == TokenType.Endline)
                advance();
            s.doWhile = false;
            return s;
        }

        if (peek.type == TokenType.Endline)
            advance();

        s.body = parseBlockUntil(["ripeti"]);
        expectKeyword("ripeti");
        if (peek.type == TokenType.Endline)
            advance();

        if (peek.type == TokenType.Keyword && peek.text == "mentre")
        {
            advance();
            s.condition = condition();
            if (peek.type == TokenType.Endline)
                advance();
            s.doWhile = true;
            return s;
        }

        s.infinite = true;
        return s;
    }

    SeStmt parseSe()
    {
        auto s = new SeStmt;
        s.condition = condition();
        if (peek.type == TokenType.Endline)
            advance();
        expectKeyword("allora");
        if (peek.type == TokenType.Endline)
            advance();
        s.thenBody = parseBlockUntil(["altrimenti", "fine"]);
        if (peek.type == TokenType.Keyword && peek.text == "altrimenti")
        {
            advance();
            if (peek.type == TokenType.Endline)
                advance();
            s.elseBody = parseBlockUntil(["fine"]);
        }
        expectKeyword("fine");
        expectKeyword("se");
        if (peek.type == TokenType.Endline)
            advance();
        return s;
    }

    FunzioneStmt parseFunzione()
    {
        auto s = new FunzioneStmt;
        s.name = expect(TokenType.Identifier, "nome di funzione").text;
        expect(TokenType.LParen, "'('");
        if (!check(TokenType.RParen))
        {
            s.params ~= expect(TokenType.Identifier, "nome di parametro").text;
            if (match(TokenType.Colon))
            {
                Token typeTok = peek();
                if (typeTok.type != TokenType.Keyword && typeTok.type != TokenType.Identifier)
                    throw new ParseException(format("atteso un tipo per il parametro, trovato %s", describe(typeTok)), typeTok);
                advance();
                s.paramTypes ~= normalizeTypeName(typeTok.text);
            }
            else
            {
                s.paramTypes ~= "";
            }

            while (match(TokenType.Comma))
            {
                s.params ~= expect(TokenType.Identifier, "nome di parametro").text;
                if (match(TokenType.Colon))
                {
                    Token typeTok = peek();
                    if (typeTok.type != TokenType.Keyword && typeTok.type != TokenType.Identifier)
                        throw new ParseException(format("atteso un tipo per il parametro, trovato %s", describe(typeTok)), typeTok);
                    advance();
                    s.paramTypes ~= normalizeTypeName(typeTok.text);
                }
                else
                {
                    s.paramTypes ~= "";
                }
            }
        }
        expect(TokenType.RParen, "')'");
        if (match(TokenType.Colon))
        {
            Token typeTok = peek();
            if (typeTok.type != TokenType.Keyword && typeTok.type != TokenType.Identifier)
                throw new ParseException(format("atteso un tipo di ritorno, trovato %s", describe(typeTok)), typeTok);
            advance();
            s.returnType = normalizeTypeName(typeTok.text);
        }
        if (peek.type == TokenType.Endline)
            advance();
        s.body = parseBlockUntil(["fine"]);
        expectKeyword("fine");
        expectKeyword("funzione");
        if (peek.type == TokenType.Endline)
            advance();
        return s;
    }

    RitornaStmt parseRitorna()
    {
        auto s = new RitornaStmt;
        s.value = expression();
        return s;
    }

    Stmt[] parseBlockUntil(string[] stopWords)
    {
        Stmt[] body;
        while (!check(TokenType.Eof))
        {
            if (peek.type == TokenType.Keyword)
            {
                bool stop = false;
                foreach (w; stopWords)
                    if (peek.text == w)
                    {
                        stop = true;
                        break;
                    }
                if (stop)
                    break;
            }
            body ~= statment();
        }
        return body;
    }

    void expectKeyword(string kw)
    {
        if (peek.type != TokenType.Keyword || peek.text != kw)
            throw new ParseException(format("atteso '%s', trovato %s", kw, describe(peek())), peek());
        advance();
    }

    void expectKeywordOrIdentifier(string kw)
    {
        if ((peek.type == TokenType.Keyword || peek.type == TokenType.Identifier) && peek.text == kw)
        {
            advance();
            return;
        }
        throw new ParseException(format("atteso '%s', trovato %s", kw, describe(peek())), peek());
    }

    ScriviStmt parseScrivi()
    {
        auto s = new ScriviStmt;
        s.args ~= expression();
        while (match(TokenType.Comma))
            s.args ~= expression();
        return s;
    }

    LeggiStmt parseLeggi()
    {
        auto s = new LeggiStmt;
        s.targets ~= expect(TokenType.Identifier, "nome di variabile").text;
        while (match(TokenType.Comma))
            s.targets ~= expect(TokenType.Identifier, "nome di variabile").text;
        return s;
    }

    DichiaraStmt parseDichiara()
    {
        auto s = new DichiaraStmt;
        s.names ~= expect(TokenType.Identifier, "nome di variabile").text;
        while (match(TokenType.Comma))
            s.names ~= expect(TokenType.Identifier, "nome di variabile").text;

        if (match(TokenType.Colon))
        {
            Token typeTok = peek();
            if (typeTok.type != TokenType.Keyword && typeTok.type != TokenType.Identifier)
                throw new ParseException(format("atteso un tipo, trovato %s", describe(typeTok)), typeTok);
            advance();
            s.typeName = normalizeTypeName(typeTok.text);
        }

        return s;
    }

    static string normalizeTypeName(string raw)
    {
        string normalized;
        foreach (ch; raw)
            normalized ~= toLower(ch);

        switch (normalized)
        {
            case "intero":
            case "int":
                return "intero";
            case "reale":
            case "float":
            case "double":
                return "reale";
            case "stringa":
            case "string":
            case "str":
                return "stringa";
            case "booleano":
            case "bool":
            case "boolean":
                return "booleano";
            case "vettore":
            case "vector":
            case "lista":
            case "list":
                return "vettore";
            default:
                throw new ParseException(format("tipo '%s' non supportato", raw), Token(TokenType.Identifier, raw, 0, 0));
        }
    }

    AssegnaStmt parseAssegna()
    {
        auto s = new AssegnaStmt;
        Expr target = primary();
        if (auto v = cast(VariableExpr) target)
            s.dest = v.name;
        else if (auto idx = cast(IndexExpr) target)
        {
            if (auto v = cast(VariableExpr) idx.target)
                s.dest = v.name;
            else
                throw new ParseException("destinazione di assegnazione non valida", Token(TokenType.Identifier, "assegna", 0, 0));
            s.destExpr = idx;
        }
        else
            throw new ParseException("destinazione di assegnazione non valida", Token(TokenType.Identifier, "assegna", 0, 0));

        expect(TokenType.Assign, "'='");
        s.src = expression();
        return s;
    }

    CalcolaStmt parseCalcola()
    {
        auto s = new CalcolaStmt;
        Expr target = primary();
        if (auto v = cast(VariableExpr) target)
            s.dest = v.name;
        else if (auto idx = cast(IndexExpr) target)
        {
            if (auto v = cast(VariableExpr) idx.target)
                s.dest = v.name;
            else
                throw new ParseException("destinazione di calcolo non valida", Token(TokenType.Identifier, "calcola", 0, 0));
            s.destExpr = idx;
        }
        else
            throw new ParseException("destinazione di calcolo non valida", Token(TokenType.Identifier, "calcola", 0, 0));

        expect(TokenType.Assign, "'='");
        s.src = expression();
        return s;
    }

    // ---------- espressioni (precedence climbing a livelli) ----------

    /// condition = orExpr
    Expr condition()
    {
        return orExpr();
    }

    Expr orExpr()
    {
        Expr left = andExpr();
        while (check(TokenType.Or))
        {
            Token op = advance();
            Expr right = andExpr();
            left = new BinOpExpr(BinOpKind.Or, left, right, op.line);
        }
        return left;
    }

    Expr andExpr()
    {
        Expr left = comparison();
        while (check(TokenType.And))
        {
            Token op = advance();
            Expr right = comparison();
            left = new BinOpExpr(BinOpKind.And, left, right, op.line);
        }
        return left;
    }

    /// comparison = expr { ("=" | "==" | "!=" | "<>" | "<" | "<=" | ">" | ">=") expr }
    Expr comparison()
    {
        Expr left = expression();
        while (check(TokenType.Assign) || check(TokenType.Eq) || check(TokenType.NotEq)
               || check(TokenType.Less) || check(TokenType.LessEq)
               || check(TokenType.Greater) || check(TokenType.GreaterEq))
        {
            Token op = advance();
            Expr right = expression();
            left = new BinOpExpr(comparisonOpOf(op.type), left, right, op.line);
        }
        return left;
    }

    /// expr = term { ("+" | "-") term }
    Expr expression()
    {
        Expr left = term();
        while (check(TokenType.Plus) || check(TokenType.Minus))
        {
            Token op = advance();
            Expr right = term();
            left = new BinOpExpr(binOpOf(op.type), left, right, op.line);
        }
        return left;
    }

    /// term = unary { ("*" | "/" | "%") unary }
    Expr term()
    {
        Expr left = unary();
        while (check(TokenType.Star) || check(TokenType.Slash) || check(TokenType.IntDiv) || check(TokenType.Percent))
        {
            Token op = advance();
            Expr right = unary();
            left = new BinOpExpr(binOpOf(op.type), left, right, op.line);
        }
        return left;
    }

    /// unary = "-" unary | primary      (-x diventa 0 - x)
    Expr unary()
    {
        if (check(TokenType.Minus))
        {
            Token op = advance();
            Expr e = unary();
            return new BinOpExpr(BinOpKind.Sub, new NumberExpr(0, op.line), e, op.line);
        }
        return primary();
    }

    Expr parsePostfix(Expr expr)
    {
        while (true)
        {
            if (check(TokenType.LBracket))
            {
                Token lb = advance();
                Expr index = expression();
                expect(TokenType.RBracket, "']'");
                expr = new IndexExpr(expr, index, lb.line);
                continue;
            }
            if (check(TokenType.Dot))
            {
                Token dot = advance();
                Token methodTok = expect(TokenType.Identifier, "nome di metodo");
                Expr[] args;
                if (check(TokenType.LParen))
                {
                    advance();
                    if (!check(TokenType.RParen))
                    {
                        args ~= expression();
                        while (match(TokenType.Comma))
                            args ~= expression();
                    }
                    expect(TokenType.RParen, "')'");
                }
                expr = new CallExpr(expr, methodTok.text, args, dot.line);
                continue;
            }
            break;
        }
        return expr;
    }

    CastExpr parseCastExpr(Token castTok)
    {
        expect(TokenType.LParen, "'('");

        Token typeTok = peek();
        if (typeTok.type != TokenType.Keyword && typeTok.type != TokenType.Identifier && typeTok.type != TokenType.String)
            throw new ParseException(format("atteso un tipo per il cast, trovato %s", describe(typeTok)), typeTok);
        advance();
        string targetType = typeTok.type == TokenType.String ? normalizeTypeName(typeTok.text) : normalizeTypeName(typeTok.text);

        expect(TokenType.Comma, "','");
        Expr value = expression();
        expect(TokenType.RParen, "')'");
        return new CastExpr(targetType, value, castTok.line);
    }

    /// primary = Number | String | Boolean | List | Identifier | "(" expr ")"
    Expr primary()
    {
        Token t = peek();
        switch (t.type)
        {
        case TokenType.Number:
            advance();
            return parsePostfix(new NumberExpr(toNumber(t), t.line));
        case TokenType.String:
            advance();
            return parsePostfix(new StringExpr(t.text, t.line));
        case TokenType.Keyword:
            if (t.text == "vero" || t.text == "true")
            {
                advance();
                return parsePostfix(new BooleanExpr(true, t.line));
            }
            if (t.text == "falso" || t.text == "false")
            {
                advance();
                return parsePostfix(new BooleanExpr(false, t.line));
            }
            if (t.text == "cast" || t.text == "converti")
            {
                Token castTok = advance();
                return parsePostfix(parseCastExpr(castTok));
            }
            break;
        case TokenType.Identifier:
            {
                advance();
                if (check(TokenType.LParen))
                {
                    advance();
                    Expr[] args;
                    if (!check(TokenType.RParen))
                    {
                        args ~= expression();
                        while (match(TokenType.Comma))
                            args ~= expression();
                    }
                    expect(TokenType.RParen, "')'");
                    return parsePostfix(new CallExpr(t.text, args, t.line));
                }
                return parsePostfix(new VariableExpr(t.text, t.line));
            }
        case TokenType.LParen:
            {
                advance();
                Expr e = expression();
                expect(TokenType.RParen, "')'");
                return parsePostfix(e);
            }
        case TokenType.LBracket:
            {
                advance();
                Expr[] items;
                if (!check(TokenType.RBracket))
                {
                    items ~= expression();
                    while (match(TokenType.Comma))
                        items ~= expression();
                }
                expect(TokenType.RBracket, "']'");
                return parsePostfix(new ListExpr(items, t.line));
            }
        default:
            throw new ParseException(
                format("atteso un'espressione, trovato %s", describe(t)), t);
        }
        throw new ParseException(
            format("atteso un'espressione, trovato %s", describe(t)), t);
    }

    static BinOpKind binOpOf(TokenType t)
    {
        switch (t)
        {
        case TokenType.Plus:
            return BinOpKind.Add;
        case TokenType.Minus:
            return BinOpKind.Sub;
        case TokenType.Star:
            return BinOpKind.Mul;
        case TokenType.Slash:
            return BinOpKind.Div;
        case TokenType.IntDiv:
            return BinOpKind.IntDiv;
        case TokenType.Percent:
            return BinOpKind.Mod;
        default:
            assert(0, "token non è un operatore binario");
        }
    }

    static BinOpKind comparisonOpOf(TokenType t)
    {
        switch (t)
        {
        case TokenType.Assign:
        case TokenType.Eq:
            return BinOpKind.Eq;
        case TokenType.NotEq:
            return BinOpKind.NotEq;
        case TokenType.Less:
            return BinOpKind.Less;
        case TokenType.LessEq:
            return BinOpKind.LessEq;
        case TokenType.Greater:
            return BinOpKind.Greater;
        case TokenType.GreaterEq:
            return BinOpKind.GreaterEq;
        default:
            assert(0, "token non è un operatore di confronto");
        }
    }

    static double toNumber(Token t)
    {
        string s = t.text;
        bool neg = false;
        if (s[0] == '-' || s[0] == '+')
        {
            neg = s[0] == '-';
            s = s[1 .. $];
        }

        try
        {
            double v;
            if (s.length > 2 && (s[1] == 'x' || s[1] == 'X'))
                v = to!long(s[2 .. $], 16);
            else
                v = to!double(s);

            if (!isFinite(v))
                throw new ParseException(format("numero '%s' fuori range", t.text), t);

            return neg ? -v : v;
        }
        catch (ConvException)
        {
            throw new ParseException(
                format("numero '%s' non valido o fuori range", t.text), t);
        }
    }
}
