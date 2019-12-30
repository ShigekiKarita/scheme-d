module parser;

import std.variant;
import std.format;
import std.conv : to, text;

import sumtype;
import pegged.grammar;


mixin(grammar(`
LispParser:
    Body < (Value / Comment)*
    Comment <: ';' (!endOfLine .)* endOfLine

    Value < Number / True / False / Atom / String / DottedList / SExpr / QuotedValue
    QuotedValue <- quote Value
    SExpr < :'(' List :')'
    DottedList < :'(' List '.' Comment* Value Comment* :')'
    List < (Value / Comment)*

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

struct Atom
{
    string name;

    string toString() { return name; }
}

// proper list: (a b c)
struct _List(T)
{
    T car;
    _List!T* cdr;

    this(T[] values...)
    {
        if (values.length == 0) return;
        this.car = values[0];
        if (values.length < 1) return;
        this.cdr = new typeof(this)(values[1 .. $]);
    }

    T front() { return this.car; }

    void popFront()
    {
        this.car = this.cdr.car;
        this.cdr = this.cdr.cdr;
    }

    bool empty() { return this.car == null; }

    auto save() { return this; }

    string toString()
    {
        if (this.empty) return "()";
        string ret = "(";
        foreach (x; this)
        {
            // NOTE: don't know why I need this...
            static if (__traits(compiles, text(*x)))
            {
                ret ~= text(*x) ~ " ";
            }
            else
            {
                ret ~= text(x) ~ " ";
            }
        }
        return ret[0 .. $-1] ~ ")";
    }
}

/// i.e., improper list: (a b . c)
struct _DottedList(T)
{
    _List!T list;
    T tail;

    string toString()
    {
        static if (__traits(compiles, text(*tail)))
        {
            auto s = text(*tail);
        }
        else
        {
            auto s = text(tail);
        }

        return list.toString[0 .. $-1] ~ " . " ~ s ~ ")";
    }
}

struct String
{
    string data;

    string toString()
    {
        import std.string : replace;
        return "\"" ~
                this.data
                .replace("\b", "\\b")
                .replace("\f", "\\f")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t")
                ~ "\"";
    }
}

struct Bool
{
    bool data;
    alias data this;
    string toString() { return data ? "#t" : "#f"; }
}

alias Integer = long;
alias Float = double;
alias LispVal = Algebraic!(
    Atom,
    _List!(This*),
    _DottedList!(This*),
    Integer,
    Float,
    String,
    Bool);

alias List = _List!(LispVal*);
alias DottedList = _DottedList!(LispVal*);

unittest
{
    import std.traits;

    alias T = SumType!(int, This*);
    static assert(isCopyable!T);

    static assert(isCopyable!LispVal);
}


LispVal*[] toAST(ParseTree tree)
{
    import std.conv: to;

    switch (tree.name)
    {
        // abstract values
        case "LispParser":
        case "LispParser.Value":
        case "LispParser.Number":
        case "LispParser.SExpr":
            assert(tree.children.length == 1);
            return toAST(tree.children[0]);
        case "LispParser.Body":
            typeof(return) ret;
            foreach (ref child; tree.children)
            {
                ret ~= toAST(child);
            }
            return ret;
        // multiple values
        case "LispParser.QuotedValue":
            assert(tree.children.length <= 1, "The quoted arg should be one or nil.");
            auto quote = new LispVal(Atom("quote"));
            auto arg = tree.children.length == 0 ? new LispVal(List()) : toAST(tree.children[0])[0];
            return [new LispVal(List([quote, arg]))];
        case "LispParser.DottedList":
            auto list = toAST(tree.children[0])[0].unwrap!List;
            auto tail = toAST(tree.children[1])[0];
            return [new LispVal(DottedList(list, tail))];
        case "LispParser.List":
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
            return [new LispVal(Bool(tree.matches[0] == "#t"))];
        case "LispParser.Integer":
            return [new LispVal(to!Integer(tree.matches[0]))];
        case "LispParser.Float":
            return [new LispVal(to!Float(tree.matches[0]))];
        case "LispParser.Quote":
            return [new LispVal(Atom("quote"))];
        case "LispParser.Atom":
            return [new LispVal(Atom(tree.matches[0]))];
        case "LispParser.String":
            return [new LispVal(String(tree.matches[0]))];
        default:
            assert(false, "unknown name: " ~ tree.name);
    }
}

T unwrap(T)(LispVal* x)
{
    // for std.variant.Algebraic
    return *(x.peek!T);
    // for SumType
    // return tryMatch!((T t) => t)(*x);
}

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

(1 2
; foo
.
; bar
3)
");
    // writeln(p);
    auto ast = p.toAST;
    assert(ast.length == 4);

    // (f0 #t #f '(1 0.2) '())
    auto sexp0 = ast[0].unwrap!List;
    // f0
    assert(sexp0.front.unwrap!Atom.name == "f0");
    // #t
    sexp0.popFront();
    assert(sexp0.front.unwrap!Bool == true);
    // #f
    sexp0.popFront();
    assert(sexp0.front.unwrap!Bool == false);
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
    assert(sexp1.front.unwrap!Atom.name == "f1");
    sexp1.popFront();
    assert(sexp1.front.unwrap!String.data == "あいうえお\n");
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

    assert(ast[2].unwrap!Bool);

    auto dl = ast[3].unwrap!DottedList;
    assert(dl.list.front.unwrap!Integer == 1);
    dl.list.popFront();
    assert(dl.list.front.unwrap!Integer == 2);
    dl.list.popFront();
    assert(dl.list.empty);
    assert(dl.tail.unwrap!Integer == 3);

    // test pretty print
    assert(ast[0].toString == `(f0 #t #f (quote (1 0.2)) (quote ()))`);
    assert(ast[1].toString == `(f1 "あいうえお\n" (+ 20 -30))`);
    assert(ast[2].toString == `#t`);
    assert(ast[3].toString == `(1 2 . 3)`);
    // foreach (val; ast)
    // {
    //     writeln(*val);
    // }
}

