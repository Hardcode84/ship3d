/**
Original comment:
gl3n.util

Authors: David Herberth
License: MIT

End of original comment.

I removed plane code and added some fancy template stuff.
*/

module gamelib.util;

private {
    import gamelib.linalg : Vector, Matrix, Quaternion;
    import gamelib.fixedpoint;

    import std.traits;
    import std.typetuple;
}

private void is_vector_impl(T, int d)(Vector!(T, d) vec) {}

/// If T is a vector, this evaluates to true, otherwise false.
template is_vector(T) {
    enum is_vector = is(typeof(is_vector_impl(T.init)));
}

private void is_matrix_impl(T, int r, int c)(Matrix!(T, r, c) mat) {}

/// If T is a matrix, this evaluates to true, otherwise false.
template is_matrix(T) {
    enum is_matrix = is(typeof(is_matrix_impl(T.init)));
}

private void is_quaternion_impl(T)(Quaternion!(T) qu) {}

/// If T is a quaternion, this evaluates to true, otherwise false.
template is_quaternion(T) {
    enum is_quaternion = is(typeof(is_quaternion_impl(T.init)));
}

unittest {
    // I need to import it here like this, otherwise you'll get a compiler
    // or a linker error depending where gl3n.util gets imported
    import gamelib.linalg;
    
    assert(is_vector!vec2);
    assert(is_vector!vec3);
    assert(is_vector!vec3d);
    assert(is_vector!vec4i);
    assert(!is_vector!int);
    assert(!is_vector!mat34);
    assert(!is_vector!quat);
    
    assert(is_matrix!mat2);
    assert(is_matrix!mat34);
    assert(is_matrix!mat4);
    assert(!is_matrix!float);
    assert(!is_matrix!vec3);
    assert(!is_matrix!quat);
    
    assert(is_quaternion!quat);
    assert(!is_quaternion!vec2);
    assert(!is_quaternion!vec4i);
    assert(!is_quaternion!mat2);
    assert(!is_quaternion!mat34);
    assert(!is_quaternion!float);
}

template TupleRange(int from, int to) if (from <= to) {
    static if (from >= to) {
        alias TupleRange = TypeTuple!();
    } else {
        alias TupleRange = TypeTuple!(from, TupleRange!(from + 1, to));
    }
}

unittest
{
    int counter = 0;
    foreach(i;TupleRange!(0,0))
    {
        ++counter;
    }
    assert(0 == counter);
    foreach(i;TupleRange!(0,2))
    {
        ++counter;
    }
    assert(2 == counter);
    counter = 0;
    foreach(i;TupleRange!(-5,2))
    {
        ++counter;
    }
    assert(7 == counter);
}

template NextType(T, TL...)
{
    static assert((TL.length == (NoDuplicates!TL).length), "Duplicates detected");
    static assert(staticIndexOf!(T,TL) >= 0, "Type not found");
    alias NextType = TL[1 + staticIndexOf!(T,TL)];
}

unittest
{
    static assert(is(NextType!(int, short,int,long) : long));
    static assert(!__traits(compiles, NextType!(int, short,int,long,long)));
    static assert(!__traits(compiles, NextType!(float, short,int,long)));
}

template Widen(T)
{
    static if(is(T : FixedPoint!(M,N,T1), int M, int N, T1))
    {
        alias Widen = FixedPoint!(M * 2,N * 2, Widen!(T.value_t));
    }
    else static if(isFloatingPoint!T)
    {
        static assert(real.sizeof > double.sizeof);;
        alias Widen = NextType!(T, TypeTuple!(float,double,real));
    }
    else static if(isSigned!T)
    {
        alias Widen = NextType!(T, TypeTuple!(byte,short,int,long));
    }
    else static if(isUnsigned!T)
    {
        alias Widen = NextType!(T, TypeTuple!(ubyte,ushort,uint,ulong));
    }
    else
    {
        static assert(false);
    }
}

template CanWiden(T)
{
    enum bool CanWiden = __traits(compiles,Widen!T);
}

template TryWiden(T)
{
    static if(CanWiden!T)
    {
        alias TryWiden = Widen!T;
    }
    else
    {
        alias TryWiden = T;
    }
}

unittest
{
    static assert(is(Widen!float : double));
    static assert(is(Widen!double : real));

    static assert(is(Widen!byte : short));
    static assert(is(Widen!short : int));
    static assert(is(Widen!int : long));

    static assert(is(Widen!ubyte : ushort));
    static assert(is(Widen!ushort : uint));
    static assert(is(Widen!uint : ulong));

    static assert(CanWiden!float);
    static assert(CanWiden!double);
    static assert(!CanWiden!real);

    static assert(CanWiden!byte);
    static assert(CanWiden!short);
    static assert(CanWiden!int);
    static assert(!CanWiden!long);

    static assert(CanWiden!ubyte);
    static assert(CanWiden!ushort);
    static assert(CanWiden!uint);
    static assert(!CanWiden!ulong);

    alias fp16 = FixedPoint!(16,16,int);
    alias fp32 = FixedPoint!(32,32,long);
    static assert(CanWiden!fp16);
    static assert(!CanWiden!fp32);
    static assert(is(Widen!fp16 : fp32));

    static assert(is(TryWiden!int : long));
    static assert(is(TryWiden!long : long));
}

