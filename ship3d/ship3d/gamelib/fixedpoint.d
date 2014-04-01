module gamelib.fixedpoint;

import std.traits;

import gamelib.util;

@safe:

struct FixedPoint(int M, int N, T)
{
    static assert(M > 0);
    static assert(N > 0);
    static assert((M + N) == 8 * T.sizeof);
    static assert(isIntegral!T);

public:
    alias this_t = FixedPoint!(M, N, T);
    alias int_part = M;
    alias frac_part = N;
    alias value_t = T;
    static if(CanWiden!value_t)
    {
        enum bool can_widen = true;
        alias inter_t = Widen!value_t;
    }
    else
    {
        enum bool can_widen = false;
        alias inter_t = value_t;
    }

    enum FixedPoint epsilon = fromRaw(1);
    static if(1 == T.sizeof)
    {
        enum FixedPoint PI = fromRaw(22, 7);
    }
    else static if(2 == T.sizeof)
    {
        enum FixedPoint PI = fromRaw(355, 113);
    }
    else
    {
        enum FixedPoint PI = fromRaw(47627751, 15160384);
    }

    enum this_t Zero = 0;
    enum this_t One = 1;

    enum this_t max = fromRaw(value_t.max);
    enum this_t min = fromRaw(value_t.min);

    static auto fromRaw(in value_t x) pure nothrow
    {
        FixedPoint ret = void;
        ret.value = x;
        return ret;
    }

    static auto fromRaw(in value_t x, in value_t y) pure nothrow
    in
    {
        assert(0 != y);
    }
    body
    {
        FixedPoint ret = void;
        ret.value = shorten((cast(inter_t)x << N) / cast(inter_t)y);
        return ret;
    }

    /// Construct with an assignable value.
    this(U)(in U x) pure nothrow
    {
        opAssign!U(x);
    }

    ref FixedPoint opAssign(U)(in U x) pure nothrow if (isIntegral!U)
    {
        value = shorten(x * ONE); // exact
        return this;
    }

    ref FixedPoint opAssign(U)(in U x) pure nothrow if (is(U: FixedPoint!(M1, N1, T1), int M1, int N1, T1))
    {
        enum shift = frac_part - U.frac_part;
        static if(0 == shift && int_part == U.int_part)
        {
            value = x.value;
            return this;
        }
        Largest!(inter_t, U.inter_t) temp = x.value;
        static if(shift < 0)
        {
            temp >>= -shift;
        }
        else static if(shift > 0)
        {
            temp <<= shift;
        }
        value = shorten(temp);
        return this;
    }
    
    ref FixedPoint opAssign(U)(in U x) pure nothrow if (isFloatingPoint!U)
    {
        value = shorten(cast(inter_t)(x * ONE)); // truncation
        return this;
    }
    
    // casting to float
    U opCast(U)() pure const nothrow if (isFloatingPoint!U)
    {
        return cast(U)(value) / ONE;
    }
    
    // casting to integer (truncation)
    U opCast(U)() pure const nothrow if (isIntegral!U)
    {
        return cast(U)(value) >> N;
    }

    U opCast(U)() pure const nothrow if (is(U: FixedPoint!(M1, N1, T1), int M1, int N1, T1))
    {
        U ret = this;
        return ret;
    }

    ref FixedPoint opOpAssign(string op : "^^", U)(U x) pure nothrow if (isIntegral!U)
    in
    {
        assert(x >= 0);
    }
    out
    {
        assert((0 != x % 2) || value >= 0);
    }
    body
    {
        inter_t mult = value;
        inter_t val = value;
        foreach(i;0..(x - 1))
        {
            static if(can_widen)
            {
                val = (val * mult) >> N;
            }
            else
            {
                static assert(0 == N % 2);
                val = (val >> (N / 2)) * (mult >> (N / 2));
            }
        }
        value = shorten(val);
        return this;
    }

    ref FixedPoint opOpAssign(string op : ">>", U)(U x) pure nothrow if (isIntegral!U)
    in
    {
        assert(x >= 0);
    }
    body
    {
        value >>= x;
        return this;
    }

    ref FixedPoint opOpAssign(string op : "<<", U)(U x) pure nothrow if (isIntegral!U)
    in
    {
        assert(x >= 0);
    }
    body
    {
        value <<= x;
        return this;
    }
    
    ref FixedPoint opOpAssign(string op, U)(in U x) pure nothrow if(is(U : this_t))
    {
        static if (op == "+")
        {
            value += x.value;
        }
        else static if (op == "-")
        {
            value -= x.value;
        }
        else static if (op == "*")
        {
            static if(can_widen)
            {
                value = shorten((cast(inter_t)value * cast(inter_t)x.value) >> N);
            }
            else
            {
                static assert(0 == N % 2);
                value = (value >> (N / 2)) * (x.value >> (N / 2));
            }
        }
        else static if (op == "/")
        {
            assert(x.value != 0);
            static if(!can_widen)
            {
                assert(value >= (1 << (M - 2)));
            }
            value = shorten((cast(inter_t)value << N) / cast(inter_t)x.value);
        }
        else
        {
            static assert(false, "FixedPoint does not support operator " ~ op);
        }
        return this;
    }
    
    ref FixedPoint opOpAssign(string op, U)(U x) pure nothrow if (isConvertible!U && op != "^^")
    {
        return opOpAssign!op(cast(FixedPoint)x);
    }
    
    FixedPoint opBinary(string op, U)(U x) pure const nothrow if (is(U: FixedPoint) || (isConvertible!U))
    {
        FixedPoint temp = this;
        return temp.opOpAssign!op(x);
    }
    
    FixedPoint opBinaryRight(string op, U)(U x) pure const nothrow if (isConvertible!U)
    {
        FixedPoint temp = x;
        return temp.opOpAssign!op(this);
    }
    
    bool opEquals(U)(in U other) pure const nothrow if(is(U : this_t))
    {
        return value == other.value;
    }
    
    bool opEquals(U)(in U other) pure const nothrow if (isConvertible!U)
    {
        FixedPoint conv = other;
        return opEquals(conv);
    }
    
    int opCmp(U)(in U other) pure const nothrow if(is(U : this_t))
    {
        if (value > other.value)
            return 1;
        else if (value < other.value)
            return -1;
        else
            return 0;
    }

    int opCmp(U)(in U other) pure const nothrow if (isConvertible!U)
    {
        auto o = cast(FixedPoint)other;
        return opCmp(o);
    }
    
    FixedPoint opUnary(string op)() pure const nothrow if (op == "+")
    {
        return this;
    }
    
    FixedPoint opUnary(string op)() pure const nothrow if (op == "-")
    {
        FixedPoint res = void;
        res.value = -value;
        return res;
    }

    value_t value;

private:
    enum value_t ONE = cast(value_t)1 << N;
    enum value_t HALF = ONE >>> 1;
    enum value_t LOW_MASK = ONE - 1;
    enum value_t HIGH_MASK = ~LOW_MASK;
    static assert((ONE & LOW_MASK) == 0);

    static bool isOk(T)(in T i) pure nothrow nothrow if(isIntegral!T)
    {
        return i <= value_t.max && i >= value_t.min;
    }

    static value_t shorten(T)(in T i) @trusted pure nothrow if(isIntegral!T)
    {
        assert(isOk(i));
        return cast(value_t)i;
    }
    
    // define types that can be converted to FixedPoint, but are not FixedPoint
    template isConvertible(T)
    {
        enum bool isConvertible = (!is(T : FixedPoint))
            && is(typeof(
                {
                T x;
                FixedPoint v = x;
            }()));
    }
}

private void isFixedPointImpl(int M, int N, T)(FixedPoint!(M,N,T) fp) {}

/// If T is a FixedPoint, this evaluates to true, otherwise false.
template isFixedPoint(T) {
    enum isFixedPoint = is(typeof(isFixedPointImpl(T.init)));
}

bool isNaN(U)(in U)      pure nothrow if(isFixedPoint!U) { return false; }
bool isInfinity(U)(in U) pure nothrow if(isFixedPoint!U) { return false; }

unittest
{
    alias FixedPoint!(4,4,byte)   fix4;
    alias FixedPoint!(8,8,short)  fix8;
    alias FixedPoint!(16,16,int)  fix16;
    alias FixedPoint!(24,8,int)   fix24_8;
    alias FixedPoint!(32,32,long) fix32_32;

    static assert(isFixedPoint!fix4);
    static assert(isFixedPoint!fix8);
    static assert(isFixedPoint!fix16);
    static assert(isFixedPoint!fix24_8);
    static assert(isFixedPoint!fix32_32);
    static assert(!isFixedPoint!int);
    static assert(!isFixedPoint!float);

    static assert(fix8.ONE == 0x0100);
    static assert(fix16.ONE == 0x00010000);
    static assert(fix24_8.ONE == 0x0100);

    fix16 a = 1, b = 2, c = 3, na = -1;
    assert(a < b);
    assert(c >= b);
    assert(a > 0);
    assert(na < 0);
    assert(a^^2 == 1);
    assert(b^^2 == 4);
    assert(c^^3 == 27);
    assert(na^^2 == 1);
    assert(na^^3 == -1);
    fix16 d;
    auto apb = a + b;
    auto bmc = b * c;
    d = a + b * c;
    assert(d.value == 7 * d.ONE);
    assert(d == 7);
    assert(32768 * (d / 32768) == 7);

    fix4 v1 = 1;
    fix8 v2 = 1;
    fix16 v3 = 1;
    fix24_8 v4 = 1;
    fix32_32 v5 = 1;

    assert(v1 == v2);
    assert(v1 == v3);
    assert(v1 == v4);
    assert(v1 == v5);
    v2 = v1;
    v3 = v1;
    v4 = v1;
    v5 = v1;
    assert(v1 == v2);
    assert(v1 == v3);
    assert(v1 == v4);
    assert(v1 == v5);

    assert(v1 == 1);
    assert(v2 == 1);
    assert(v3 == 1);
    assert(v4 == 1);
    assert(v5 == 1);

    v1 += 1;
    v2 += v1;
    v3 += v1;
    v4 += v1;
    v5 += v1;
    assert(v1 == 2);
    assert(v2 == 3);
    assert(v3 == 3);
    assert(v4 == 3);
    assert(v5 == 3);

    v2 *= v1;
    v3 *= v1;
    v4 *= v1;
    v5 *= v1;
    assert(v2 == 6);
    assert(v3 == 6);
    assert(v4 == 6);
    assert(v5 == 6);
}

auto abs(U)(in U x) pure nothrow if(isFixedPoint!U)
{
    U res = void;
    res.value = ((x.value >= 0) ? x.value : -x.value);
    return res;
}

/// Fixed point square root function by Christophe Meessen
/// https://github.com/chmike/fpsqrt
auto sqrt(U)(in U x) pure nothrow if(isFixedPoint!U)
in
{
    assert(x >= 0);
}
out(result)
{
    assert(result >= 0);
}
body
{
    alias val_t = Unsigned!(U.value_t);
    val_t r = x.value;
    val_t b = cast(val_t)1 << (8 * val_t.sizeof - 2);
    val_t q = 0;

    while(b > 0x40)
    {
        auto t = q + b;
        if( r >= t )
        {
            r -= t;
            q = t + b; // equivalent to q += 2*b
        }
        r <<= 1;
        b >>= 1;
    }

    enum bits = U.int_part;
    q >>= (bits / 2);
    static if(0 != bits % 2)
    {
        return U.fromRaw(q) / U.fromRaw(1414213562,1000000000);
    }
    else
    {
        return U.fromRaw(q);
    }
}

auto sin(U)(in U x) pure nothrow if(isFixedPoint!U)
{
    static if(__ctfe)
    {
        //taylor series
        U val = 1;
        enum j = 10;
        for (int k = j - 1; k >= 0; --k)
        {
            val = 1 - x*x/(2*k+2)/(2*k+3)*val;
        }

        import gamelib.math;
        return clamp((x * val), -U.One, U.One);
    }
    else
    {
        static assert(false,"not implemented");
    }
}

auto cos(U)(in U x) pure nothrow if(isFixedPoint!U)
{
    auto ret = sin(x + U.PI / 2);
    import gamelib.math;
    return clamp(ret, -U.One, U.One);
}

auto atan2(U)(in U y, in U x) pure nothrow if(isFixedPoint!U)
{
    import std.math;
    return cast(U)atan2(cast(real)y, cast(real)x); //TODO: fixme
}


auto hypot(U)(in U x, in U y) pure nothrow if(isFixedPoint!U)
out(result)
{
    assert(result >= 0);
}
body
{
    static if(16 == U.int_part && 16 == U.frac_part)
    {
        //fixed point hypot from TarasB
        U dx = abs(x);
        U dy = abs(y);
        U result;
        if (dx>dy) 
        {
            dy = (dy>>1) - (dx>>3);
            if (dy>=0) result = dx+dy; else result = dx;
        }
        else
        {
            dx = (dx>>1) - (dy>>3);
            if (dx>=0) result = dx+dy; else result = dy;
        }

        if (result.value>=5)
        {
            U revr = 1/result;
            return (result + x*(x*revr)+y*(y*revr))>>1;
        } 
        else
        {
            return result;
        }
    }
    else
    {
        if(0 == x && 0 == y) return cast(U)0;
        import gamelib.math: min, max;
        U x1 = abs(x);
        U y1 = abs(y);
        U t = min(x1,y1);
        x1 = max(x1,y1);
        assert(x1 != 0);
        t = t / x1;
        t = 1 + t ^^ 2;
        return x1 * sqrt(t);
    }
}

void testFixedPointFuncs(U)()
{
    alias fix = U;
    enum precision = fix.fromRaw(25,65536);
    import gamelib.math: almost_equal, min, max;

    //abs
    fix a = 123;
    fix b = abs(a);
    assert(a == b);
    assert(123 == b);
    a = -123;
    b = abs(a);
    assert(a == -b);
    assert(123 == b);

    //sqrt
    assert(0 == sqrt(cast(fix)0));
    assert(almost_equal(1,  sqrt(cast(fix)1),   precision));
    assert(almost_equal(2,  sqrt(cast(fix)4),   precision));
    assert(almost_equal(3,  sqrt(cast(fix)9),   precision));
    assert(almost_equal(4,  sqrt(cast(fix)16),  precision));
    assert(almost_equal(5,  sqrt(cast(fix)25),  precision));
    assert(almost_equal(16, sqrt(cast(fix)256), precision));

    //trig
    enum trigPrecision = fix.fromRaw(20,65536); //TODO: fix trig precision issues in compile time
    static assert(0 == sin(cast(fix)0));
    static assert(1 == sin(cast(fix)(fix.PI / 2)));
    static assert(almost_equal(0, sin(cast(fix)(fix.PI)), trigPrecision)); 
    static assert(almost_equal(-1, sin(cast(fix)(fix.PI + fix.PI / 2)), trigPrecision));

    static assert(almost_equal(1, cos(cast(fix)0), trigPrecision));
    static assert(almost_equal(0, cos(cast(fix)(fix.PI / 2)), trigPrecision));
    static assert(almost_equal(-1, cos(cast(fix)(fix.PI)), trigPrecision));
    static assert(almost_equal(0, cos(cast(fix)(fix.PI + fix.PI / 2)), trigPrecision));
    //import std.stdio;
    //writeln(sin(cast(fix)(fix.PI)).value);
    //writeln(cast(float)sin(cast(fix)(fix.PI)));
    /*
    import std.random;
    import std.stdio;
    Random gen;
    fix maxdev = 0;
    fix mindev = 9000;
    foreach(i;0..1000000)
    {
        fix f;
        f.value = uniform(1,int.max,gen);
        auto fixval = sqrt(f);
        import std.math;
        auto floatval = sqrt(cast(float)f);

        auto res = abs((fixval - cast(fix)floatval) / f);
        maxdev = max(maxdev, res);
        mindev = min(mindev, res);
    }

    writeln(cast(float)precision);
    writeln(cast(float)maxdev);
    writeln(cast(float)mindev);
    */
    a = 0;
    b = 0;
    assert(0 == hypot(a,b));
    a = 10;
    b = 0;
    assert(almost_equal(10, hypot(a,b), precision));
    a = 0;
    b = 10;
    assert(almost_equal(10, hypot(a,b), precision));
    a = 0;
    b = -10;
    assert(almost_equal(10, hypot(a,b), precision));
    a = -10;
    b = 0;
    assert(almost_equal(10, hypot(a,b), precision));
    a = 10;
    b = 10;
    import smath = std.math;
    assert(almost_equal(cast(fix)smath.hypot(10.0f,10.0f), hypot(a,b), precision));
}

unittest
{
    testFixedPointFuncs!(FixedPoint!(16,16,int))();
    //testFixedPointFuncs!(FixedPoint!(8,24,int))();
}