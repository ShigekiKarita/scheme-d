import std.stdio;
import std.typecons;

import sumtype;
import pegged.grammar;


mixin(grammar(`
LispParser:
    Body < SExpr* / Comment
    Comment <: ';' (!endOfLine .)* endOfLine
    SExpr < :'(' (Value / Comment)* :')'
    Value < Number / List / Atom / String / True / False / SExpr
    List < quote SExpr

    Atom <~ AtomChar (AtomChar / Digit)*
    AtomChar <- [a-zA-Z] / Symbol
    Symbol <- '!' / '#' / '$' / '%' / '&' / '|'
            / '+' / '-' / '*' / '/' / ':' / '<'
            / '=' / '>' / '?' / '@' / '^' / '_' / '~'
    String <~ :doublequote Char* :doublequote
    Char   <~ backslash doublequote
            / backslash backslash
            / backslash [bfnrt]
            / (!doublequote .)

    Number <~ '-'? ('0' / [1-9] Digit* ('.' Digit*)?)
    Digit  <- [0-9]

    True <- "#t"
    False <- "#f"
`));

struct Atom { string name; }
struct List { LispVal[] data; }
struct DottedList
{
    LispVal[] data;
    LispVal* tail;
}
// TODO: support float
struct Number { long integer; }

alias LispVal = SumType!(
    Atom,
    List,
    DottedList,
    Number,
    string,
    bool);



void main(string[] args)
{
    enum input1 = `
(f0 #t #f '(1 2 3) '())

(f1 "string"
    ;; comment
    (+ 20 -30))
`;
    writeln(LispParser(input1));
    // writeln("Hello, ", args[1]);
}
