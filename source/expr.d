module expr;

import std.array : join;
import std.conv : to;
import std.format : format;

/// Formatta un numero: interi senza ".0", altrimenti double.
string numberToString(double n)
{
    if (n > -1e15 && n < 1e15 && n == cast(long) n)
        return to!string(cast(long) n);
    return to!string(n);
}

enum ExprKind { Number, String, Boolean, List, Variable, Index, Call, BinOp }

/// Operatori binari. Per aggiungerne uno: nuovo valore qui, opSymbol(),
/// parser (tabella di precedenza) e evalBinOp() nell'interprete.
enum BinOpKind { Add, Sub, Mul, Div, IntDiv, Mod, Eq, NotEq, Less, LessEq, Greater, GreaterEq, And, Or }

string opSymbol(BinOpKind op)
{
    final switch (op)
    {
        case BinOpKind.Add: return "+";
        case BinOpKind.Sub: return "-";
        case BinOpKind.Mul: return "*";
        case BinOpKind.Div: return "/";
        case BinOpKind.IntDiv: return "//";
        case BinOpKind.Mod: return "%";
        case BinOpKind.Eq: return "==";
        case BinOpKind.NotEq: return "!=";
        case BinOpKind.Less: return "<";
        case BinOpKind.LessEq: return "<=";
        case BinOpKind.Greater: return ">";
        case BinOpKind.GreaterEq: return ">=";
        case BinOpKind.And: return "&&";
        case BinOpKind.Or: return "||";
    }
}

class Expr
{
    ExprKind kind;
    size_t line;

    this(ExprKind k, size_t line)
    {
        this.kind = k;
        this.line = line;
    }
}

class NumberExpr : Expr
{
    double value; /// già convertito dal parser

    this(double v, size_t line) { super(ExprKind.Number, line); value = v; }

    override string toString()  { return numberToString(value); }
}

class StringExpr : Expr
{
    string value;

    this(string v, size_t line) { super(ExprKind.String, line); value = v; }

    override string toString()  { return format("\"%s\"", value); }
}

class BooleanExpr : Expr
{
    bool value;

    this(bool v, size_t line) { super(ExprKind.Boolean, line); value = v; }

    override string toString()  { return value ? "vero" : "falso"; }
}

class VariableExpr : Expr
{
    string name;

    this(string n, size_t line) { super(ExprKind.Variable, line); name = n; }

    override string toString()  { return name; }
}

class IndexExpr : Expr
{
    Expr target;
    Expr index;

    this(Expr target, Expr index, size_t line)
    {
        super(ExprKind.Index, line);
        this.target = target;
        this.index = index;
    }

    override string toString()
    {
        return format("%s[%s]", target.toString(), index.toString());
    }
}

class ListExpr : Expr
{
    Expr[] items;

    this(Expr[] items, size_t line) { super(ExprKind.List, line); this.items = items; }

    override string toString()
    {
        string[] parts;
        foreach (item; items)
            parts ~= item.toString();
        return "[" ~ parts.join(", ") ~ "]";
    }
}

class CallExpr : Expr
{
    Expr receiver;
    string name;
    Expr[] args;

    this(string n, Expr[] args, size_t line)
    {
        super(ExprKind.Call, line);
        this.name = n;
        this.args = args;
    }

    this(Expr receiver, string n, Expr[] args, size_t line)
    {
        super(ExprKind.Call, line);
        this.receiver = receiver;
        this.name = n;
        this.args = args;
    }

    override string toString()
    {
        string[] parts;
        foreach (a; args)
            parts ~= a.toString();

        if (receiver)
            return format("%s.%s(%s)", receiver.toString(), name, parts.join(", "));
        return format("%s(%s)", name, parts.join(", ")); 
    }
}

/// left <op> right
class BinOpExpr : Expr
{
    BinOpKind op;
    Expr left;
    Expr right;

    this(BinOpKind op, Expr left, Expr right, size_t line)
    {
        super(ExprKind.BinOp, line);
        this.op = op;
        this.left = left;
        this.right = right;
    }

    override string toString()
    {
        return format("(%s %s %s)", left.toString(), opSymbol(op), right.toString());
    }
}
