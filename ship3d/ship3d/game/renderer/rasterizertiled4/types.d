module game.renderer.rasterizertiled4.types;

import core.bitop;

import game.units;
import game.utils;

public import game.renderer.types;

enum AffineLength = 32;
enum TileSize = Size(64,64);
enum TileBufferSize = 128;

enum MaxAreasPerTriangle = 8;
static assert(ispow2(MaxAreasPerTriangle));
enum AreaIndexShift = bsr(MaxAreasPerTriangle);
enum AreaIndexMask = MaxAreasPerTriangle - 1;

enum FillBackground = true;

enum UseDithering = true;

struct Tile
{
@nogc pure nothrow:
    static assert(TileBufferSize > 0);
    struct BuffElem
    {
        ushort index = void;
        float minZ = void;
        float maxZ = void;
    }

    ubyte elemCount = 0;
    BuffElem[TileBufferSize] buffer = void;

    alias spanbuff_index_t = ubyte;
    enum InvalidIndex = spanbuff_index_t.max;
    static assert(TileBufferSize <= InvalidIndex);

    struct SpanBuff
    {
        struct Span
        {
            spanbuff_index_t index = void;
            ubyte len = void;
            static assert(TileSize.w <= len.max);
        }

        struct Line
        {
            float minZ = void;
            float maxZ = void;
            Span[TileSize.w] elem = void;
        }

        Line[TileSize.h] lines = void;
    }

    SpanBuff spanBuff = void;

    @property auto full() const
    {
        assert(elemCount <= buffer.length);
        return elemCount == buffer.length;
    }

    @property auto empty() const
    {
        assert(elemCount <= buffer.length);
        return 0 == elemCount;
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