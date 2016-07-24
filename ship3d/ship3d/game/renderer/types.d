module game.renderer.types;

import std.traits;
import core.bitop;

import game.units;
import game.utils;

struct TriangleAreaEdge
{
pure nothrow @nogc:
    int x0 = 0;
    int x1 = 0;
    float xf0 = 0.0f;
    float xf1 = 0.0f;
    this(T)(in T x0_, in T x1_)
    {
        x0  = cast(int)x0_;
        x1  = cast(int)x1_;
        xf0 = cast(float)x0_;
        xf1 = cast(float)x1_;
    }
}

struct TriangleAreaEdgeIterator
{
pure nothrow @nogc:
    const float d;
    float currx;
    this(T)(in TriangleAreaEdge edge, int dy, in T x)
    {
        assert(dy > 0);
        const dx = cast(float)(edge.xf1 - edge.xf0);
        d = dx / cast(float)dy;
        currx = x;
    }

    void incY()
    {
        currx += d;
    }

    void incY(int val)
    {
        assert(val >= 0);
        currx += d * val;
    }

    @property auto x() const
    {
        return cast(int)currx;
    }
}

struct TriangleArea
{
pure nothrow @nogc:
    TriangleAreaEdge edge0;
    TriangleAreaEdge edge1;
    int y0 = 0;
    int y1 = 0;

    this(in TriangleAreaEdge e0, in TriangleAreaEdge e1, int y0_, int y1_)
    {
        edge0 = e0;
        edge1 = TriangleAreaEdge(e1.xf0 + 0.5f, e1.xf1 + 0.5f);
        y0 = y0_;
        y1 = y1_;
    }

    @property auto x0() const
    {
        return min(edge0.x0, edge0.x1);
    }

    @property auto x1() const
    {
        return max(edge1.x0, edge1.x1);
    }

    @property auto valid() const
    {
        return y1 > y0;
    }

    auto iter0() const
    {
        assert(valid);
        const dy = y1 - y0;
        return TriangleAreaEdgeIterator(edge0, dy, edge0.xf0);
    }

    auto iter1() const
    {
        assert(valid);
        const dy = y1 - y0;
        return TriangleAreaEdgeIterator(edge1, dy, edge1.xf0);
    }

    auto iter0(int y) const
    {
        assert(valid);
        assert(y >= y0);
        assert(y <= y1);
        const dy = y1 - y0;
        auto it = TriangleAreaEdgeIterator(edge0, dy, edge0.xf0);
        it.incY(y - y0);
        return it;
    }

    auto iter1(int y) const
    {
        assert(valid);
        assert(y >= y0);
        assert(y <= y1);
        const dy = y1 - y0;
        auto it = TriangleAreaEdgeIterator(edge1, dy, edge1.xf0);
        it.incY(y - y0);
        return it;
    }
}

struct HSLine
{
@nogc pure nothrow:
    alias PosT = float;
    PosT dx, dy, c;

    this(VT,ST)(in VT v1, in VT v2, in ST size)
    {
        const x1 = v1.x;
        const x2 = v2.x;
        const y1 = v1.y;
        const y2 = v2.y;
        const w1 = v1.z;
        const w2 = v2.z;
        dx = (y2 * w1 - y1 * w2) / (size.w);
        dy = (x1 * w2 - x2 * w1) / (size.h);
        c  = (x2 * y1 - x1 * y2) - dy * (size.h / 2) - dx * (size.w / 2);
    }

    auto val(T)(in T x, in T y) const
    {
        return c + dy * y + dx * x;
    }
}

struct HSPoint
{
@nogc pure nothrow:
    alias PosT = float;
    enum NumLines = 3;
    int currx = void;
    int curry = void;
    PosT[NumLines] cx = void;
    PosT[NumLines] dx = void;
    PosT[NumLines] dy = void;
    this(LineT)(int x, int y, in ref LineT lines)
    {
        foreach(i;0..NumLines)
        {
            const val = lines[i].val(x, y + 1);
            cx[i] = val;
            dx[i] = lines[i].dx;
            dy[i] = lines[i].dy;
        }
        currx = x;
        curry = y;
    }

    void incX(int val)
    {
        foreach(i;0..NumLines)
        {
            cx[i] += dx[i] * val;
        }
        currx += val;
    }

    void incY(int val)
    {
        foreach(i;0..NumLines)
        {
            cx[i] += dy[i] * val;
        }
        curry += val;
    }

    bool check() const
    {
        return cx[0] > 0 && cx[1] > 0 && cx[2] > 0;
    }

    uint vals() const
    {
        const val = (floatInvSign(cx[0]) >> 31) |
                    (floatInvSign(cx[1]) >> 30) |
                    (floatInvSign(cx[2]) >> 29);
        debug
        {
            const val2 = (cast(uint)(cx[0] >= 0) << 0) |
                         (cast(uint)(cx[1] >= 0) << 1) |
                         (cast(uint)(cx[2] >= 0) << 2);
            assert(val == val2);
        }
        return val;
    }

    auto val(int i) const
    {
        return cx[i];
    }
}

auto hsPlanesVals(LineT)(int x, int y, in ref LineT lines) pure nothrow @nogc
{
    const val = (floatInvSign(lines[0].val(x, y)) >> 31) |
                (floatInvSign(lines[1].val(x, y)) >> 30) |
                (floatInvSign(lines[2].val(x, y)) >> 29);
    debug
    {
        const val2 = (
            (cast(uint)(lines[0].val(x, y) >= 0) << 0) |
            (cast(uint)(lines[1].val(x, y) >= 0) << 1) |
            (cast(uint)(lines[2].val(x, y) >= 0) << 2));
        assert(val == val2);
    }
    return val;
}

struct Plane
{
@nogc pure nothrow:
    float dx;
    float dy;
    float c;
    this(V,S)(in V vec, in S size)
    {
        dx = vec.x / (size.w);
        dy = vec.y / (size.h);
        c = vec.z - dx * ((size.w) / cast(float)2) - dy * ((size.h) / cast(float)2);
    }

    auto get(T)(in T x, in T y) const
    {
        return c + dx * x + dy * y;
    }
}

