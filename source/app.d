
 // italicode Copyright (C) 2026 Felice Di Lonardo
 // This program comes with ABSOLUTELY NO WARRANTY
 // This is free software, and you are welcome to redistribute it under certain conditions

import std.stdio;
import std.file;
import std.getopt : getopt;
import std.format;
import lexer;
import parser;
import semantic;
import interpreter;
import std.conv : text;

version (Windows)
{
    import core.sys.windows.windows : SetConsoleCP, SetConsoleOutputCP;
}

class ProgramError : Exception
{
    this(string msg, string file = __FILE__, size_t ln = __LINE__)
    {
        super(format("Errore programma: %s", msg), file, ln);
    }
}

void main(string[] args)
{
    bool unicodeFix = false;

    // Alias personalizzato: -uf
    foreach (i; 1 .. args.length)
    {
        if (args[i] == "-uf")
            args[i] = "--unicodefix";
    }

    // Parsing delle opzioni
    getopt(args, "unicodefix", &unicodeFix);

    version (Windows)
    {
        if (unicodeFix)
        {
            SetConsoleCP(65_001);
            SetConsoleOutputCP(65_001);
        }
    }

    if (args.length < 2)
        throw new ProgramError(format(
            "Input file mancante.\nUso: %s <file> [--unicodefix | -uf]",
            args[0]
        ));

    auto lexer = Lexer.fromFile(args[1]);
    Token[] tokens = lexer.tokenize;

    auto root = new Parser(tokens).parse;
    auto program = new SemanticChecker().analyze(root);

    new Interpreter().run(program);
}
