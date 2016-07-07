module game.renderer.rasterizerhybrid3;

import std.traits;
import std.algorithm;
import std.array;
import std.string;
import std.functional;
import std.range;

import gamelib.types;
import gamelib.util;
import gamelib.graphics.graph;
import gamelib.memory.utils;
import gamelib.memory.arrayview;

import game.units;
import game.utils;

@nogc:

struct RasterizerHybrid3(bool HasTextures, bool WriteMask, bool ReadMask, bool HasLight, bool UseCache = true)
{
    version(LDC)
    {
    import ldc.attributes;
@llvmAttr("unsafe-fp-math", "true"):
    }

    static void drawIndexedTriangle(AllocT,CtxT1,CtxT2,VertT,IndT)
        (auto ref AllocT alloc, auto ref CtxT1 outputContext, auto ref CtxT2 extContext, in VertT[] verts, in IndT[] indices) if(isIntegral!IndT)
    {
        assert(indices.length == 3);
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        drawTriangle(alloc, outputContext, extContext, pverts);
    }

private:
    enum AffineLength = 32;
    enum TileSize = Size(64,64);
    enum HighTileLevelCount = 1;
    enum TileBufferSize = 128;
    enum LowTileSize = Size(TileSize.w >> HighTileLevelCount, TileSize.h >> HighTileLevelCount);
    struct Tile
    {
        alias type_t = ushort;
        type_t used = 0;
        type_t[TileBufferSize - 1] buffer = void;
        enum EndFlag = 1 << (used.sizeof * 8 - 1);

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

        auto addTriangle(int index, bool finalize)
        {
            assert(index >= 0);
            assert(index < type_t.max);
            assert(!full);
            buffer[length] = cast(type_t)index;
            ++used;
            if(finalize)
            {
                used |= EndFlag;
            }
        }
    }

    struct HighTile
    {
        alias type_t = ushort;
        enum UnusedFlag = type_t.max;
        enum ChildrenFlag = UnusedFlag - 1;
        type_t index = UnusedFlag;

        @property auto used() const
        {
            return index != UnusedFlag && index != ChildrenFlag;
        }

        @property auto hasChildren() const
        {
            return index == ChildrenFlag;
        }

        void set(int ind)
        {
            assert(ind >= 0);
            assert(ind < ChildrenFlag);
            assert(!used);
            index = cast(type_t)ind;
        }

        void setChildren()
        {
            assert(!used);
            index = ChildrenFlag;
        }
    }

    struct TileMask(int W, int H)
    {
        static assert(W > 0);
        static assert(H > 0);
        static assert(ispow2(W));
        static assert(ispow2(H));
        static      if(1*8 == W) alias type_t = ubyte;
        else static if(2*8 == W) alias type_t = ushort;
        else static if(4*8 == W) alias type_t = uint;
        else static if(8*8 == W) alias type_t = ulong;
        else static assert(false);

        enum FullMask = type_t.max;

        type_t[H] data = void;

        @property auto full() const
        {
            auto val = FullMask;
            foreach(m;data[])
            {
                val &= m;
            }
            return FullMask == val;
        }
    }

    struct Line(PosT)
    {
        pure nothrow:
    @nogc:
        Unqual!PosT dx, dy, c;

        this(VT,ST)(in VT v1, in VT v2, in VT v3, in ST size)
        {
            const x1 = v1.x;
            const x2 = v2.x;
            const y1 = v1.y;
            const y2 = v2.y;
            const w1 = v1.z;
            const w2 = v2.z;
            dx = (y1 * w2 - y2 * w1) / (size.w);
            dy = (x1 * w2 - x2 * w1) / (size.h);
            c  = (x2 * y1 - x1 * y2) - dy * (size.h / 2) + dx * (size.w / 2);
        }

        auto val(int x, int y) const
        {
            return c + dy * y - dx * x;
        }
    }

    struct Plane(PosT)
    {
    pure nothrow @nogc:
        Unqual!PosT dx;
        Unqual!PosT dy;
        Unqual!PosT c;
        this(V,S)(in V vec, in S size)
        {
            dx = vec.x / size.w;
            dy = vec.y / size.h;
            c = vec.z - dx * (size.w / 2) - dy * (size.h / 2);
        }

        auto get(int x, int y) const
        {
            return c + dx * x + dy * y;
        }
    }

    struct LinesPack(PosT,TextT,LineT)
    {
    pure nothrow @nogc:
        alias pos_t = PosT;
        enum HasTexture = !is(TextT : void);
        alias vec2 = Vector!(PosT,2);
        alias vec3 = Vector!(PosT,3);
        alias PlaneT = Plane!(PosT);

        vec3[3] verts = void;
        PlaneT wplane = void;

        static if(HasTexture)
        {
            alias vec3tex = Vector!(TextT,3);
            alias PlaneTtex = Plane!(TextT);
            PlaneTtex uplane = void;
            PlaneTtex vplane = void;
        }
        static if(HasLight)
        {
            PlaneT refXplane = void, refYplane = void, refZplane = void;
            vec3 normal = void;
        }
        bool external = void;

        this(VT,ST)(in VT v1, in VT v2, in VT v3, in ST size, ref bool degenerate)
        {
            verts = [v1.pos.xyw,v2.pos.xyw,v3.pos.xyw];

            const w1 = v1.pos.w;
            const w2 = v2.pos.w;
            const w3 = v3.pos.w;
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const x3 = v3.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            const y3 = v3.pos.y;
            const mat = Matrix!(PosT,3,3)(
                x1, y1, w1,
                x2, y2, w2,
                x3, y3, w3);
            const d = mat.det;
            if(d <= 0 || (w1 > 0 && w2 > 0 && w3 > 0))
            {
                degenerate = true;
                return;
            }
            degenerate = false;

            const dw = 0.0001f;
            const sizeLim = 10000;
            const bool big = max(max(abs(x1 / w1), abs(x2 / w2), abs(x3 / w3)) * size.w,
                max(abs(y1 / w1), abs(y2 / w2), abs(y3 / w3)) * size.h) > sizeLim;
            external = big || almost_equal(w1, 0, dw) || almost_equal(w2, 0, dw) || almost_equal(w3, 0, dw) || (w1 * w2 < 0) || (w1 * w3 < 0);

            const invMat = mat.inverse;
            wplane = PlaneT(invMat * vec3(1,1,1), size);
            static if(HasTexture)
            {
                const tu1 = v1.tpos.u;
                const tu2 = v2.tpos.u;
                const tu3 = v3.tpos.u;
                const tv1 = v1.tpos.v;
                const tv2 = v2.tpos.v;
                const tv3 = v3.tpos.v;
                uplane = PlaneTtex(invMat * vec3tex(tu1,tu2,tu3), size);
                vplane = PlaneTtex(invMat * vec3tex(tv1,tv2,tv3), size);
            }
            static if(HasLight)
            {
                const refPos1 = v1.refPos;
                const refPos2 = v2.refPos;
                const refPos3 = v3.refPos;
                refXplane = PlaneT(invMat * vec3(refPos1.x,refPos2.x,refPos3.x), size);
                refYplane = PlaneT(invMat * vec3(refPos1.y,refPos2.y,refPos3.y), size);
                refZplane = PlaneT(invMat * vec3(refPos1.z,refPos2.z,refPos3.z), size);
                normal = cross(refPos2 - refPos1, refPos3 - refPos1).normalized;
            }
        }
    }

    struct Point(PosT)
    {
    pure nothrow @nogc:
        enum NumLines = 3;
        int currx = void;
        int curry = void;
        PosT[NumLines] cx = void;
        PosT[NumLines] dx = void;
        PosT[NumLines] dy = void;
        this(PackT,LineT)(in ref PackT p, int x, int y, in ref LineT lines)
        {
            foreach(i;0..NumLines)
            {
                const val = lines[i].val(x, y);
                cx[i] = val;
                dx[i] = -lines[i].dx;
                dy[i] =  lines[i].dy;
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
            return (cast(uint)(cx[0] > 0) << 0) |
                   (cast(uint)(cx[1] > 0) << 1) |
                   (cast(uint)(cx[2] > 0) << 2);
        }

        auto val(int i) const
        {
            return cx[i];
        }
    }

    struct Span(PosT)
    {
    pure nothrow @nogc:
        PosT wStart = void, wCurr = void;
        immutable PosT dwx, dwy;

        PosT suStart = void, svStart = void;
        PosT suCurr  = void, svCurr  = void;
        immutable PosT dsux, dsuy;
        immutable PosT dsvx, dsvy;
        PosT u  = void, v  = void;
        PosT u1 = void, v1 = void;
        PosT dux = void, dvx = void;
        pure nothrow:
        this(PackT)(in ref PackT pack, int x, int y)
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

        void incX(int dx)
        {
            suCurr += dsux * dx;
            svCurr += dsvx * dx;
            u = u1;
            v = v1;
            wCurr += dwx * dx;
            u1 = suCurr / wCurr;
            v1 = svCurr / wCurr;
            dux = (u1 - u) / dx;
            dvx = (v1 - v) / dx;
        }

        void initX()
        {
            u = u1;
            v = v1;
            u1 = suCurr / wCurr;
            v1 = svCurr / wCurr;
        }

        void incY()
        {
            wStart += dwy;
            wCurr  = wStart;

            suStart += dsuy;
            suCurr  = suStart;
            svStart += dsvy;
            svCurr  = svStart;
        }
    }

    struct LightProxy(int Len, PosT)
    {
    pure nothrow @nogc:
        int currX, currY;
        ubyte[Len] buffer;
        alias vec3 = Vector!(PosT,3);
        alias vec4 = Vector!(PosT,4);
        alias LightT = int;
        alias ColView = ArrayView!LightT;
        alias DataT = ArrayView!(ColView);
        DataT lightData;
        LightT[Len] buff = void;
        LightT l1,l2;

        this(AllocT,PackT,SpansT,CtxT)(
            auto ref AllocT alloc,
            in ref PackT pack,
            in ref SpansT spans,
            in auto ref CtxT ctx)
        {
            const minTy = spans.y0 / Len;
            const maxTy = 1 + (spans.y1 + Len - 1) / Len;
            lightData = DataT(alloc.alloc!ColView(maxTy - minTy), minTy);
            int prevMinTx = int.max;
            int prevMaxTx = 0;
            foreach(ty;minTy..maxTy)
            {
                const miny = max(spans.y0,ty * Len);
                const maxy = min(spans.y1,(ty + 1) * Len);
                int minx = int.max;
                int maxx = 0;
                foreach(y;miny..maxy)
                {
                    minx = min(minx, spans.spans[y].x0);
                    maxx = max(maxx, spans.spans[y].x1);
                }
                if(maxx >= minx || prevMaxTx >= prevMinTx)
                {
                    const minTx = minx / Len;
                    const maxTx = (maxx + Len - 1) / Len + 1;
                    const tx0 = min(minTx, prevMinTx);
                    const tx1 = max(maxTx, prevMaxTx);
                    lightData[ty] = ColView(alloc.alloc!LightT(tx1 - tx0),tx0);
                    prevMinTx = minTx;
                    prevMaxTx = maxTx;
                }
            }
            const lights = ctx.lights;
            const lightController = ctx.lightController;
            const posDx = vec4(pack.refXplane.dx,pack.refYplane.dx,pack.refZplane.dx,pack.wplane.dx) * Len;
            foreach(ty;lightData.low..lightData.high)
            {
                const row = lightData[ty];
                const y = cast(int)ty * Len;
                auto  x = cast(int)row.low * Len;
                auto pos = vec4(pack.refXplane.get(x,y),pack.refYplane.get(x,y),pack.refZplane.get(x,y),pack.wplane.get(x,y));
                foreach(tx;row.low..row.high)
                {
                    lightData[ty][tx] = lightController.calcLight(pos.xyz / pos.w,pack.normal,lights,0);
                    pos += posDx;
                }
            }
        }

        void setXY(int x, int y)
        {
            currX = x / Len;
            currY = y;
            l2 = get();
        }

        void incX()
        {
            ++currX;
            l1 = l2;
            l2 = get();
            foreach(i;0..Len)
            {
                buff[i] = (i + currY) % 2 ? l1 : l2;
            }
        }

        @property x() const { return (currX - 1) * Len; }

        private auto get() const
        {
            const ty = currY / Len;
            const row1 = lightData[ty];
            const row2 = lightData[ty + 1];
            return currY % 2 ? row1[currX] : row2[currX];
        }
    }

    alias SpanElemType = short;
    struct SpanRange
    {
        struct Span
        {
            SpanElemType x0 = void;
            SpanElemType x1 = void;
        }
        int y0 = void;
        int y1 = void;
        Span[] spans;
    }

    struct RelSpanRange
    {
        struct Span
        {
            SpanElemType x0 = void;
            SpanElemType x1 = void;
        }
        Span[] spns;
        int y0 = void;
        int x0 = void;
        int x1 = void;

        @property auto y1() const { return y0 + cast(int)spns.length; }

        auto ref spans(int index) inout
        {
            assert(index >= y0);
            assert(index < y1);
            return spns[index - y0];
        }
    }

    struct PreparedData(PosT,TextT,LineT)
    {
        bool valid = true;
        alias PackT   = LinesPack!(PosT,TextT,LineT);
        PackT pack;
        RelSpanRange spanrange;

        this(PackT pack_)
        {
            pack = pack_;
        }

        this(VT,ST)(in VT v1, in VT v2, in VT v3, in ST size, ref bool degenerate) pure nothrow
        {
            pack = PackT(v1,v2,v3,size, degenerate);
        }
    }

    static auto prepareTriangle(AllocT,CtxT1,CtxT2,VertT)
        (auto ref AllocT alloc, auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
    {
        assert(pverts.length == 3);
        alias PosT = Unqual!(typeof(VertT.pos.x));

        static if(HasTextures)
        {
            alias TextT = PosT;
        }
        else
        {
            alias TextT = void;
        }
        alias LineT   = Line!(PosT);
        alias PackT   = LinesPack!(PosT,TextT,LineT);
        alias PrepDataT = PreparedData!(PosT,TextT,LineT);

        const size = outContext.size;

        bool degenerate = void;
        PrepDataT ret = PrepDataT(pverts[0], pverts[1], pverts[2], size, degenerate);
        if(degenerate)
        {
            ret.valid = false;
            return ret;
        }

        return ret;
    }

    static void createTriangleSpans(AllocT,CtxT1,CtxT2,PrepT)
        (auto ref AllocT alloc, auto ref CtxT1 outContext, auto ref CtxT2 extContext, ref PrepT prepared)
    {
        alias PosT    = prepared.pack.pos_t;
        alias LineT   = Line!(PosT);
        alias PointT  = Point!(PosT);

        const clipRect = outContext.clipRect;
        const size = outContext.size;

        static if(ReadMask)
        {
            const srcMask = &outContext.mask;
            if(srcMask.isEmpty)
            {
                PrepDataT invalid;
                invalid.valid = false;
                return invalid;
            }
        }

        static if(ReadMask)
        {
            const minX = max(clipRect.x, srcMask.x0);
            const maxX = min(clipRect.x + clipRect.w, srcMask.x1);
            const minY = max(clipRect.y, srcMask.y0);
            const maxY = min(clipRect.y + clipRect.h, srcMask.y1);
        }
        else
        {
            const minX = clipRect.x;
            const maxX = clipRect.x + clipRect.w;
            const minY = clipRect.y;
            const maxY = clipRect.y + clipRect.h;
        }

        if(minX >= maxX || minY >= maxY)
        {
            prepared.valid = false;
            return;
        }

        void* ptr = null;
        int trueMinX = maxY;
        int trueMaxX = minX;
        int offset = 0;
        int hgt = 0;
        bool fullSpansRange = false;
        {
            auto allocState = alloc.state;
            scope(exit) alloc.restoreState(allocState);

            SpanRange spanrange;
            //spanrange.spans = alloc.alloc!(SpanRange.Span)(size.h);
            const LineT[3] lines = [
                LineT(prepared.pack.verts[0], prepared.pack.verts[1], prepared.pack.verts[2], size),
                LineT(prepared.pack.verts[1], prepared.pack.verts[2], prepared.pack.verts[0], size),
                LineT(prepared.pack.verts[2], prepared.pack.verts[0], prepared.pack.verts[1], size)];

            if(PointT(prepared.pack, minX, minY, lines).check() &&
               PointT(prepared.pack, maxX, minY, lines).check() &&
               PointT(prepared.pack, minX, maxY, lines).check() &&
               PointT(prepared.pack, maxX, maxY, lines).check())
            {
                fullSpansRange = true;
                spanrange.spans = alloc.alloc!(SpanRange.Span)(maxY);
                spanrange.y0 = minY;
                spanrange.y1 = maxY;
                foreach(y;minY..maxY)
                {
                    static if(ReadMask)
                    {
                        const xc0 = max(srcMask.spans[y].x0, minX);
                        const xc1 = min(srcMask.spans[y].x1, maxX);
                    }
                    else
                    {
                        const xc0 = minX;
                        const xc1 = maxX;
                    }
                    auto span = &spanrange.spans[y];
                    span.x0 = numericCast!SpanElemType(xc0);
                    span.x1 = numericCast!SpanElemType(xc1);
                    trueMinX = min(trueMinX, span.x0);
                    trueMaxX = max(trueMaxX, span.x1);
                }
            }
            else if(prepared.pack.external)
            {
                fullSpansRange = true;
                spanrange.spans = alloc.alloc!(SpanRange.Span)(maxY);
                //find first valid point
                bool findStart(int x0, int y0, int x1, int y1, ref PointT start)
                {
                    assert(x0 <= x1);
                    assert(x0 >= minX);
                    assert(x1 <= maxX);
                    assert(y0 <= y1);
                    assert(y0 >= minY);
                    assert(y1 <= maxY);
                    foreach(y;y0..y1)
                    {
                        static if(ReadMask)
                        {
                            const xs = max(x0, srcMask.spans[y].x0);
                            const xe = min(x1, srcMask.spans[y].x1);
                        }
                        else
                        {
                            const xs = x0;
                            const xe = x1;
                        }
                        auto pt = PointT(prepared.pack, xs, y, lines);
                        int count = 0;
                        foreach(x;xs..xe)
                        {
                            if(pt.check())
                            {
                                if(++count > 1)
                                {
                                    start = pt;
                                    return true;
                                }
                            }
                            pt.incX(1);
                        }
                    }
                    return false;
                }

                PointT startPoint = void;
                do
                {
                    foreach(const ref v; prepared.pack.verts[])
                    {
                        const w = v.z;
                        const x = cast(int)((v.x / w) * size.w) + size.w / 2;
                        const y = cast(int)((v.y / w) * size.h) + size.h / 2;

                        if(x >= minX && x < maxX &&
                           y >= minY && y < maxY &&
                           findStart(max(x - 2, minX), max(y - 2, minY), min(x + 3, maxX), min(y + 3, maxY), startPoint))
                        {
                            goto found;
                        }
                    }

                    bool checkQuad(in PointT pt00, in PointT pt10, in PointT pt01, in PointT pt11)
                    {
                        const x0 = pt00.currx;
                        const x1 = pt11.currx;
                        const y0 = pt00.curry;
                        const y1 = pt11.curry;
                        assert(x1 > x0);
                        assert(y1 > y0);
                        assert(x0 >= minX);
                        assert(x1 <= maxX);
                        assert(y0 >= minY);
                        assert(y1 <= maxY);
                        bool none(in uint val) pure nothrow
                        {
                            return 0x0 == (val & 0b001_001_001_001) ||
                                   0x0 == (val & 0b010_010_010_010) ||
                                   0x0 == (val & 0b100_100_100_100);
                        }
                        if(none((pt00.vals() << 0) |
                                (pt10.vals() << 3) |
                                (pt01.vals() << 6) |
                                (pt11.vals() << 9)))
                        {
                            return false;
                        }

                        if((x1 - x0) <= 8 ||
                           (y1 - y0) <= 8)
                        {
                            return findStart(x0, y0, x1, y1, startPoint);
                        }
                        const cx = x0 + (x1 - x0) / 2;
                        const cy = y0 + (y1 - y0) / 2;
                        //outContext.surface[cy][cx] = ColorRed;
                        auto ptc0 = PointT(prepared.pack, cx, y0, lines);
                        auto pt0c = PointT(prepared.pack, x0, cy, lines);
                        auto ptcc = PointT(prepared.pack, cx, cy, lines);
                        auto pt1c = PointT(prepared.pack, x1, cy, lines);
                        auto ptc1 = PointT(prepared.pack, cx, y1, lines);
                        return checkQuad(pt00, ptc0, pt0c, ptcc) ||
                               checkQuad(ptc0, pt10, ptcc, pt1c) ||
                               checkQuad(pt0c, ptcc, pt01, ptc1) ||
                               checkQuad(ptcc, pt1c, ptc1, pt11);
                    }
                    if(checkQuad(PointT(prepared.pack, minX, minY, lines),
                                 PointT(prepared.pack, maxX, minY, lines),
                                 PointT(prepared.pack, minX, maxY, lines),
                                 PointT(prepared.pack, maxX, maxY, lines)))
                    {
                        goto found;
                    }
                    //nothing found
                    prepared.valid = false;
                    return;
                }
                while(false);
            found:

                auto fillLine(in ref PointT pt)
                {
                    enum Step = 16;
                    static if(ReadMask)
                    {
                        const leftBound  = max(minX, srcMask.spans[pt.curry].x0);
                        const rightBound = min(maxX, srcMask.spans[pt.curry].x1);
                    }
                    else
                    {
                        const leftBound  = minX;
                        const rightBound = maxX;
                    }
                    if(leftBound < rightBound)
                    {
                        int findLeft()
                        {
                            PointT newPt = pt;
                            const count = (newPt.currx - leftBound) / Step;
                            foreach(i;0..count)
                            {
                                newPt.incX(-Step);
                                if(!newPt.check)
                                {
                                    foreach(j;0..Step)
                                    {
                                        newPt.incX(1);
                                        if(newPt.check()) break;
                                    }
                                    return newPt.currx;
                                }
                            }
                            while(newPt.currx >= leftBound && newPt.check())
                            {
                                newPt.incX(-1);
                            }
                            return newPt.currx + 1;
                        }
                        int findRight()
                        {
                            PointT newPt = pt;
                            const count = (rightBound - newPt.currx) / Step;
                            foreach(i;0..count)
                            {
                                newPt.incX(Step);
                                if(!newPt.check)
                                {
                                    foreach(j;0..Step)
                                    {
                                        newPt.incX(-1);
                                        if(newPt.check()) break;
                                    }
                                    return newPt.currx + 1;
                                }
                            }
                            while(newPt.currx < (rightBound - 0) && newPt.check())
                            {
                                newPt.incX(1);
                            }
                            return newPt.currx;
                        }
                        const x0 = findLeft();
                        const x1 = findRight();

                        auto span = &spanrange.spans[pt.curry];
                        span.x0 = numericCast!SpanElemType(max(x0, leftBound));
                        span.x1 = numericCast!SpanElemType(min(x1, rightBound));
                        trueMinX = min(trueMinX, span.x0);
                        trueMaxX = max(trueMaxX, span.x1);
                        return vec2i(x0, x1);
                    }
                    assert(false);
                }

                bool findPoint(T)(int y, in T bounds, out int x)
                {
                    //debugOut("find point");
                    static if(ReadMask)
                    {
                        const x0 = max(bounds.x - 4, minX, srcMask.spans[y].x0);
                        const x1 = min(bounds.y + 4, maxX, srcMask.spans[y].x1);
                    }
                    else
                    {
                        const x0 = max(bounds.x - 4, minX);
                        const x1 = min(bounds.y + 4, maxX);
                    }
                    auto none(in uint val) pure nothrow
                    {
                        return 0x0 == (val & 0b001_001) ||
                               0x0 == (val & 0b010_010) ||
                               0x0 == (val & 0b100_100);
                    }
                    const pt0 = PointT(prepared.pack, x0, y, lines);
                    const pt1 = PointT(prepared.pack, x1, y, lines);
                    if(none(pt0.vals() | (pt1.vals() << 3)))
                    {
                        return false;
                    }
                    enum Step = 16;
                    if((x1 - x0) >= Step)
                    {
                        foreach(i;0..Step)
                        {
                            auto pt = PointT(prepared.pack, x0 + i, y, lines);
                            while(pt.currx < x1)
                            {
                                if(pt.check())
                                {
                                    x = pt.currx;
                                    return true;
                                }
                                pt.incX(Step);
                            }
                        }
                    }
                    const e = x0 + ((x1 - x0) / Step) * Step;
                    auto pt = PointT(prepared.pack, e, y, lines);
                    while(pt.currx < x1)
                    {
                        //debugOut("check");
                        //debugOut(pt.currx);
                        if(pt.check())
                        {
                            x = pt.currx;
                            return true;
                        }
                        pt.incX(1);
                    }
                    bool findP(T)(in ref T p0, in ref T p1)
                    {
                        if(none(p0.vals() | (p1.vals() << 3)))
                        {
                            return false;
                        }
                        const d = p1.currx - p0.currx;
                        if(d <= 1)
                        {
                            x = p0.currx;
                            return true;
                        }
                        const cp = PointT(prepared.pack, p0.currx + d / 2, y, lines);
                        if(!findP(p0,cp))
                        {
                            findP(cp,p1);
                        }
                        return true;
                    }
                    findP(pt0, pt1);
                    return false;
                }
                int search(bool Down)(vec2i bounds, int y)
                {
                    //debugOut("search");
                    enum Inc = (Down ? 1 : -1);
                    y += Inc;
                    int x;
                    bool check()
                    {
                        static if(Down)
                        {
                            return bounds.y > bounds.x && y < maxY;
                        }
                        else
                        {
                            return bounds.y > bounds.x && y >= minY;
                        }
                    }
                    while(check() && findPoint(y, bounds, x))
                    {
                        const pt = PointT(prepared.pack, x, y, lines);
                        bounds = fillLine(pt);
                        //outContext.surface[y][x] = ColorBlue;
                        y += Inc;
                    }
                    return y;
                }
                const sy = startPoint.curry;
                const bounds = fillLine(startPoint);
                spanrange.y1 = search!true(bounds, sy);
                spanrange.y0 = search!false(bounds, sy) + 1;
            }
            else //external
            {
                alias Vec2 = Vector!(PosT,2);
                Vec2[3] sortedPos = void;
                PosT upperY = PosT.max;
                int minElem;
                foreach(int i,const ref v; prepared.pack.verts[])
                {
                    const pos = (v.xy / v.z);
                    sortedPos[i] = Vec2(cast(PosT)((pos.x * size.w) + size.w / 2),
                        cast(PosT)((pos.y * size.h) + size.h / 2));
                    if(sortedPos[i].y < upperY)
                    {
                        upperY = sortedPos[i].y;
                        minElem = i;
                    }
                }
                bringToFront(sortedPos[0..minElem], sortedPos[minElem..$]);
                //debugOut(sortedPos);
                struct Edge
                {
                    alias FP = float;//FixedPoint!(16,16,int);
                    FP dx;
                    FP currX;
                    FP y;
                    FP ye;
                    this(P)(in P p1, in P p2)
                    {
                        y  = p1.y;
                        ye = p2.y;
                        const FP x1 = p1.x;
                        const FP y1 = p1.y;
                        const FP x2 = p2.x;
                        const FP y2 = p2.y;
                        currX = x1;
                        //debugOut(y1," ",y2);
                        assert(y2 >= y1);
                        dx = (x2 - x1) / (y2 - y1);
                        incY(y.ceil - y);
                    }

                    void incY(PosT val)
                    {
                        y += val;
                        currX += dx * val;
                    }

                    @property auto x() const { return cast(int)(currX + 1.0f); }
                }

                Edge[3] edges = void;
                bool revX = void;
                if(sortedPos[1].y < sortedPos[2].y)
                {
                    revX = true;
                    edges[0] = Edge(sortedPos[0],sortedPos[2]);
                    edges[1] = Edge(sortedPos[0],sortedPos[1]);
                    edges[2] = Edge(sortedPos[1],sortedPos[2]);
                }
                else
                {
                    revX = false;
                    edges[0] = Edge(sortedPos[0],sortedPos[1]);
                    edges[1] = Edge(sortedPos[0],sortedPos[2]);
                    edges[2] = Edge(sortedPos[2],sortedPos[1]);
                }

                const y0 = max(cast(int)min(sortedPos[0].y, sortedPos[1].y, sortedPos[2].y), minY);
                const y1 = min(cast(int)max(sortedPos[0].y, sortedPos[1].y, sortedPos[2].y), maxY);
                assert(y0 >= 0);
                if(y0 <= y1)
                {
                    spanrange.spans = (alloc.alloc!(SpanRange.Span)(y1 - y0).ptr - y0)[0..y1 + 1]; //hack to reduce allocated memory
                }

                void fillSpans(bool ReverseX)()
                {
                    int y = cast(int)edges[0].y;
                    bool iterate(bool Fill)()
                    {
                        auto e0 = &edges[0];
                        foreach(i;TupleRange!(0,2))
                        {
                            static if(0 == i)
                            {
                                auto e1 = &edges[1];
                            }
                            else
                            {
                                auto e1 = &edges[2];
                            }
                            const ye = e1.ye;
                            while(y < ye)
                            {
                                if(y >= maxY)
                                {
                                    return false;
                                }
                                else if(y >= minY)
                                {
                                    //const x0 = min(e0.x, e1.x);
                                    //const x1 = max(e0.x, e1.x);
                                    static if(ReverseX)
                                    {
                                        const x0 = e1.x;
                                        const x1 = e0.x;
                                    }
                                    else
                                    {
                                        const x0 = e0.x;
                                        const x1 = e1.x;
                                    }
                                    /*if(x0 > x1)
                                    {
                                        debugOut(x0," ",x1);
                                        debugOut(*e0, " ",*e1);
                                    }*/
                                    //assert(x1 >= x0); TODO: investigate fails
                                    //outContext.surface[y][x0..x1] = ColorBlue;
                                    //debugOut(y);
                                    static if(ReadMask)
                                    {
                                        const xc0 = max(x0, srcMask.spans[y].x0, minX);
                                        const xc1 = min(x1, srcMask.spans[y].x1, maxX);
                                    }
                                    else
                                    {
                                        const xc0 = max(x0, minX);
                                        const xc1 = min(x1, maxX);
                                    }

                                    static if(!Fill)
                                    {
                                        if(xc1 > xc0)
                                        {
                                            return true;
                                        }
                                    }
                                    else
                                    {
                                        if(xc0 > xc1)
                                        {
                                            return false;
                                        }
                                        auto span = &spanrange.spans[y];
                                        span.x0 = numericCast!SpanElemType(xc0);
                                        span.x1 = numericCast!SpanElemType(xc1);
                                        trueMinX = min(trueMinX, span.x0);
                                        trueMaxX = max(trueMaxX, span.x1);
                                    }

                                    //outContext.surface[y][xc0..xc1] = ColorBlue;
                                }
                                ++y;
                                e0.incY(1);
                                e1.incY(1);
                            }
                        }
                        return false;
                    } //iterate
                    if(iterate!false())
                    {
                        spanrange.y0 = y;
                        iterate!true();
                        spanrange.y1 = y;
                    }
                } //fillspans

                if(revX)
                {
                    fillSpans!true();
                }
                else
                {
                    fillSpans!false();
                }
                offset = spanrange.y0 - y0;
            } //external

            if(spanrange.y0 >= spanrange.y1) 
            {
                prepared.valid = false;
                return;
            }

            prepared.spanrange.y0 = spanrange.y0;
            hgt = spanrange.y1 - spanrange.y0;
            if(fullSpansRange && 0 != spanrange.y0)
            {
                ptr = spanrange.spans.ptr;
                foreach(i,span;spanrange.spans[spanrange.y0..spanrange.y1]) 
                {
                    spanrange.spans[i] = span; //hack to reduce allocated memory
                }
            }
            else
            {
                ptr = spanrange.spans.ptr + spanrange.y0;
            }
        }
        prepared.spanrange.spns = alloc.alloc!(RelSpanRange.Span)(hgt).ptr[offset..offset + hgt]; //should be same data as in previous spanrange
        prepared.spanrange.x0 = trueMinX;
        prepared.spanrange.x1 = trueMaxX;
        assert(prepared.spanrange.spns.ptr == ptr);
    }

    static void drawPreparedTriangle(size_t TWidth, AllocT,CtxT1,CtxT2,PrepT)
        (auto ref AllocT alloc, in Rect clipRect, auto ref CtxT1 outContext, auto ref CtxT2 extContext, in auto ref PrepT prepared)
    {
        enum Full = (TWidth > 0);
        static assert(!Full || (TWidth >= AffineLength && 0 == (TWidth % AffineLength)));
        //alias FP = FixedPoint!(16,16,int);
        alias SpanT   = Span!(prepared.pack.pos_t);
        //alias SpanT   = Span!FP;
        static if(HasLight)
        {
            alias LightProxT = LightProxy!(AffineLength, PosT);
        }

        static if(HasTextures)
        {
            static if(HasLight)
            {
                auto lightProx = LightProxT(alloc,prepared.pack,prepared.spanrange,extContext);
            }

            void drawSpan(bool FixedLen,L)(
                int y,
                int x1, int x2,
                in ref SpanT span,
                auto ref L line)
            {
                assert((x2 - x1) <= AffineLength);
                if(x1 >= x2) return;
                static if(HasTextures)
                {
                    struct Transform
                    {
                    @nogc:
                        pure nothrow:
                        static if(HasLight)
                        {
                            ArrayView!int view;
                            auto opCall(T)(in T val,int x) const
                            {
                                //debugOut(view[x]);
                                return val + view[x] * (1 << LightPaletteBits);
                            }
                        }
                        else
                        {
                            static auto opCall(T)(in T val,int) { return val; }
                        }
                    }
                    alias TexT = Unqual!(typeof(span.u));
                    struct Context
                    {
                        Transform colorProxy;
                        int x;
                        TexT u;
                        TexT v;
                        TexT dux;
                        TexT dvx;
                    }
                    Context ctx = {x: x1, u: span.u, v: span.v, dux: span.dux, dvx: span.dvx};
                    static if(HasLight)
                    {
                        ctx.colorProxy.view.assign(lightProx.buff[],lightProx.x);
                    }

                    static if(FixedLen)
                    {
                        static if(Full)
                        {
                            assert(0 == (cast(size_t)line.ptr & (64 - 1)));
                            //assume(0 == (cast(size_t)line.ptr & (64 - 1)));
                        }
                        assert(x2 == (x1 + AffineLength));
                        extContext.texture.getLine!AffineLength(ctx,line[x1..x1 + AffineLength]);
                        //extContext.texture.getLine!AffineLength(ctx,ntsRange(line[x1..x2]));
                    }
                    else
                    {
                        enum SmallLine = 4;
                        foreach(sx;0..(x2 - x1) / SmallLine)
                        {
                            extContext.texture.getLine!SmallLine(ctx,line[ctx.x..ctx.x+SmallLine]);
                            //extContext.texture.getLine!SmallLine(ctx,ntsRange(line[ctx.x..ctx.x+SmallLine]));
                            ctx.u += ctx.dux * SmallLine;
                            ctx.v += ctx.dvx * SmallLine;
                            ctx.x += SmallLine;
                        }
                        foreach(x;ctx.x..x2)
                        {
                            extContext.texture.getLine!1(ctx,line[x..x+1]);
                            //extContext.texture.getLine!1(ctx,ntsRange(line[x..x+1]));
                            ctx.u += ctx.dux;
                            ctx.v += ctx.dvx;
                            ++ctx.x;
                        }
                    }
                }
            }

            static if(Full)
            {
                const sy = clipRect.y;
                const sx = clipRect.x;
                const ey = clipRect.y + clipRect.h;
                const x0 = sx;
                const x1 = x0 + TWidth;
            }
            else
            {
                const sy = max(clipRect.y, prepared.spanrange.y0);
                const sx = max(clipRect.x, prepared.spanrange.spans(sy).x0);
                const ey = min(clipRect.y + clipRect.h, prepared.spanrange.y1);
            }
            auto span = SpanT(prepared.pack, sx, sy);

            auto line = outContext.surface[sy];
            foreach(y;sy..ey)
            {
                static if(!Full)
                {
                    const yspan = prepared.spanrange.spans(y);
                    const x0 = max(clipRect.x, yspan.x0);
                    const x1 = min(clipRect.x + clipRect.w, yspan.x1);
                    const dx = x0 - sx;
                    assert(!Full || (0 == dx));
                    if(0 == dx)
                    {
                        span.initX();
                    }
                    else
                    {
                        span.incX(dx);
                    }
                }
                else
                {
                    span.initX();
                }

                static if(HasLight)
                {
                    lightProx.setXY(x0, y);
                }
                int x = x0;

                static if(!Full)
                {
                    const nx = (x + (AffineLength - 1)) & ~(AffineLength - 1);
                    if(nx > x && nx < x1)
                    {
                        static if(HasLight) lightProx.incX();
                        span.incX(nx - x - 1);
                        drawSpan!false(y, x, nx, span, line);
                        x = nx;
                    }
                    const affParts = ((x1-x) / AffineLength);
                }
                else
                {
                    //Full
                    enum affParts = TWidth / AffineLength;
                }

                foreach(i;0..affParts)
                {
                    span.incX(AffineLength);
                    static if(HasLight) lightProx.incX();
                    drawSpan!true(y, x, x + AffineLength, span, line);
                    x += AffineLength;
                }

                static if(!Full)
                {
                    const rem = (x1 - x);
                    if(rem > 0)
                    {
                        span.incX(rem);
                        static if(HasLight) lightProx.incX();
                        drawSpan!false(y, x, x1, span, line);
                    }
                }

                span.incY();
                ++line;
            }
        }

        static if(WriteMask)
        {
            static if(ReadMask)
            {
                const srcMask = &outContext.mask;
                const minX = max(outContext.clipRect.x, srcMask.x0);
                const maxX = min(outContext.clipRect.x + outContext.clipRect.w, srcMask.x1);
            }
            else
            {
                const minX = outContext.clipRect.x;
                const maxX = outContext.clipRect.x + outContext.clipRect.w;
            }
            auto  dstMask = &outContext.dstMask;
            void writeMask(bool Empty)()
            {
                //static immutable colors = [ColorRed,ColorGreen,ColorBlue];
                int mskMinX = maxX;
                int mskMaxX = minX;
                foreach(y;prepared.spanrange.y0..prepared.spanrange.y1)
                {
                    const x0 = prepared.spanrange.spans[y].x0;
                    const x1 = prepared.spanrange.spans[y].x1;
                    assert(x0 >= minX);
                    assert(x1 <= maxX);
                    assert(x1 >= x0);

                    if(Empty || y < dstMask.y0 || y >= dstMask.y1)
                    {
                        dstMask.spans[y].x0 = x0;
                        dstMask.spans[y].x1 = x1;
                    }
                    else
                    {
                        dstMask.spans[y].x0 = min(x0, dstMask.spans[y].x0);
                        dstMask.spans[y].x1 = max(x1, dstMask.spans[y].x1);
                    }
                    //outContext.surface[y][dstMask.spans[y].x0..dstMask.spans[y].x1] = ColorBlue;

                    mskMinX = min(mskMinX, x0);
                    mskMaxX = max(mskMaxX, x1);
                }
                static if(Empty)
                {
                    dstMask.y0 = prepared.spanrange.y0;
                    dstMask.y1 = prepared.spanrange.y1;
                    dstMask.x0 = mskMinX;
                    dstMask.x1 = mskMaxX;
                }
                else
                {
                    dstMask.x0 = min(mskMinX, dstMask.x0);
                    dstMask.x1 = max(mskMaxX, dstMask.x1);
                    dstMask.y0 = min(prepared.spanrange.y0, dstMask.y0);
                    dstMask.y1 = max(prepared.spanrange.y1, dstMask.y1);
                }
            }

            if(dstMask.isEmpty) writeMask!true();
            else                writeMask!false();
        }
        //end
    }

    struct CacheElem(PackT,ContextT)
    {
        PackT pack;
        ContextT extContext;
    }

    struct FlushParam(Alloc, Context)
    {
        Alloc alloc;
        Context* context;
    }

    static void flushData(PreparedT,FlushParam,CacheElem)(void[] data)
    {
        debugOut("flush");
        assert(data.length > FlushParam.sizeof);
        assert(0 == (data.length - FlushParam.sizeof) % CacheElem.sizeof);
        FlushParam* param = (cast(FlushParam*)data.ptr);
        const(CacheElem)[] cache = (cast(const(CacheElem)*)(data.ptr + FlushParam.sizeof))[0..(data.length - FlushParam.sizeof) / CacheElem.sizeof];

        auto allocState1 = param.alloc.state;
        scope(exit) param.alloc.restoreState(allocState1);

        const clipRect = param.context.clipRect;
        auto CalcTileSize(in Size tileSize)
        {
            assert(tileSize.w > 0);
            assert(tileSize.h > 0);
            return Size((clipRect.w + tileSize.w - 1) / tileSize.w, (clipRect.h + tileSize.h - 1) / tileSize.h);
        }
        Size[HighTileLevelCount + 1] tilesSizes = void;
        HighTile[][HighTileLevelCount] highTiles;
        tilesSizes[0] = CalcTileSize(TileSize);
        highTiles[0] = param.alloc.alloc(tilesSizes[0].w * tilesSizes[0].h, HighTile());
        foreach(i; TupleRange!(1,HighTileLevelCount + 1))
        {
            tilesSizes[i] = Size(tilesSizes[i - 1].w * 2, tilesSizes[i - 1].h * 2);
            static if(i < HighTileLevelCount)
            {
                highTiles[i] = param.alloc.alloc(tilesSizes[i].w * tilesSizes[i].h, HighTile());
            }
        }

        alias PackT = Unqual!(typeof(cache[0]));
        auto tiles = param.alloc.alloc(tilesSizes[HighTileLevelCount].w * tilesSizes[HighTileLevelCount].h,Tile());
        auto spans = param.alloc.alloc!RelSpanRange(cache.length);

        {
            auto allocState2 = param.alloc.state;
            scope(exit) param.alloc.restoreState(allocState2);
            //static assert(LowTileSize.w == LowTileSize.h);
            enum MaskW = LowTileSize.w;
            enum MaskH = LowTileSize.h;
            alias MaskT = TileMask!(MaskW, MaskH);
            auto masks = param.alloc.alloc!MaskT(tilesSizes[HighTileLevelCount].w * tilesSizes[HighTileLevelCount].h);

            foreach(i;iota(0,cache.length).retro)
            {
                auto prepared = PreparedT(cache[i].pack);
                createTriangleSpans(param.alloc, param.context, cache[i].extContext, prepared);

                if(!prepared.valid)
                {
                    continue;
                }
                updateTiles(param, highTiles, tiles, masks, tilesSizes, prepared.spanrange, cache[i].pack, cast(int)i);
                spans[i] = prepared.spanrange;

                //drawPreparedTriangle(param.alloc, param.context.clipRect, param.context, cache[i].extContext, prepared);
            }

        }

        drawTiles(param, highTiles, tiles, tilesSizes, cache, spans);
    }

    static void updateTiles(ParamsT,HTileT,TileT,MaskT,SpanT,PackT)
        (auto ref ParamsT params, HTileT[][] htiles, TileT[] tiles, MaskT[] masks, in Size[] tilesSizes, auto ref SpanT spanrange, in auto ref PackT pack, int index)
    {
        assert(index >= 0);

        alias PosT    = pack.pos_t;
        alias LineT   = Line!(PosT);
        alias PointT  = Point!(PosT);

        const LineT[3] lines = [
            LineT(pack.verts[0], pack.verts[1], pack.verts[2], params.context.size),
            LineT(pack.verts[1], pack.verts[2], pack.verts[0], params.context.size),
            LineT(pack.verts[2], pack.verts[0], pack.verts[1], params.context.size)];

        const clipRect = params.context.clipRect;
        bool none(in uint val) pure nothrow const
        {
            return 0x0 == (val & 0b00000001_00000001_00000001_00000001) ||
                   0x0 == (val & 0b00000010_00000010_00000010_00000010) ||
                   0x0 == (val & 0b00000100_00000100_00000100_00000100);
        }
        auto all(in uint val) pure nothrow const
        {
            return val == 0b00000111_00000111_00000111_00000111;
        }

        void updateLine(int y)
        {
            const ty0 = y * TileSize.h;
            const ty1 = min(ty0 + TileSize.h, clipRect.y + clipRect.h);
            assert(ty1 > ty0);
            const sy0 = max(spanrange.y0, ty0);
            const sy1 = min(spanrange.y1, ty1);
            assert(sy1 > sy0);

            const sx = (spanrange.x0 / TileSize.w) * TileSize.w;
            auto pt1 = PointT(pack, cast(int)sx, cast(int)ty0, lines);
            auto pt2 = PointT(pack, cast(int)sx, cast(int)ty1, lines);
            uint val = (pt1.vals() << 0) | (pt2.vals() << 8);

            bool hadOne = false;
            foreach(x; (spanrange.x0 / TileSize.w)..((spanrange.x1 + TileSize.w - 1) / TileSize.w))
            {
                pt1.incX(TileSize.w);
                pt2.incX(TileSize.w);
                val = val | (pt1.vals() << 16) | (pt2.vals() << 24);
                union U
                {
                    uint oldval;
                    ubyte[4] vals;
                }
                static assert(U.sizeof == uint.sizeof);
                const U u = {oldval: val};
                assert((u.oldval & 0xff) == u.vals[0]);
                val >>= 16;

                auto tile = &htiles[0][x + y * tilesSizes[0].w];

                if(tile.used)
                {
                    continue;
                }

                if(none(u.oldval))
                {
                    if(hadOne)
                    {
                        break;
                    }
                    else
                    {
                        continue;
                    }
                }
                hadOne = true;

                if(!tile.hasChildren && all(u.oldval))
                {
                    tile.set(index);
                }
                else
                {
                    void checkTile(Size TSize, int Level)(int tx, int ty, in ubyte[4] prevVals)
                    {
                        static assert(TSize.w > 0 && TSize.h > 0);
                        static assert(Level >= 0);
                        assert(4 == prevVals.length);
                        const x = tx * TSize.w;
                        const y = ty * TSize.h;
                        enum gamelib.types.Point[4] tpoints = [
                             gamelib.types.Point(0, 0),
                             gamelib.types.Point(1, 0),
                             gamelib.types.Point(0, 1),
                             gamelib.types.Point(1, 1)];

                        const pt1 = cast(uint)prevVals[0];//*/PointT(pack, cast(int)x              , cast(int)y              , lines).vals();
                        const pt2 = PointT(pack, cast(int)x + TSize.w    , cast(int)y              , lines).vals();
                        const pt3 = cast(uint)prevVals[2];//*/PointT(pack, cast(int)x + TSize.w * 2, cast(int)y              , lines).vals();
                        const pt4 = PointT(pack, cast(int)x              , cast(int)y + TSize.h    , lines).vals();
                        const pt5 = PointT(pack, cast(int)x + TSize.w    , cast(int)y + TSize.h    , lines).vals();
                        const pt6 = PointT(pack, cast(int)x + TSize.w * 2, cast(int)y + TSize.h    , lines).vals();
                        const pt7 = cast(uint)prevVals[1];//*/PointT(pack, cast(int)x              , cast(int)y + TSize.h * 2, lines).vals();
                        const pt8 = PointT(pack, cast(int)x + TSize.w    , cast(int)y + TSize.h * 2, lines).vals();
                        const pt9 = cast(uint)prevVals[3];//*/PointT(pack, cast(int)x + TSize.w * 2, cast(int)y + TSize.h * 2, lines).vals();
                        const uint[4] vals = [
                            (pt1 << 0) | (pt4 << 8) | (pt2 << 16) | (pt5 << 24),
                            (pt2 << 0) | (pt5 << 8) | (pt3 << 16) | (pt6 << 24),
                            (pt4 << 0) | (pt7 << 8) | (pt5 << 16) | (pt8 << 24),
                            (pt5 << 0) | (pt8 << 8) | (pt6 << 16) | (pt9 << 24)];

                        static if(Level < HighTileLevelCount)
                        {
                            foreach(i;0..4)
                            {
                                const currPt = gamelib.types.Point(tx + tpoints[i].x, ty + tpoints[i].y);
                                auto tile = &htiles[Level][currPt.x + currPt.y * tilesSizes[Level].w];
                                if(tile.used)
                                {
                                    continue;
                                }

                                if(!tile.hasChildren && all(vals[i]))
                                {
                                    tile.set(index);
                                }
                                else if(!none(vals[i]))
                                {
                                    const U temp = {oldval: vals[i] };
                                    checkTile!(Size(TSize.w >> 1, TSize.h >> 1), Level + 1)(currPt.x * 2, currPt.y * 2, temp.vals);
                                    tile.setChildren();
                                }
                            }
                        }
                        else static if(Level == HighTileLevelCount)
                        {
                            foreach(i;0..4)
                            {
                                const currPt = gamelib.types.Point(tx + tpoints[i].x, ty + tpoints[i].y);
                                auto tile = &tiles[currPt.x + currPt.y * tilesSizes[Level].w];
                                if(tile.full)
                                {
                                    continue;
                                }

                                const int x0 = currPt.x * TSize.w;
                                const int x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                                //assert(x1 > x0);

                                const int y0 = currPt.y * TSize.h;
                                const int y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                                //assert(y1 > y0);

                                if(spanrange.x1 <= x0 || spanrange.x0 >= x1 ||
                                   spanrange.y1 <= y0 || spanrange.y0 >= y1)
                                {
                                    continue;
                                }

                                if(none(vals[i]))
                                {
                                    continue;
                                }

                                if(all(vals[i]))
                                {
                                    tile.addTriangle(index, true);
                                }
                                else
                                {
                                    const sy0 = max(spanrange.y0, y0);
                                    const sy1 = min(spanrange.y1, y1);

                                    auto mask = &masks[currPt.x + currPt.y * tilesSizes[Level].w];
                                    if(tile.empty)
                                    {
                                        foreach(myr;0..TSize.h)
                                        {
                                            mask.type_t newMaskVal = 0;
                                            const my = y0 + myr;
                                            if(my >= sy0 && my < sy1)
                                            {
                                                const sx0 = max(spanrange.spans(my).x0, x0);
                                                const sx1 = min(spanrange.spans(my).x1, x1);
                                                if(sx1 > sx0)
                                                {
                                                    enum FullMask = mask.FullMask;
                                                    const sh0 = (sx0 - x0);
                                                    const sh1 = (x0 + TSize.w - sx1);
                                                    const val = (FullMask >> sh0) & (FullMask << sh1);
                                                    assert(0 != val);
                                                    newMaskVal = val;
                                                }
                                            }
                                            mask.data[myr] = newMaskVal;
                                        }

                                        tile.addTriangle(index, mask.full);
                                    }
                                    else
                                    {
                                        assert(!mask.full);

                                        bool visible = false;
                                        foreach(my; sy0..sy1)
                                        {
                                            const sx0 = max(spanrange.spans(my).x0, x0);
                                            const sx1 = min(spanrange.spans(my).x1, x1);
                                            if(sx1 > sx0)
                                            {
                                                const myr = my - y0;
                                                enum FullMask = mask.FullMask;
                                                const sh0 = (sx0 - x0);
                                                const sh1 = (x0 + TSize.w - sx1);
                                                const val = (FullMask >> sh0) & (FullMask << sh1);
                                                assert(0 != val);
                                                if(0 != (val & ~mask.data[myr]))
                                                {
                                                    mask.data[myr] |= val;
                                                    visible = true;
                                                }
                                            }
                                        }

                                        if(visible)
                                        {
                                            tile.addTriangle(index, mask.full);
                                        }
                                    }
                                }
                            }
                        }
                        else static assert(false);
                    }

                    checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1)(x * 2, y * 2, u.vals);
                    tile.setChildren();
                }
            }
        }

        auto yrange = iota((spanrange.y0 / TileSize.h), ((spanrange.y1 + TileSize.h - 1) / TileSize.h));

        /*if(params.context.myTaskPool !is null && yrange.length > 1)
        {
            foreach(y; params.context.myTaskPool.parallel(yrange, 1))
            {
                updateLine(y);
            }
        }
        else*/
        {
            foreach(y; yrange)
            {
                updateLine(y);
            }
        }
    }

    static void drawTiles(ParamsT,HTileT,TileT,CacheT,SpansT)
        (auto ref ParamsT params, HTileT[][] htiles, TileT[] tiles, in Size[] tilesSizes, CacheT[] cache, SpansT[] spans)
    {
        struct TilePrepared
        {
            Unqual!(typeof(cache[0].pack)) pack;
            RelSpanRange spanrange;
        }
        void drawTile(Size TSize, int Level)(int tx, int ty)
        {
            static assert(TSize.w > 0 && TSize.h > 0);
            static assert(Level >= 0);
            enum FullDrawWidth = TSize.w;

            static if(Level < HighTileLevelCount)
            {
                auto tile = &htiles[Level][tx + ty * tilesSizes[Level].w];

                if(tile.hasChildren)
                {
                    const gamelib.types.Point[4] tpoints = [
                          gamelib.types.Point(tx * 2    ,ty * 2),
                          gamelib.types.Point(tx * 2 + 1,ty * 2),
                          gamelib.types.Point(tx * 2    ,ty * 2 + 1),
                          gamelib.types.Point(tx * 2 + 1,ty * 2 + 1)];
                    foreach(i;0..4)
                    {
                        drawTile!(Size(TSize.w >> 1, TSize.h >> 1), Level + 1)(tpoints[i].x,tpoints[i].y);
                    }
                }
                else if(tile.used)
                {
                    const x0 = tx * TSize.w;
                    const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                    assert(x1 > x0);
                    const y0 = ty * TSize.h;
                    const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                    assert(y1 > y0);
                    const rect = Rect(x0, y0, x1 - x0, y1 - y0);

                    const index = tile.index;
                    if(rect.w == TSize.w)
                    {
                        drawPreparedTriangle!FullDrawWidth(params.alloc, rect, params.context, cache[index].extContext, TilePrepared(cache[index].pack, spans[index]));
                    }
                    else
                    {
                        drawPreparedTriangle!0(params.alloc, rect, params.context, cache[index].extContext, TilePrepared(cache[index].pack, spans[index]));
                    }
                }
            }
            else static if(Level == HighTileLevelCount)
            {
                auto tile = &tiles[tx + ty * tilesSizes[Level].w];
                if(tile.empty)
                {
                    return;
                }
                const x0 = tx * TSize.w;
                const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                assert(x1 > x0);
                const y0 = ty * TSize.h;
                const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                assert(y1 > y0);
                const rect = Rect(x0, y0, x1 - x0, y1 - y0);

                auto buff = tile.buffer[0..tile.length];
                assert(buff.length > 0);

                if(tile.covered && (rect.w == TSize.w))
                {
                    const index = buff.back;
                    assert(index >= 0);
                    assert(index < cache.length);
                    drawPreparedTriangle!FullDrawWidth(params.alloc, rect, params.context, cache[index].extContext, TilePrepared(cache[index].pack, spans[index]));
                    buff.popBack;
                }

                foreach(const index; buff.retro)
                {
                    assert(index >= 0);
                    assert(index < cache.length);
                    drawPreparedTriangle!0(params.alloc, rect, params.context, cache[index].extContext, TilePrepared(cache[index].pack, spans[index]));
                }
            }
            else static assert(false);
        }
        const clipRect = params.context.clipRect;

        auto xyrange = cartesianProduct(iota(0, tilesSizes[0].h), iota(0, tilesSizes[0].w));

        if(params.context.myTaskPool !is null)
        {
            foreach(pos; params.context.myTaskPool.parallel(xyrange, 8))
            {
                const y = pos[0];
                const x = pos[1];
                drawTile!(TileSize,0)(x,y);
            }
        }
        else
        {
            foreach(pos; xyrange)
            {
                const y = pos[0];
                const x = pos[1];
                drawTile!(TileSize,0)(x,y);
            }
        }
    }

    static void drawTriangle(AllocT,CtxT1,CtxT2,VertT)
        (auto ref AllocT alloc, auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
    {
        assert(pverts.length == 3);
        alias PosT = Unqual!(typeof(VertT.pos.x));

        auto prepared = prepareTriangle(alloc, outContext, extContext, pverts);
        alias PreparedT = Unqual!(typeof(prepared));

        if(!prepared.valid)
        {
            return;
        }

        if(UseCache)
        //if(false)
        {
            alias CacheElemT = CacheElem!(Unqual!(typeof(prepared.pack)), Unqual!CtxT2);
            enum CacheElemSize = CacheElemT.sizeof;
            alias FlushParamT = FlushParam!(Unqual!AllocT,Unqual!CtxT1);
            assert(outContext.rasterizerCache.length > (CacheElemSize + FlushParamT.sizeof));

            auto ownFunc = &flushData!(PreparedT,FlushParamT,CacheElemT);
            if((outContext.rasterizerCache.length - outContext.rasterizerCacheUsed) < CacheElemSize ||
                    outContext.flushFunc != ownFunc)
            {
                if(outContext.flushFunc !is null)
                {
                    outContext.flushFunc(outContext.rasterizerCache[0..outContext.rasterizerCacheUsed]);
                }
                outContext.rasterizerCacheUsed = FlushParamT.sizeof;
                *(cast(FlushParamT*)outContext.rasterizerCache.ptr) = FlushParamT(alloc,&outContext);
                outContext.flushFunc = ownFunc;
            }

            auto newElem = CacheElemT(prepared.pack, extContext);
            (outContext.rasterizerCache.ptr + outContext.rasterizerCacheUsed)[0..CacheElemT.sizeof] = (cast(void*)&newElem)[0..CacheElemT.sizeof];
            outContext.rasterizerCacheUsed += CacheElemSize;
        }
        else
        {
            auto allocState1 = alloc.state;
            scope(exit) alloc.restoreState(allocState1);
            createTriangleSpans(alloc, outContext, extContext, prepared);

            if(!prepared.valid)
            {
                return;
            }

            drawPreparedTriangle!0(alloc, outContext.clipRect, outContext, extContext, prepared);
        }
    }

}
