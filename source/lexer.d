module lexer;

import std.ascii : isDigit, isHexDigit;
import std.array : appender;
import std.file : readText;
import std.format : format;
import std.uni : isAlpha, isAlphaNum, toLower;
import std.utf : decode, UTFException;

/// Tipi di token riconosciuti dal lexer.
enum TokenType
{
    // letterali e parole
    Number,      /// 42, -3.14, 1e5, 0xFF
    String,      /// "testo" oppure 'testo' (escape già risolti)
    Keyword,     /// parola riservata (mov, add, ...)
    Identifier,  /// qualsiasi altra parola [A-Za-z_][A-Za-z0-9_]*

    // punteggiatura
    Comma,       /// ,
    Colon,       /// :
    Semicolon,   /// ;
    Dot,         /// .
    At,          /// @
    Dollar,      /// $
    LParen,      /// (
    RParen,      /// )
    LBrace,      /// {
    RBrace,      /// }
    LBracket,    /// [
    RBracket,    /// ]

    // operatori aritmetici
    Plus,        /// +
    Minus,       /// -
    Star,        /// *
    Slash,       /// /
    IntDiv,      /// //
    Percent,     /// %

    // assegnamento e confronto
    Assign,    /// =
    Eq,          /// ==
    NotEq,       /// !=
    Less,        /// <
    LessEq,      /// <=
    Greater,     /// >
    GreaterEq,   /// >=
    Arrow,       /// ->

    // logici / bit a bit
    Not,         /// !
    And,         /// &&
    Or,          /// ||
    BitAnd,      /// &
    BitOr,       /// |
    BitXor,      /// ^
    BitNot,      /// ~

    // controllo
    Endline,     /// fine di uno statement (solo se la riga conteneva token)
    Eof          /// fine del file
}

struct Token
{
    TokenType type;
    string text;   /// lessema (per le stringhe: contenuto senza apici e con escape risolti)
    size_t line;   /// riga (1-based)
    size_t column; /// colonna (1-based)

    string toString() const
    {
        if (type == TokenType.Endline) return format("Endline @%s:%s", line, column);
        if (type == TokenType.Eof)     return format("Eof @%s:%s", line, column);
        return format("%s(%s) @%s:%s", type, text, line, column);
    }
}

class LexerException : Exception
{
    size_t line;
    size_t column;

    this(string msg, size_t line, size_t column,
         string file = __FILE__, size_t ln = __LINE__)
    {
        super(format("Errore lexer %s:%s: %s", line, column, msg), file, ln);
        this.line = line;
        this.column = column;
    }
}

/// Keyword di default
immutable string[] defaultKeywords = [
    "dichiara", "assegna", "calcola", "scrivi", "leggi", "immetti", "inizio", "fine",
    "se", "esegui", "mentre", "ripeti", "allora", "altrimenti",
    "continua", "ferma", "per", "da", "passo",
    "funzione", "ritorna",
    "intero", "reale", "stringa", "booleano", "vettore", "lista",
    "cast", "converti",
    "vero", "falso", "true", "false"
];

class Lexer
{
private:
    string src;
    size_t pos;
    size_t line = 1;
    size_t col = 1;
    bool lineHasTokens; // true se sulla riga corrente c'è almeno uno statement
    Token[] tokens;
    bool[string] keywords;

public:
    /// `kw` è l'elenco delle parole riservate (case-sensitive).
    this(string source, const(string)[] kw = defaultKeywords)
    {
        src = source;
        foreach (k; kw) keywords[k] = true;
    }

    /// Crea un lexer a partire dal contenuto di un file.
    static Lexer fromFile(string path, const(string)[] kw = defaultKeywords)
    {
        return new Lexer(readText(path), kw);
    }

    /// Aggiunge una keyword a runtime (da chiamare prima di tokenize()).
    void addKeyword(string k) { keywords[k] = true; }

    /// Tokenizza tutto il sorgente. L'ultimo token è sempre Eof.
    Token[] tokenize()
    {
        pos = 0;
        line = 1;
        col = 1;
        lineHasTokens = false;
        tokens = [];

        while (!atEnd)
        {
            immutable char c = peek();

            if (c == ' ' || c == '\t' || c == '\r')
            {
                advance();
            }
            else if (c == '\n')
            {
                // Endline solo se la riga conteneva uno statement
                if (lineHasTokens)
                    tokens ~= Token(TokenType.Endline, "\n", line, col);
                advance();
                lineHasTokens = false;
            }
            else if (c == '#')
            {
                skipComment();
            }
            else if (isDigit(c) || (isSign(c) && isDigit(peekAt(1)) && !previousIsValue()))
            {
                lexNumber();
            }
            else if (c == '"' || c == '\'')
            {
                lexString();
            }
            else if (isAlpha(c) || c == '_')
            {
                lexWord();
            }
            else
            {
                lexSymbol();
            }
        }

        // ultima riga senza '\n' finale ma con uno statement
        if (lineHasTokens)
            tokens ~= Token(TokenType.Endline, "\n", line, col);

        tokens ~= Token(TokenType.Eof, "", line, col);
        return tokens;
    }

private:
    // ---------- utilità ----------

    bool atEnd() const { return pos >= src.length; }

    char peek() const { return atEnd ? '\0' : src[pos]; }

    dchar peekDchar() const
    {
        if (atEnd) return '\0';
        size_t i = pos;
        try
        {
            dchar ch;
            ch = decode(src, i);
            return ch;
        }
        catch (UTFException)
        {
            return cast(dchar) src[pos];
        }
    }

    char peekAt(size_t offset) const
    {
        return (pos + offset < src.length) ? src[pos + offset] : '\0';
    }

    dchar advanceDchar()
    {
        if (atEnd) return '\0';

        size_t i = pos;
        dchar ch;
        try
        {
            ch = decode(src, i);
        }
        catch (UTFException)
        {
            ch = cast(dchar) src[pos];
            i = pos + 1;
        }

        pos = i;
        if (ch == '\n') { line++; col = 1; }
        else           { col++; }
        return ch;
    }

    char advance()
    {
        immutable char c = src[pos++];
        if (c == '\n') { line++; col = 1; }
        else           { col++; }
        return c;
    }

    static bool isSign(char c) { return c == '+' || c == '-'; }

    /// true se il token precedente (sulla stessa riga) è un valore: serve a distinguere
    /// "a - 1" (operatore) da "mov a, -1" (numero con segno).
    bool previousIsValue() const
    {
        if (!lineHasTokens || tokens.length == 0) return false;
        switch (tokens[$ - 1].type)
        {
            case TokenType.Number:
            case TokenType.String:
            case TokenType.Identifier:
            case TokenType.RParen:
            case TokenType.RBracket:
                return true;
            default:
                return false;
        }
    }

    void add(TokenType type, string text, size_t l, size_t c)
    {
        tokens ~= Token(type, text, l, c);
        lineHasTokens = true;
    }

    // ---------- commenti ----------

    void skipComment()
    {
        // consuma fino a fine riga, il '\n' resta al ciclo principale
        while (!atEnd && peek() != '\n')
            advance();
    }

    // ---------- numeri ----------

    void lexNumber()
    {
        immutable startPos = pos;
        immutable startLine = line;
        immutable startCol = col;

        if (isSign(peek())) advance();

        if (peek() == '0' && (peekAt(1) == 'x' || peekAt(1) == 'X'))
        {
            advance(); advance();
            if (!isHexDigit(peek()))
                throw new LexerException("numero esadecimale non valido", startLine, startCol);
            while (isHexDigit(peek())) advance();
        }
        else
        {
            while (isDigit(peek())) advance();

            if (peek() == '.' && isDigit(peekAt(1)))
            {
                advance();
                while (isDigit(peek())) advance();
            }

            if (peek() == 'e' || peek() == 'E')
            {
                if (isDigit(peekAt(1)) || (isSign(peekAt(1)) && isDigit(peekAt(2))))
                {
                    advance();
                    if (isSign(peek())) advance();
                    while (isDigit(peek())) advance();
                }
            }
        }

        if (isAlpha(peek()) || peek() == '_')
            throw new LexerException("numero malformato", startLine, startCol);

        add(TokenType.Number, src[startPos .. pos], startLine, startCol);
    }

    // ---------- stringhe ----------

    void lexString()
    {
        immutable startLine = line;
        immutable startCol = col;
        immutable char quote = advance();
        auto buf = appender!string();

        while (true)
        {
            if (atEnd || peek() == '\n')
                throw new LexerException("stringa non terminata", startLine, startCol);

            char c = advance();
            if (c == quote) break;

            if (c == '\\')
            {
                if (atEnd)
                    throw new LexerException("stringa non terminata", startLine, startCol);

                immutable escLine = line;
                immutable escCol = col - 1;
                char e = advance();
                switch (e)
                {
                    case 'n':  buf.put('\n'); break;
                    case 't':  buf.put('\t'); break;
                    case 'r':  buf.put('\r'); break;
                    case '0':  buf.put('\0'); break;
                    case '\\': buf.put('\\'); break;
                    case '"':  buf.put('"');  break;
                    case '\'': buf.put('\''); break;
                    default:
                        throw new LexerException(
                            format("escape sconosciuto '\\%s'", e), escLine, escCol);
                }
            }
            else
            {
                buf.put(c);
            }
        }

        add(TokenType.String, buf.data, startLine, startCol);
    }

    // ---------- keyword / identificatori ----------

    static bool isIdentifierPart(dchar ch)
    {
        if (ch == '_') return true;
        if (ch >= '0' && ch <= '9') return true;
        if (ch <= 0x7F)
            return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
        return isAlpha(ch) || isAlphaNum(ch);
    }

    void lexWord()
    {
        immutable startPos = pos;
        immutable startLine = line;
        immutable startCol = col;

        while (true)
        {
            if (atEnd) break;
            dchar ch = peekDchar();
            if (isIdentifierPart(ch))
            {
                advanceDchar();
                continue;
            }
            break;
        }

        string word = src[startPos .. pos];
        string normalized;
        foreach (dchar ch; word)
            normalized ~= toLower(ch);

        add((normalized in keywords) ? TokenType.Keyword : TokenType.Identifier,
            normalized, startLine, startCol);
    }

    // ---------- simboli ----------

    static bool twoCharType(string s, out TokenType t)
    {
        switch (s)
        {
            case "==": t = TokenType.Eq;        return true;
            case "!=": t = TokenType.NotEq;     return true;
            case "<>": t = TokenType.NotEq;     return true;
            case "<=": t = TokenType.LessEq;    return true;
            case ">=": t = TokenType.GreaterEq; return true;
            case "->": t = TokenType.Arrow;     return true;
            case "&&": t = TokenType.And;       return true;
            case "||": t = TokenType.Or;        return true;
            case "//": t = TokenType.IntDiv;    return true;
            default:   return false;
        }
    }

    static bool oneCharType(char c, out TokenType t)
    {
        switch (c)
        {
            case ',': t = TokenType.Comma;     return true;
            case ':': t = TokenType.Colon;     return true;
            case ';': t = TokenType.Semicolon; return true;
            case '.': t = TokenType.Dot;       return true;
            case '@': t = TokenType.At;        return true;
            case '$': t = TokenType.Dollar;    return true;
            case '(': t = TokenType.LParen;    return true;
            case ')': t = TokenType.RParen;    return true;
            case '{': t = TokenType.LBrace;    return true;
            case '}': t = TokenType.RBrace;    return true;
            case '[': t = TokenType.LBracket;  return true;
            case ']': t = TokenType.RBracket;  return true;
            case '+': t = TokenType.Plus;      return true;
            case '-': t = TokenType.Minus;     return true;
            case '*': t = TokenType.Star;      return true;
            case '/': t = TokenType.Slash;     return true;
            case '%': t = TokenType.Percent;   return true;
            case '=': t = TokenType.Assign;    return true;
            case '<': t = TokenType.Less;      return true;
            case '>': t = TokenType.Greater;   return true;
            case '!': t = TokenType.Not;       return true;
            case '&': t = TokenType.BitAnd;    return true;
            case '|': t = TokenType.BitOr;     return true;
            case '^': t = TokenType.BitXor;    return true;
            case '~': t = TokenType.BitNot;    return true;
            default:  return false;
        }
    }

    void lexSymbol()
    {
        immutable startLine = line;
        immutable startCol = col;
        TokenType t;

        // operatori a due caratteri
        if (pos + 1 < src.length)
        {
            string two = src[pos .. pos + 2];
            if (twoCharType(two, t))
            {
                advance(); advance();
                add(t, two, startLine, startCol);
                return;
            }
        }

        immutable char c = peek();
        if (!oneCharType(c, t))
            throw new LexerException(
                format("carattere non valido '%s'", c), startLine, startCol);

        advance();
        add(t, [c].idup, startLine, startCol);
    }
}