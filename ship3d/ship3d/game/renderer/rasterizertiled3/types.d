module game.renderer.rasterizertiled3.types;

import std.traits;
import core.bitop;

import game.units;
import game.utils;


enum AffineLength = 32;
enum TileSize = Size(64,64);
enum HighTileLevelCount = 1;
enum TileBufferSize = 96;
enum LowTileSize = Size(TileSize.w >> HighTileLevelCount, TileSize.h >> HighTileLevelCount);

enum MaxAreasPerTriangle = 8;
static assert(ispow2(MaxAreasPerTriangle));
enum AreaIndexShift = bsr(MaxAreasPerTriangle);
enum AreaIndexMask = MaxAreasPerTriangle - 1;

enum FillBackground = true;

enum UseDithering = false;

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


struct Tile
{
@nogc pure nothrow:
    static assert(TileBufferSize > 1);
    alias type_t = ushort;
    type_t used = 0;
    struct BuffElem
    {
        type_t index = void;
        ubyte minY   = void;
        ubyte maxY   = void;
    }
    BuffElem[TileBufferSize] buffer = void;
    enum EndFlag = 1 << (type_t.sizeof * 8 - 1);

    @property auto empty() const
    {
        return 0 == used;
    }

    @property auto length() const
    {
        return used & ~EndFlag;
    }

    @property auto covered() const
    {
        return 0 != (used & EndFlag);
    }

    @property auto full() const
    {
        assert(length <= buffer.length);
        return covered || length == buffer.length;
    }

    auto addTriangle(int index, bool finalize, int minY, int maxY)
    {
        assert(index >= 0);
        assert(index < type_t.max);
        assert(minY >= 0);
        assert(minY <= ubyte.max);
        assert(maxY >= 0);
        assert(maxY <= ubyte.max);
        assert(maxY > minY);
        assert(!full);
        buffer[length].index = cast(type_t)index;
        buffer[length].minY = cast(ubyte)minY;
        buffer[length].maxY = cast(ubyte)maxY;
        ++used;
        if(finalize)
        {
            used |= EndFlag;
        }
    }
}

struct HighTile
{
@nogc pure nothrow:
    alias type_t = ushort;
    enum UnusedFlag = type_t.max;
    enum ChildrenFlag = (1 << (type_t.sizeof * 8 - 5));
    enum ChildrenFullOffset = ((type_t.sizeof * 8) - 4);
    enum FullChildrenFlag = (ChildrenFlag | (0xf << ChildrenFullOffset));
    type_t index = UnusedFlag;

    @property auto used() const
    {
        return index < ChildrenFlag;
    }

    @property auto hasChildren() const
    {
        return 0 != (index & ChildrenFlag);
    }

    @property auto childrenFull() const
    {
        //assert(0 == (index & ~FullChildrenFlag));
        return index == FullChildrenFlag;
    }

    void set(int ind)
    {
        assert(ind >= 0);
        assert(ind < FullChildrenFlag);
        assert(!used);
        index = cast(type_t)ind;
    }

    void setChildren()
    {
        assert(!used);
        index |= ChildrenFlag;
    }

    void SetChildrenFullMask(type_t mask)
    {
        assert(mask >= 0);
        assert(mask <= 0xf);
        index |= (mask << ChildrenFullOffset);
    }
}

struct TileMask(int W, int H)
{
@nogc pure nothrow:
    static assert(W > 0);
    static assert(H > 0);
    static assert(ispow2(W));
    static assert(ispow2(H));
    enum width  = W;
    enum height = H;
    alias type_t  = SizeToUint!W;
    alias fmask_t = SizeToUint!H;

    enum FullMask = type_t.max;

    fmask_t  fmask = void;
    type_t[H] data = void;

    @property auto full() const
    {
        debug
        {
            auto val = FullMask;
            foreach(i,m;data[])
            {
                assert((m == FullMask) == (0 != (fmask & (1 << i))));
                val &= m;
            }
            assert((FullMask == val) == (FullMask == fmask));
        }
        return FullMask == fmask;
    }
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

struct PreparedTriangle
{
@nogc pure nothrow:
    TriangleArea[] areas;

    Plane wplane = void;
    Plane uplane = void;
    Plane vplane = void;
    float minW   = void;
    float maxW   = void;

    bool needSetup = true;

    void setup(VertT, TcoordT)(in VertT[] verts, in TcoordT[] tcoords, in Size size)
    {
        const w1 = verts[0].z;
        const w2 = verts[1].z;
        const w3 = verts[2].z;
        const x1 = verts[0].x;
        const x2 = verts[1].x;
        const x3 = verts[2].x;
        const y1 = verts[0].y;
        const y2 = verts[1].y;
        const y3 = verts[2].y;
        const mat = mat3_t(
            x1, y1, w1,
            x2, y2, w2,
            x3, y3, w3);

        const invMat = mat.inverse;
        wplane = Plane(invMat * vec3_t(1,1,1), size);

        const tu1 = tcoords[0].u;
        const tu2 = tcoords[1].u;
        const tu3 = tcoords[2].u;
        const tv1 = tcoords[0].v;
        const tv2 = tcoords[1].v;
        const tv3 = tcoords[2].v;
        uplane = Plane(invMat * vec3_t(tu1,tu2,tu3), size);
        vplane = Plane(invMat * vec3_t(tv1,tv2,tv3), size);

        minW = min(w1,w2,w3);
        maxW = max(w1,w2,w3);
        const wDiff = (maxW - minW);
        assert(wDiff >= 0);
        needSetup = false;
    }
}

align(16) struct Span(PosT, bool Affine)
{
pure nothrow @nogc:
    static if(!Affine)
    {
        align(16) immutable PosT dwx;
        immutable PosT dsux;
        immutable PosT dsvx;
        
        align(16) immutable PosT dwy;
        immutable PosT dsuy;
        immutable PosT dsvy;

        align(16) PosT wStart = void;
        PosT suStart = void;
        PosT svStart = void;

        align(16) PosT wCurr = void;
        PosT suCurr  = void;
        PosT svCurr  = void;

        align(16) PosT u  = void, v  = void;
        PosT u1 = void, v1 = void;
        PosT dux = void, dvx = void;
    }
    else
    {
        align(16) immutable PosT dux;
        immutable PosT dvx;
        immutable PosT duy;
        immutable PosT dvy;

        align(16) PosT uStart = void;
        PosT vStart = void;
        PosT u = void;
        PosT v = void;
        PosT u1 = void;
        PosT v1 = void;
    }

    this(PackT)(in ref PackT pack, int x, int y, in Size size)
    {
        static if(!Affine)
        {
            suStart = pack.uplane.get(x, y);
            suCurr  = suStart;
            dsux    = pack.uplane.dx;
            dsuy    = pack.uplane.dy;

            svStart = pack.vplane.get(x, y);
            svCurr  = svStart;
            dsvx    = pack.vplane.dx;
            dsvy    = pack.vplane.dy;

            wStart = pack.wplane.get(x, y);
            wCurr  = wStart;
            dwx    = pack.wplane.dx;
            dwy    = pack.wplane.dy;
        }
        else
        {
            const wdt = size.w / 2;
            const hgt = size.h / 2;
            const x1 = x + wdt;
            const y1 = y + hgt;
            const w = pack.wplane.get(x1, y1);
            dux    = pack.uplane.dx / w;
            dvx    = pack.vplane.dx / w;
            duy    = pack.uplane.dy / w;
            dvy    = pack.vplane.dy / w;

            uStart = pack.uplane.get(x1, y1) / w - (dux * wdt + duy * hgt);
            vStart = pack.vplane.get(x1, y1) / w - (dvx * wdt + dvy * hgt);
            u = uStart;
            v = vStart;
        }
    }

    void incX(int dx)
    {
        const PosT fdx = dx;
        static if(!Affine)
        {
            wCurr  += dwx * fdx;
            suCurr += dsux * fdx;
            svCurr += dsvx * fdx;

            u = u1;
            v = v1;

            u1 = suCurr / wCurr;
            v1 = svCurr / wCurr;
            dux = (u1 - u) / fdx;
            dvx = (v1 - v) / fdx;
        }
        else
        {
            u = u1;
            v = v1;

            u1 = uStart + dux * fdx;
            v1 = vStart + dvx * fdx;
        }
    }
    
    void initX()
    {
        static if(!Affine)
        {
            u1 = suCurr / wCurr;
            v1 = svCurr / wCurr;
        }
        else
        {
            u1 = uStart;
            v1 = vStart;
        }
    }

    void incY()
    {
        static if(!Affine)
        {
            wStart  += dwy;
            suStart += dsuy;
            svStart += dsvy;

            wCurr   = wStart;
            suCurr  = suStart;
            svCurr  = svStart;
        }
        else
        {
            uStart += duy;
            vStart += dvy;
        }
    }

    void incXY(T)(in T dx)
    {
        const PosT fdx = dx;
        static if(!Affine)
        {
            wStart  += dwy;
            suStart += dsuy;
            svStart += dsvy;

            wCurr   = wStart  + dwx  * fdx;
            suCurr  = suStart + dsux * fdx;
            svCurr  = svStart + dsvx * fdx;

            u1 = suCurr / wCurr;
            v1 = svCurr / wCurr;
        }
        else
        {
            uStart += duy;
            vStart += dvy;

            u1 = uStart + dux * fdx;
            v1 = vStart + dvx * fdx;
        }
    }

    void incXY()
    {
        static if(!Affine)
        {
            wStart  += dwy;
            suStart += dsuy;
            svStart += dsvy;

            wCurr   = wStart;
            suCurr  = suStart;
            svCurr  = svStart;

            u1 = suCurr / wCurr;
            v1 = svCurr / wCurr;
        }
        else
        {
            uStart += duy;
            vStart += dvy;

            u1 = uStart;
            v1 = vStart;
        }
    }

    auto calcMaxD(T)(in T dx) const
    {
        static if(!Affine)
        {
            const du0 = suCurr / wCurr;
            const dv0 = svCurr / wCurr;
            const newW = (wCurr + dwx * dx);
            const du1 = (suCurr + dsux * dx) / newW;
            const dv1 = (svCurr + dsux * dx) / newW;
            return max(abs(du1 - du0),abs(dv1 - dv0));
        }
        else
        {
            return max(abs(dux * dx),abs(dvx * dx));
        }
    }
}