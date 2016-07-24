module game.renderer.rasterizertiled3.types;

import std.traits;
import core.bitop;

import game.units;
import game.utils;

public import game.renderer.types;

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

enum UseDithering = true;

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
        assert((covered || length == buffer.length) == (used >= buffer.length));
        return used >= buffer.length;
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
    alias type_t = uint;
    
    enum ChildrenFlag = (1 << (type_t.sizeof * 8 - 5));
    enum ChildrenFullOffset = ((type_t.sizeof * 8) - 4);
    enum FullChildrenFlag = (ChildrenFlag | (0xf << ChildrenFullOffset));
    enum UnusedFlag = cast(type_t)~FullChildrenFlag;
    type_t index = UnusedFlag;

    @property auto used() const
    {
        return index < UnusedFlag;
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
        assert(!hasChildren);
        assert(!childrenFull);
        assert(ind >= 0);
        assert(ind < UnusedFlag);
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
        assert(!used);
        assert(mask >= 0);
        assert(mask <= 0xf);
        index |= (mask << ChildrenFullOffset);
    }

    @property auto childrenFullMask() const
    {
        assert((index >> ChildrenFullOffset) <= 0xf);
        return cast(type_t)(index >> ChildrenFullOffset);
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