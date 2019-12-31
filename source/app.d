import std.stdio;

import schemed.parser : LispParser, toAST;


version (unittest) {} else
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
