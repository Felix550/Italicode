import std.stdio;
import std.file;
import lexer;
import parser;
import semantic;
import interpreter;
import std.conv : text;
import std.format;


class ProgramError : Exception
{
    this(string msg, string file = __FILE__, size_t ln = __LINE__)
    {
        super(format("Errore programma: %s", msg), file, ln);
    }
}

void main(string[] args)
{
	if (args.length < 2)
		throw new ProgramError(format("Input File Mancante.\nUso: %s <file>",args[0]));
	auto lexer = Lexer.fromFile(args[1]);
	Token[] tokens = lexer.tokenize;
	
	auto root = new Parser(tokens).parse;
	auto program = new SemanticChecker().analyze(root);
	new Interpreter().run(program);
}
