import std.stdio;
import std.stdio;

import parser;

void main(string[] args)
{
    auto parsed = LispParser(readln());
    writeln("=== ParseTree ===");
    writeln(parsed);
    auto ast = toAST(parsed);

    writeln("=== AST ===");
    foreach (val; ast)
    {
        writeln(*val);
    }
    writeln("OK");
}
