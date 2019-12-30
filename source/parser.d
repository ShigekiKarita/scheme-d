module parser;

import std.range;
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
// alias List = SList!(LispVal*);
struct List
{
    LispVal* car;
    List* cdr;

    this(LispVal*[] values...)
    {
        if (values.length == 0) return;

        this.car = values[0];
        if (values.length < 1) return;

        this.cdr = new List(values[1 .. $]);
    }

    auto front() { return this.car; }

    void popFront()
    {
        this.car = this.cdr.car;
        this.cdr = this.cdr.cdr;
    }

    bool empty() { return this.car == null; }

    auto save() { return this; }
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
            List ret;
            auto iter = &ret;
            foreach (ref child; tree.children)
            {
                iter.car = toAST(child)[0];
                auto tmp = new List;
                iter.cdr = tmp;
                iter = tmp;
            }
            return [new LispVal(ret)];
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
    // f0
    assert(sexp0.front.unwrap!Atom.name == "f0");
    // #t
    sexp0.popFront();
    assert(sexp0.front.unwrap!bool == true);
    // #f
    sexp0.popFront();
    assert(sexp0.front.unwrap!bool == false);
    // '(1 2)
    sexp0.popFront();
    auto q = sexp0.front.unwrap!List;
    assert(q.front.unwrap!Atom.name == "quote");
    q.popFront();
    auto xs = q.front.unwrap!List;
    assert(xs.front.unwrap!Integer == 1);
    xs.popFront();
    assert(xs.front.unwrap!Float == 0.2);
    xs.popFront();
    assert(xs.empty);
    // '()
    sexp0.popFront();
    auto nil = sexp0.front.unwrap!List;
    assert(nil.front.unwrap!Atom.name == "quote");
    nil.popFront();
    assert(nil.front.unwrap!List.empty);
    nil.popFront();
    assert(nil.empty);
    sexp0.popFront();
    assert(sexp0.empty);

    // (f1 "string"
    //     ;; comment
    //     (+ 20 -30))
    auto sexp1 = ast[1].unwrap!List;
    assert(sexp1.walkLength == 3);
    assert(sexp1.front.unwrap!Atom.name == "f1");
    sexp1.popFront();
    assert(sexp1.front.unwrap!string == "あいうえお\n");
    sexp1.popFront();
    auto addexp = sexp1.front.unwrap!List;
    assert(addexp.front.unwrap!Atom.name == "+");
    addexp.popFront();
    assert(addexp.front.unwrap!Integer == 20);
    addexp.popFront();
    assert(addexp.front.unwrap!Integer == -30);
    addexp.popFront();
    assert(addexp.empty);
    sexp1.popFront();
    assert(sexp1.empty);

    assert(ast[2].unwrap!bool);
}

