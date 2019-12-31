module schemed.object;

@safe:

/// symbol: 'a
struct Atom
{
    string name;

    string toString() { return name; }
}

/// proper list: (a b c)
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

    // NOTE: this trusted is need for text(*x)
    @trusted
    string toString()
    {
        import std.conv : text, to;

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

    // NOTE: this trusted is need for text(*x)
    @trusted
    string toString()
    {
        import std.conv : text;

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

/// string wrapper
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

/// bool wrapper
struct Bool
{
    bool data;
    alias data this;
    string toString() { return data ? "#t" : "#f"; }
}

alias Integer = long;
alias Float = double;

version (USE_SUMTYPE)
{
    import sumtype : SumType, This;
    alias SumT = SumType;
}
else
{
    import std.variant : Algebraic, This;
    alias SumT = Algebraic;
}

alias LispVal = SumT!(
    Atom,
    _List!(This*),
    _DottedList!(This*),
    Integer,
    Float,
    String,
    Bool);

alias List = _List!(LispVal*);
alias DottedList = _DottedList!(LispVal*);

version (USE_SUMTYPE) unittest
{
    import sumtype;
    import std.traits;

    alias T = SumType!(int, This*);
    static assert(isCopyable!T);

    static assert(isCopyable!LispVal);
}
