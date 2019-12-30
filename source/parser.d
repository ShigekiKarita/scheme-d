module parser;

import std.container;

import sumtype;
import pegged.grammar;


mixin(grammar(`
LispParser:
    Body < (Value / Comment)*
    Comment <: ';' (!endOfLine .)* endOfLine
    SExpr < :'(' (Value / Comment)* :')'

    Value < Number / True / False / Atom / String / SExpr / QuotedValue
    QuotedValue <- quote Value
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

    Number < Float / Integer
    Float <~ Integer '.' Digit*
    Integer <~ '-'? ('0' / [1-9] Digit*)
    Digit  <- [0-9]

    True <- "#t"
    False <- "#f"
`));

struct Atom { string name; }
struct List
{
    LispVal*[] data;
    alias data this;
}
struct DottedList
{
    LispVal*[] data;
    LispVal* tail;
}
alias Integer = long;
alias Float = double;
alias LispVal = SumType!(
    Atom,
    List,
    DottedList,
    Integer,
    Float,
    string,
    bool);

LispVal*[] toAST(ParseTree tree)
{
    import std.conv: to;

    switch (tree.name)
    {
        // abstract values
        case "LispParser":
        case "LispParser.Value":
        case "LispParser.Number":
            assert(tree.children.length == 1);
            return toAST(tree.children[0]);
        case "LispParser.Body":
            typeof(return) ret;
            foreach (ref child; tree.children)
            {
                ret ~= toAST(child);
            }
            return ret;
        case "LispParser.QuotedValue":
            assert(tree.children.length <= 1, "The quoted arg should be one or nil.");
            auto quote = new LispVal(Atom("quote"));
            auto arg = tree.children.length == 0 ? new LispVal(List()) : toAST(tree.children[0])[0];
            return [new LispVal(List([quote, arg]))];
        case "LispParser.SExpr":
            List ls;
            foreach (ref child; tree.children)
            {
                ls.data ~= toAST(child);
            }
            return [new LispVal(ls)];
        // single value
        case "LispParser.True":
        case "LispParser.False":
            return [new LispVal(tree.matches[0] == "#t")];
        case "LispParser.Integer":
            return [new LispVal(to!Integer(tree.matches[0]))];
        case "LispParser.Float":
            return [new LispVal(to!Float(tree.matches[0]))];
        case "LispParser.Quote":
            return [new LispVal(Atom("quote"))];
        case "LispParser.Atom":
            return [new LispVal(Atom(tree.matches[0]))];
        case "LispParser.String":
            return [new LispVal(tree.matches[0])];
        default:
            assert(false, "unknown name: " ~ tree.name);
    }
}

auto unwrap(T)(LispVal* x) { return tryMatch!((T t) => t)(*x); }

unittest
{
    import std.stdio;
    auto p = LispParser("
(f0 #t #f '(1 0.2) '())

; (1 2 . 3))

(f1 \"あいうえお\n\"
    ;; comment
    (+ 20 -30))

#t
");
    writeln(p);
    auto ast = p.toAST;
    assert(ast.length == 3);

    // (f0 #t #f '(1 0.2) '())
    auto sexp0 = ast[0].unwrap!List;
    assert(sexp0.length == 5);
    // f0
    assert(sexp0[0].unwrap!Atom.name == "f0");
    // #t
    assert(sexp0[1].unwrap!bool == true);
    // #f
    assert(sexp0[2].unwrap!bool == false);
    // '(1 2)
    auto q = sexp0[3].unwrap!List;
    assert(q[0].unwrap!Atom.name == "quote");
    auto xs = q[1].unwrap!List;
    assert(xs.length == 2);
    assert(xs[0].unwrap!Integer == 1);
    assert(xs[1].unwrap!Float == 0.2);
    // '()
    auto nil = sexp0[4].unwrap!List;
    assert(nil.length == 2);
    assert(nil[0].unwrap!Atom.name == "quote");
    assert(nil[1].unwrap!List.length == 0);

    // (f1 "string"
    //     ;; comment
    //     (+ 20 -30))
    auto sexp1 = ast[1].unwrap!List;
    assert(sexp1.length == 3);
    assert(sexp1[0].unwrap!Atom.name == "f1");
    assert(sexp1[1].unwrap!string == "あいうえお\n");
    auto addexp = sexp1[2].unwrap!List;
    assert(addexp[0].unwrap!Atom.name == "+");
    assert(addexp[1].unwrap!Integer == 20);
    assert(addexp[2].unwrap!Integer == -30);

    assert(ast[2].unwrap!bool);
}

