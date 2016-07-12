﻿module game.renderer.rasterizertiled2;

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

struct RasterizerTiled2(bool HasTextures, bool WriteMask, bool ReadMask, bool HasLight)
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
        drawTriangle(outputContext, extContext, pverts);
    }

private:
    enum TiledRendering = true;
    enum FillBackground = true;
    enum UseDithering = false;

    enum AffineLength = 32;
    enum TileSize = Size(64,64);
    enum HighTileLevelCount = 1;
    enum TileBufferSize = 64;
    enum LowTileSize = Size(TileSize.w >> HighTileLevelCount, TileSize.h >> HighTileLevelCount);
    struct Tile
    {
        static assert(TileBufferSize > 1);
        alias type_t = ushort;
        type_t used = 0;
        type_t[TileBufferSize - 1] buffer = void;
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

        auto val(T)(in T x, in T y) const
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
            dx = vec.x / (size.w);
            dy = vec.y / (size.h);
            c = vec.z - dx * ((size.w) / cast(PosT)2) - dy * ((size.h) / cast(PosT)2);
        }

        auto get(T)(in T x, in T y) const
        {
            return c + dx * x + dy * y;
        }
    }

    struct VertsPack(PosT,TextT)
    {
        pure nothrow @nogc:
        alias pos_t = PosT;
        alias vec2 = Vector!(PosT,2);
        alias vec3 = Vector!(PosT,3);
        alias pack_t = LinesPack!(PosT,TextT);

        vec3[3] verts = void;
        vec2[3] tcoords = void;

        this(VT)(in VT v1, in VT v2, in VT v3, in Size size, ref bool valid)
        {
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
            enum tol = 0.001f;
            if(d < tol || (w1 > tol && w2 > tol && w3 > tol))
            {
                valid = false;
                return;
            }
            valid = true;
            verts = [v1.pos.xyw,v2.pos.xyw,v3.pos.xyw];
            tcoords = [v1.tpos,v2.tpos,v3.tpos];
        }

        auto external(in Size size) const
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
            const dw = 0.001f;
            const sizeLim = 100000;
            const bool big = max(
                max(abs(x1 / w1), abs(x2 / w2), abs(x3 / w3)) * size.w,
                max(abs(y1 / w1), abs(y2 / w2), abs(y3 / w3)) * size.h) > sizeLim;
            return big || almost_equal(w1, 0, dw) || almost_equal(w2, 0, dw) || almost_equal(w3, 0, dw) || (w1 * w2 < dw) || (w1 * w3 < dw);
        }
    }

    struct LinesPack(PosT,TextT)
    {
        pure nothrow @nogc:
        alias pos_t = PosT;
        enum HasTexture = !is(TextT : void);
        alias vec2 = Vector!(PosT,2);
        alias vec3 = Vector!(PosT,3);
        alias PlaneT = Plane!(PosT);

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
        vec3[3] verts = void;
        PosT wDiff = void;

        this(VT)(in auto ref VT v, in Size size)
        {
            verts = v.verts;

            const w1 = verts[0].z;
            const w2 = verts[1].z;
            const w3 = verts[2].z;
            const x1 = verts[0].x;
            const x2 = verts[1].x;
            const x3 = verts[2].x;
            const y1 = verts[0].y;
            const y2 = verts[1].y;
            const y3 = verts[2].y;
            const mat = Matrix!(PosT,3,3)(
                x1, y1, w1,
                x2, y2, w2,
                x3, y3, w3);

            const invMat = mat.inverse;
            wplane = PlaneT(invMat * vec3(1,1,1), size);
            static if(HasTexture)
            {
                const tu1 = v.tcoords[0].u;
                const tu2 = v.tcoords[1].u;
                const tu3 = v.tcoords[2].u;
                const tv1 = v.tcoords[0].v;
                const tv2 = v.tcoords[1].v;
                const tv3 = v.tcoords[2].v;
                uplane = PlaneTtex(invMat * vec3tex(tu1,tu2,tu3), size);
                vplane = PlaneTtex(invMat * vec3tex(tv1,tv2,tv3), size);
            }
            static if(HasLight)
            {
                const refPos1 = verts[0].refPos;
                const refPos2 = verts[1].refPos;
                const refPos3 = verts[2].refPos;
                refXplane = PlaneT(invMat * vec3(refPos1.x,refPos2.x,refPos3.x), size);
                refYplane = PlaneT(invMat * vec3(refPos1.y,refPos2.y,refPos3.y), size);
                refZplane = PlaneT(invMat * vec3(refPos1.z,refPos2.z,refPos3.z), size);
                normal = cross(refPos2 - refPos1, refPos3 - refPos1).normalized;
            }

            const minW = min(w1,w2,w3);
            const maxW = max(w1,w2,w3);
            wDiff = (maxW - minW);
            assert(wDiff >= 0);
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
        this(LineT)(int x, int y, in ref LineT lines)
        {
            foreach(i;0..NumLines)
            {
                const val = lines[i].val(x, y + 1);
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

    static auto pointPlanesVals(LineT)(int x, int y, in ref LineT lines)
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

        @property auto empty() const
        {
            return 0 == spns.length;
        }
    }

    struct PreparedData(PosT,TextT)
    {
        alias PackT = VertsPack!(PosT,TextT);
        PackT pack = void;
        bool valid = void;
        RelSpanRange spanrange;

        this(PackT pack_)
        {
            pack = pack_;
            valid = true;
        }

        this(VT,ST)(in VT v1, in VT v2, in VT v3, in ST size) pure nothrow
        {
            pack = PackT(v1,v2,v3,size,valid);
        }
    }

    static auto prepareTriangle(CtxT1,CtxT2,VertT)
        (auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
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
        alias PrepDataT = PreparedData!(PosT,TextT);

        const size = outContext.size;
        PrepDataT ret = PrepDataT(pverts[0], pverts[1], pverts[2], size);

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
                prepared.valid = false;
                return;
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
        int realHgt = 0;
        int hgt = 0;
        {
            bool fullSpansRange = false;
            auto allocState = alloc.state;
            scope(exit) alloc.restoreState(allocState);
            SpanRange spanrange;

            const LineT[3] lines = [
                LineT(prepared.pack.verts[0], prepared.pack.verts[1], prepared.pack.verts[2], size),
                LineT(prepared.pack.verts[1], prepared.pack.verts[2], prepared.pack.verts[0], size),
                LineT(prepared.pack.verts[2], prepared.pack.verts[0], prepared.pack.verts[1], size)];

            if(PointT(minX, minY, lines).check() &&
               PointT(maxX, minY, lines).check() &&
               PointT(minX, maxY, lines).check() &&
               PointT(maxX, maxY, lines).check())
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
                hgt = (maxY - minY);
                realHgt = hgt;
            }
            else if(prepared.pack.external(size))
            {
                fullSpansRange = true;
                assert(maxY > 0);
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
                        auto pt = PointT(xs, y, lines);
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

                        const ptc0 = PointT(cx, y0, lines);
                        const pt0c = PointT(x0, cy, lines);
                        const ptcc = PointT(cx, cy, lines);
                        const pt1c = PointT(x1, cy, lines);
                        const ptc1 = PointT(cx, y1, lines);
                        return checkQuad(pt00, ptc0, pt0c, ptcc) ||
                               checkQuad(ptc0, pt10, ptcc, pt1c) ||
                               checkQuad(pt0c, ptcc, pt01, ptc1) ||
                               checkQuad(ptcc, pt1c, ptc1, pt11);
                    }
                    if(checkQuad(PointT(minX, minY, lines),
                                 PointT(maxX, minY, lines),
                                 PointT(minX, maxY, lines),
                                 PointT(maxX, maxY, lines)))
                    {
                        goto found;
                    }
                    //nothing found
                    prepared.valid = false;
                    return;
                }
                while(false);
            found:

                auto spans = spanrange.spans.ptr;
                auto fillLine(in ref PointT pt)
                {
                    enum Step = 16;
                    const currY = pt.curry;
                    static if(ReadMask)
                    {
                        const leftBound  = max(minX, srcMask.spans[currY].x0);
                        const rightBound = min(maxX, srcMask.spans[currY].x1);
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
                            while(newPt.currx < (rightBound) && newPt.check())
                            {
                                newPt.incX(1);
                            }
                            return newPt.currx;
                        }
                        const x0 = findLeft() - 1;
                        const x1 = findRight() + 1;

                        assert(currY >= 0);
                        assert(currY < spanrange.spans.length);
                        auto span = &spans[currY];
                        const sx0 = max(x0, leftBound);
                        const sx1 = min(x1, rightBound);
                        span.x0 = numericCast!SpanElemType(sx0);
                        span.x1 = numericCast!SpanElemType(sx1);
                        trueMinX = min(trueMinX, sx0);
                        trueMaxX = max(trueMaxX, sx1);
                        return vec2i(x0, x1);
                    }
                    assert(false);
                }

                bool findPoint(T)(int y, in T bounds, out int x)
                {
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
                    const pt0 = PointT(x0, y, lines);
                    const pt1 = PointT(x1, y, lines);
                    if(none(pt0.vals() | (pt1.vals() << 3)))
                    {
                        return false;
                    }
                    enum Step = 16;
                    if((x1 - x0) >= Step)
                    {
                        foreach(i;0..Step)
                        {
                            auto pt = PointT(x0 + i, y, lines);
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
                    auto pt = PointT(e, y, lines);
                    while(pt.currx < x1)
                    {
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
                        const cp = PointT(p0.currx + d / 2, y, lines);
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
                        const pt = PointT(x, y, lines);
                        bounds = fillLine(pt);
                        //outContext.surface[y][x] = ColorBlue;
                        y += Inc;
                    }
                    return y;
                }
                const sy = startPoint.curry;
                const bounds = fillLine(startPoint);
                const y1 = search!true(bounds, sy);
                const y0 = search!false(bounds, sy) + 1;
                hgt = (y1 - y0);
                realHgt = hgt;
                spanrange.y1 = y1;
                spanrange.y0 = y0;
            }
            else //external
            {
                alias Vec2 = Vector!(PosT,2);
                Vec2[3] sortedPos = void;
                PosT upperY = PosT.max;
                int minElem;
                foreach(int i,const ref v; prepared.pack.verts[])
                {
                    //assert(v.z < -0.01f);
                    const pos = (v.xy / v.z);
                    sortedPos[i] = Vec2(
                        cast(PosT)((pos.x * size.w) + size.w / 2),
                        cast(PosT)((pos.y * size.h) + size.h / 2));
                    if(sortedPos[i].y < upperY)
                    {
                        upperY = sortedPos[i].y;
                        minElem = i;
                    }
                }
                bringToFront(sortedPos[0..minElem], sortedPos[minElem..$]);
                struct Edge
                {
                    alias FP = float;//FixedPoint!(16,16,int);
                    FP dx;
                    FP currX;
                    FP y;
                    FP ye;
                    this(P)(in P p1, in P p2, in FP xcorrect)
                    {
                        y  = p1.y;
                        ye = p2.y;
                        const FP x1 = p1.x;
                        const FP y1 = p1.y;
                        const FP x2 = p2.x;
                        const FP y2 = p2.y;
                        currX = x1 + xcorrect;

                        assert(y2 >= y1);
                        dx = (x2 - x1) / (y2 - y1);
                        incY(y.ceil - y);
                    }

                    void incY(PosT val)
                    {
                        y += val;
                        currX += dx * val;
                    }

                    void incY()
                    {
                        ++y;
                        currX += dx;
                    }

                    @property auto x() const { return cast(int)(currX); }
                }

                bool revX = void;
                auto xcorr1 = 0.0f;
                auto xcorr2 = 0.0f;
                if(sortedPos[1].y < sortedPos[2].y)
                {
                    revX = true;
                    swap(sortedPos[1],sortedPos[2]);
                    xcorr1 = 2.5f;
                }
                else
                {
                    revX = false;
                    xcorr2 = 2.5f;
                }

                Edge[3] edges = [
                    Edge(sortedPos[0],sortedPos[1],xcorr1),
                    Edge(sortedPos[0],sortedPos[2],xcorr2),
                    Edge(sortedPos[2],sortedPos[1],xcorr2)];

                const y0 = max(sortedPos[0].y.numericCast!int, minY);
                const y1 = min(sortedPos[1].y.numericCast!int, maxY);
                assert(y0 >= 0);
                if(y0 <= y1)
                {
                    spanrange.spans = (alloc.alloc!(SpanRange.Span)(y1 - y0).ptr - y0)[0..y1 + 1]; //hack to reduce allocated memory
                }
                else
                {
                    spanrange.spans = spanrange.spans.init;
                }
                auto spans = spanrange.spans.ptr;

                void fillSpans(bool ReverseX)() nothrow
                {
                    int y = sortedPos[0].y.numericCast!int;
                    bool iterate(bool Fill)()
                    {
                        int currY = y;
                        auto e0 = edges[0];
                        foreach(i;0..2)
                        {
                            auto e1 = edges[1 + i];
                            const ye = min(e1.ye.numericCast!int, maxY);
                            if(currY < minY)
                            {
                                if(ye < minY)
                                {
                                    const dy = ye - currY;
                                    e0.incY(dy);
                                    currY = ye;
                                    continue;
                                }
                                else
                                {
                                    const dy = minY - currY;
                                    e0.incY(dy);
                                    e1.incY(dy);
                                    currY = minY;
                                }
                            }

                            while(currY < ye)
                            {
                                assert(currY >= minY);
                                assert(currY <  maxY);

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

                                static if(ReadMask)
                                {
                                    const xc0 = max(x0, srcMask.spans[currY].x0, minX);
                                    const xc1 = min(x1, srcMask.spans[currY].x1, maxX);
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
                                        edges[0] = e0;
                                        edges[1 + i] = e1;
                                        y = currY;
                                        return true;
                                    }
                                }
                                else
                                {
                                    if(xc0 > xc1)
                                    {
                                        y = currY;
                                        return false;
                                    }
                                    assert(currY >= y0);
                                    assert(currY < y1);
                                    assert(currY >= 0);
                                    assert(currY < spanrange.spans.length);
                                    auto span = &spans[currY];
                                    assert(xc0 >= SpanElemType.min && xc0 <= SpanElemType.max);
                                    assert(xc1 >= SpanElemType.min && xc1 <= SpanElemType.max);
                                    span.x0 = numericCast!SpanElemType(xc0);
                                    span.x1 = numericCast!SpanElemType(xc1);
                                    trueMinX = min(trueMinX, xc0);
                                    trueMaxX = max(trueMaxX, xc1);
                                }

                                ++currY;
                                e0.incY();
                                e1.incY();
                            }
                        }
                        y = currY;
                        return false;
                    } //iterate

                    if(iterate!false())
                    {
                        spanrange.y0 = y;
                        iterate!true();
                        spanrange.y1 = y;

                        assert(spanrange.y0 >= y0);
                        assert(spanrange.y1 <= y1);
                        assert(spanrange.y1 > spanrange.y0);
                        assert((spanrange.y1 - spanrange.y0) <= (y1 - y0));
                    }
                } //fillspans

                if(y1 > y0)
                {
                    if(revX)
                    {
                        fillSpans!true();
                    }
                    else
                    {
                        fillSpans!false();
                    }
                    realHgt = y1 - y0;
                    offset = spanrange.y0 - y0;
                    hgt = spanrange.y1 - spanrange.y0;
                }
                else
                {
                    spanrange.y0 = 0;
                    spanrange.y1 = 0;
                }
            } //external

            if(spanrange.y0 >= spanrange.y1)
            {
                prepared.valid = false;
                return;
            }

            prepared.spanrange.y0 = spanrange.y0;
            if(fullSpansRange && spanrange.y0 > 0)
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
        assert(prepared.valid);
        assert(realHgt > 0);
        assert(hgt > 0);
        prepared.spanrange.spns = alloc.alloc!(RelSpanRange.Span)(realHgt).ptr[offset..offset + hgt]; //should be same data as in previous spanrange
        prepared.spanrange.x0 = trueMinX;
        prepared.spanrange.x1 = trueMaxX;
        assert(prepared.spanrange.spns.ptr == ptr);
    }

    static void fillBackground(CtxT1)
        (in Rect clipRect, auto ref CtxT1 outContext)
    {
        const color = outContext.backColor;
        const y0 = clipRect.y;
        const y1 = clipRect.y + clipRect.h;
        const x0 = clipRect.x;
        const x1 = clipRect.x + clipRect.w;
        auto line = outContext.surface[y0];
        foreach(y;y0..y1)
        {
            line[x0..x1] = color;
            ++line;
        }
    }

    static void drawPreparedTriangle(size_t TWidth, bool FillBack, AllocT,CtxT1,CtxT2,PrepT)
        (auto ref AllocT alloc, in Rect clipRect, auto ref CtxT1 outContext, auto ref CtxT2 extContext, in auto ref PrepT prepared)
    {
        enum Full = (TWidth > 0);
        static assert(!(Full && FillBack));
        static assert(!Full || (TWidth >= AffineLength && 0 == (TWidth % AffineLength)));

        const size = outContext.size;

        static if(HasLight)
        {
            alias LightProxT = LightProxy!(AffineLength, PosT);
        }

        static if(HasTextures)
        {
            static if(HasLight)
            {
                auto lightProx = LightProxT(alloc,prepared.pack,prepared.spans,extContext);
            }

            void drawSpan(uint AffLen, bool UseDither, S, L)(
                int y,
                int x1, int x2,
                in auto ref S span,
                auto ref L line)
            {
                enum FixedLen = (AffLen > 0);
                //assert((x2 - x1) <= AffLen);
                assert(x2 > x1);
                static if(HasTextures)
                {
                    struct Transform
                    {
                    @nogc pure nothrow:
                        static if(HasLight)
                        {
                            ArrayView!int view;
                            auto opCall(T)(in T val,int x) const
                            {
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
                        const int y;
                        TexT u;
                        TexT v;
                        const TexT dux;
                        const TexT dvx;
                        enum dither = UseDither;
                    }
                    Context ctx = {x: x1, y: y, u: span.u, v: span.v, dux: span.dux, dvx: span.dvx};
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
                        assert(x2 == (x1 + AffLen));
                        extContext.texture.getLine!AffLen(ctx,line[x1..x1 + AffLen]);
                        //extContext.texture.getLine!AffLen(ctx,ntsRange(line[x1..x2]));
                    }
                    else
                    {
                        extContext.texture.getLine!0(ctx,line[x1..x2]);
                    }
                    //line[x1..x2] = (UseDither ? ColorRed : ColorGreen);
                }
            }

            const clipSize = Size(clipRect.w,clipRect.h);
            void outerLoop(bool Affine)()
            {
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
                    const sy = max(clipRect.y, prepared.spans.y0);

                    const sx = max(clipRect.x, prepared.spans.spans(sy).x0);
                    const ey = min(clipRect.y + clipRect.h, prepared.spans.y1);
                    const minX = clipRect.x;
                    const maxX = clipRect.x + clipRect.w;
                    const spans = prepared.spans.spns.ptr - prepared.spans.y0; //optimization
                }

                static if(FillBack)
                {
                    const backColor = outContext.backColor;
                    const beginLine = clipRect.x;
                    const endLine   = clipRect.x + clipRect.w;
                    auto line = outContext.surface[clipRect.y];
                    foreach(y;clipRect.y..sy)
                    {
                        line[beginLine..endLine] = backColor;
                        ++line;
                    }
                }
                else
                {
                    auto line = outContext.surface[sy];
                }

                alias SpanT = Span!(prepared.pack.pos_t, Affine);

                auto span = SpanT(prepared.pack, sx, sy, clipSize);
                void innerLoop(uint AffLen, bool UseDither)()
                {
                    foreach(y;sy..ey)
                    {
                        static if(!Full)
                        {
                            //const yspan = prepared.spans.spans(y);
                            const yspan = spans[y];
                            const x0 = max(minX, yspan.x0);
                            const x1 = min(maxX, yspan.x1);
                            if(y == sy)
                            {
                                assert(x0 == sx);
                                span.initX();
                            }
                            else
                            {
                                const dx = x0 - sx;
                                span.incXY(dx);
                            }

                            const validLine = (x1 > x0);
                        }
                        else
                        {
                            if(y == sy)
                            {
                                span.initX();
                            }
                            else
                            {
                                span.incXY();
                            }
                            enum validLine = true;
                        }

                        if(validLine)
                        {
                            static if(FillBack)
                            {
                                line[beginLine..x0] = backColor;
                            }

                            static if(HasLight)
                            {
                                lightProx.setXY(x0, y);
                            }
                            int x = x0;

                            static if(!Affine)
                            {
                                static if(!Full)
                                {
                                    /*const nx = (x + ((AffLen - 1)) & ~(AffLen - 1));
                                    assert(x >= clipRect.x);
                                    if(nx > x && nx < x1)
                                    {
                                        assert(nx <= (clipRect.x + clipRect.w));
                                        static if(HasLight) lightProx.incX();
                                        span.incX(nx - x - 1);
                                        drawSpan!(0,UseDither)(y, x, nx, span, line);
                                        x = nx;
                                    }
                                    const affParts = ((x1-x) / AffLen);*/
                                    const affParts = ((x1-x0) / AffLen);
                                }
                                else
                                {
                                    //Full
                                    enum affParts = TWidth / AffLen;
                                }

                                foreach(i;0..affParts)
                                {
                                    assert(x >= clipRect.x);
                                    assert((x + AffLen) <= (clipRect.x + clipRect.w));
                                    span.incX(AffLen);
                                    static if(HasLight) lightProx.incX();
                                    drawSpan!(AffLen,UseDither)(y, x, x + AffLen, span, line);
                                    x += AffLen;
                                }

                                static if(!Full)
                                {
                                    assert(x <= (clipRect.x + clipRect.w));
                                    const rem = (x1 - x);
                                    assert(rem >= 0);
                                    if(rem > 0)
                                    {
                                        span.incX(rem);
                                        static if(HasLight) lightProx.incX();
                                        drawSpan!(0,UseDither)(y, x, x1, span, line);
                                    }
                                }
                            }
                            else
                            {
                                static if(HasLight) lightProx.incX();
                                static if(Full)
                                {
                                    span.incX(TWidth);
                                    drawSpan!(TWidth,UseDither)(y, x, x + TWidth, span, line);
                                }
                                else
                                {
                                    span.incX(x1 - x0);
                                    drawSpan!(0,UseDither)(y, x0, x1, span, line);
                                }
                            }

                            static if(FillBack)
                            {
                                line[x1..endLine] = backColor;
                            }
                        }
                        else static if(FillBack)
                        {
                            line[beginLine..endLine] = backColor;
                        }

                        debug
                        {
                            static if(FillBack)
                            {
                                outContext.pixelsDrawn += (endLine - beginLine);
                            }
                            else
                            {
                                outContext.pixelsDrawn += (x1 - x0);
                            }
                        }

                        ++line;
                    }

                    static if(FillBack)
                    {
                        foreach(y;ey..(clipRect.y + clipRect.h))
                        {
                            line[beginLine..endLine] = backColor;
                            ++line;
                        }
                    }
                }

                static if(UseDithering)
                {
                    const maxD = span.calcMaxD(3.0f);
                    const D = 1.0f / min(extContext.texture.width,extContext.texture.height);
                    if(maxD < D)
                    {
                        innerLoop!(AffineLength,true)();
                    }
                    else
                    {
                        innerLoop!(AffineLength,false)();
                    }
                }
                else
                {
                    innerLoop!(AffineLength,false)();
                }
            }

            const affineThresh = (24.0f / max(clipSize.w, clipSize.h));
            if(prepared.pack.wDiff < affineThresh)
            {
                outerLoop!(true)();
            }
            else
            {
                outerLoop!(false)();
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
                foreach(y;prepared.spans.y0..prepared.spans.y1)
                {
                    const x0 = prepared.spans.spans[y].x0;
                    const x1 = prepared.spans.spans[y].x1;
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
                    dstMask.y0 = prepared.spans.y0;
                    dstMask.y1 = prepared.spans.y1;
                    dstMask.x0 = mskMinX;
                    dstMask.x1 = mskMaxX;
                }
                else
                {
                    dstMask.x0 = min(mskMinX, dstMask.x0);
                    dstMask.x1 = max(mskMaxX, dstMask.x1);
                    dstMask.y0 = min(prepared.spans.y0, dstMask.y0);
                    dstMask.y1 = max(prepared.spans.y1, dstMask.y1);
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

    struct FlushParam(Context)
    {
        Context* context;
    }

    struct TrianglePrepared(PackT)
    {
        PackT pack;
        RelSpanRange spans;
    }

    static void flushData(PreparedT,FlushParam,CacheElem)(void[] data)
    {
        debugOut("flush");
        assert(data.length > FlushParam.sizeof);
        assert(0 == (data.length - FlushParam.sizeof) % CacheElem.sizeof);
        FlushParam* param = (cast(FlushParam*)data.ptr);
        const(CacheElem)[] cache = (cast(const(CacheElem)*)(data.ptr + FlushParam.sizeof))[0..(data.length - FlushParam.sizeof) / CacheElem.sizeof];

        auto alloc = param.context.allocators[0];
        auto allocState1 = alloc.state;
        scope(exit) alloc.restoreState(allocState1);

        const size = param.context.size;
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
        highTiles[0] = alloc.alloc(tilesSizes[0].w * tilesSizes[0].h, HighTile());
        foreach(i; TupleRange!(1,HighTileLevelCount + 1))
        {
            tilesSizes[i] = Size(tilesSizes[i - 1].w * 2, tilesSizes[i - 1].h * 2);
            static if(i < HighTileLevelCount)
            {
                highTiles[i] = alloc.alloc(tilesSizes[i].w * tilesSizes[i].h, HighTile());
            }
        }

        //alias PackT = Unqual!(typeof(cache[0]));
        auto tiles = alloc.alloc(tilesSizes[HighTileLevelCount].w * tilesSizes[HighTileLevelCount].h,Tile());
        //auto spans = alloc.alloc!RelSpanRange(cache.length);
        alias PackT = CacheElem.pack.pack_t;
        alias TrianglePreparedT = TrianglePrepared!(PackT);
        auto preparedTris = alloc.alloc!TrianglePreparedT(cache.length);

        const cacheLen = cache.length;

        enum MaskW = LowTileSize.w;
        enum MaskH = LowTileSize.h;
        alias MaskT = TileMask!(MaskW, MaskH);
        auto masks = alloc.alloc!MaskT(tilesSizes[HighTileLevelCount].w * tilesSizes[HighTileLevelCount].h);

        auto pool = param.context.myTaskPool;
        if(pool !is null)
        {
            auto allocState2 = saveAllocsStates(param.context.allocators);
            scope(exit) allocState2.restore();

            foreach(i;pool.parallel(iota(0,cacheLen), 4))
            {
                const workerIndex = pool.workerIndex;
                auto prepared = PreparedT(cache[i].pack);
                createTriangleSpans(allocState2.allocs[workerIndex], param.context, cache[i].extContext, prepared);

                if(prepared.valid)
                {
                    preparedTris[i].pack = PackT(cache[i].pack, size);
                    preparedTris[i].spans = prepared.spanrange;
                }
                else
                {
                    preparedTris[i].spans.spns = preparedTris[i].spans.spns.init;
                }
            }

            enum Xstep = max(256 / TileSize.w, 1);
            enum Ystep = max(256 / TileSize.h, 1);
            auto xyrange = cartesianProduct(iota(0, tilesSizes[0].h, Xstep), iota(0, tilesSizes[0].w, Ystep));

            foreach(pos; pool.parallel(xyrange, 1))
            {
                const workerIndex = pool.workerIndex;
                const y = pos[0];
                const x = pos[1];
                const x0 = max(x * TileSize.w, clipRect.x);
                const x1 = min(x0 + TileSize.w * Xstep, clipRect.x + clipRect.w);
                assert(x1 > x0);
                const y0 = max(y * TileSize.h, clipRect.y);
                const y1 = min(y0 + TileSize.h * Ystep, clipRect.y + clipRect.h);
                assert(y1 > y0);
                const rect = Rect(x0, y0, x1 - x0, y1 - y0);
                foreach_reverse(i;0..cacheLen)
                {
                    if(!preparedTris[i].spans.empty)
                    {
                        updateTiles(param, rect, highTiles, tiles, masks, tilesSizes, preparedTris[i].spans, cache[i].pack, cast(int)i);
                    }
                }
                const tx1 = x;
                const tx2 = min(tx1 + Xstep, tilesSizes[0].w);
                assert(tx2 > tx1);
                const ty1 = y;
                const ty2 = min(ty1 + Ystep, tilesSizes[0].h);
                assert(ty2 > ty1);
                drawTiles(param, alloc, Rect(tx1,ty1,tx2,ty2), highTiles, tiles, tilesSizes, cache, preparedTris);
            }
        }
        else
        {
            foreach_reverse(i;0..cacheLen)
            {
                auto prepared = PreparedT(cache[i].pack);
                createTriangleSpans(alloc, param.context, cache[i].extContext, prepared);

                if(!prepared.valid)
                {
                    continue;
                }
                preparedTris[i].pack = PackT(cache[i].pack, size);
                preparedTris[i].spans = prepared.spanrange;

                updateTiles(param, clipRect, highTiles, tiles, masks, tilesSizes, prepared.spanrange, cache[i].pack, cast(int)i);
            }
            drawTiles(param, alloc, Rect(0,0,tilesSizes[0].w,tilesSizes[0].h), highTiles, tiles, tilesSizes, cache, preparedTris);
        }
    }

    static void updateTiles(ParamsT,HTileT,TileT,MaskT,SpanT,PackT)
        (auto ref ParamsT params, in Rect clipRect, HTileT[][] htiles, TileT[] tiles, MaskT[] masks, in Size[] tilesSizes, auto ref SpanT spanrange, in auto ref PackT pack, int index)
    {
        assert(index >= 0);

        alias PosT    = pack.pos_t;
        alias LineT   = Line!(PosT);
        alias PointT  = Point!(PosT);

        const size = params.context.size;
        const LineT[3] lines = [
            LineT(pack.verts[0], pack.verts[1], pack.verts[2], size),
            LineT(pack.verts[1], pack.verts[2], pack.verts[0], size),
            LineT(pack.verts[2], pack.verts[0], pack.verts[1], size)];

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
            const firstTilesSize = tilesSizes[0];
            assert(y >= 0);
            assert(y < firstTilesSize.h);
            const ty0 = y * TileSize.h;
            const ty1 = ty0 + TileSize.h;
            assert(ty1 > ty0);

            const sy0 = max(spanrange.y0, ty0, clipRect.y);
            const sy1 = min(spanrange.y1, ty1, clipRect.y + clipRect.h);
            assert(sy1 > sy0);
            const bool yEdge = (TileSize.h != (sy1 - sy0));

            const tx1 = (max(spanrange.x0, clipRect.x) / TileSize.w);
            const tx2 = ((min(spanrange.x1, clipRect.x + clipRect.w) + TileSize.w - 1) / TileSize.w);
            const sx = tx1 * TileSize.w;
            auto pt1 = PointT(cast(int)sx, cast(int)ty0, lines);
            auto pt2 = PointT(cast(int)sx, cast(int)ty1, lines);
            uint val = (pt1.vals() << 0) | (pt2.vals() << 8);

            bool hadOne = false;

            auto htiles0Local = htiles[0].ptr + y * firstTilesSize.w;
            foreach(x; tx1..tx2)
            {
                assert(x >= 0);
                assert(x < firstTilesSize.w);
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

                auto tile = &htiles0Local[x];
                assert(tile is &htiles[0][x + y * firstTilesSize.w]);
                if(tile.used || tile.childrenFull)
                {
                    continue;
                }

                if(!tile.hasChildren && all(u.oldval))
                {
                    tile.set(index);
                }
                else/* if(!tile.childrenFull)*/
                {
                    HighTile.type_t checkTile(Size TSize, int Level, bool Full)(int tx, int ty, in ubyte[4] prevVals)
                    {
                        static assert(TSize.w > 0 && TSize.h > 0);
                        static assert(Level >= 0);
                        assert(4 == prevVals.length);
                        const x = tx * TSize.w;
                        const y = ty * TSize.h;

                        const pt1 = cast(uint)prevVals[0];//*/pointPlanesVals(cast(int)x              , cast(int)y              , lines)
                        const pt2 = pointPlanesVals(cast(int)x + TSize.w    , cast(int)y              , lines);
                        const pt3 = cast(uint)prevVals[2];//*/pointPlanesVals(cast(int)x + TSize.w * 2, cast(int)y              , lines);
                        const pt4 = pointPlanesVals(cast(int)x              , cast(int)y + TSize.h    , lines);
                        const pt5 = pointPlanesVals(cast(int)x + TSize.w    , cast(int)y + TSize.h    , lines);
                        const pt6 = pointPlanesVals(cast(int)x + TSize.w * 2, cast(int)y + TSize.h    , lines);
                        const pt7 = cast(uint)prevVals[1];//*/pointPlanesVals(cast(int)x              , cast(int)y + TSize.h * 2, lines);
                        const pt8 = pointPlanesVals(cast(int)x + TSize.w    , cast(int)y + TSize.h * 2, lines);
                        const pt9 = cast(uint)prevVals[3];//*/pointPlanesVals(cast(int)x + TSize.w * 2, cast(int)y + TSize.h * 2, lines);
                        const uint[4] vals = [
                            (pt1 << 0) | (pt4 << 8) | (pt2 << 16) | (pt5 << 24),
                            (pt2 << 0) | (pt5 << 8) | (pt3 << 16) | (pt6 << 24),
                            (pt4 << 0) | (pt7 << 8) | (pt5 << 16) | (pt8 << 24),
                            (pt5 << 0) | (pt8 << 8) | (pt6 << 16) | (pt9 << 24)];

                        const tilesSize = tilesSizes[Level];
                        const initialTileOffset = tx + ty * tilesSize.w;
                        enum gamelib.types.Point[4] offsetPoints = [
                             gamelib.types.Point(0,0),
                             gamelib.types.Point(1,0),
                             gamelib.types.Point(0,1),
                             gamelib.types.Point(1,1)
                        ];
                        static if(Level < HighTileLevelCount)
                        {
                            auto htilesLocal = htiles[Level].ptr + initialTileOffset;
                            HighTile.type_t childrenFullMask = 0;
                            foreach(i;0..4)
                            {
                                const offsetPointLocal = offsetPoints[i];
                                const tileOffset = offsetPointLocal.x + offsetPointLocal.y * tilesSize.w;

                                const currPt = gamelib.types.Point(tx + (i & 1), ty + ((i >> 1) & 1));
                                assert(currPt.x >= 0);
                                assert(currPt.x < tilesSize.w);
                                assert(currPt.y >= 0);
                                assert(currPt.y < tilesSize.h);
                                assert((initialTileOffset + tileOffset) == (currPt.x + currPt.y * tilesSize.w));

                                assert((initialTileOffset + tileOffset) < htiles[Level].length);
                                auto tile = &htilesLocal[tileOffset];
                                if(tile.used || tile.childrenFull)
                                {
                                    childrenFullMask |= (1 << i);
                                    continue;
                                }

                                const valLocal = vals[i];
                                if(!tile.hasChildren && all(valLocal))
                                {
                                    childrenFullMask |= (1 << i);
                                    tile.set(index);
                                }
                                else if(!none(valLocal))
                                {
                                    tile.setChildren();
                                    const U temp = {oldval: valLocal };
                                    const childrenMask = checkTile!(Size(TSize.w >> 1, TSize.h >> 1), Level + 1,Full)(currPt.x * 2, currPt.y * 2, temp.vals);
                                    tile.SetChildrenFullMask(childrenMask);
                                    if(0xf == childrenMask)
                                    {
                                        childrenFullMask |= (1 << i);
                                    }
                                }
                            }
                            return childrenFullMask;
                        }
                        else static if(Level == HighTileLevelCount)
                        {
                            auto tilesLocal = tiles.ptr + initialTileOffset;
                            auto masksLocal = masks.ptr + initialTileOffset;
                            const spanrangeLocal = spanrange;
                            HighTile.type_t childrenFullMask = 0;
                            foreach(i;0..4)
                            {
                                const offsetPointLocal = offsetPoints[i];
                                const tileOffset = offsetPointLocal.x + offsetPointLocal.y * tilesSize.w;

                                assert((initialTileOffset + tileOffset) < tiles.length);
                                assert((initialTileOffset + tileOffset) < masks.length);
                                auto tile = &tilesLocal[tileOffset];
                                if(tile.full)
                                {
                                    childrenFullMask |= (1 << i);
                                    continue;
                                }

                                debug
                                {
                                    const currPt = gamelib.types.Point(tx + (i & 1), ty + ((i >> 1) & 1));
                                    assert(currPt.x >= 0);
                                    assert(currPt.x < tilesSize.w);
                                    assert(currPt.y >= 0);
                                    assert(currPt.y < tilesSize.h);
                                    assert((initialTileOffset + tileOffset) == (currPt.x + currPt.y * tilesSize.w));
                                }

                                static if(Full)
                                {
                                    const int x0 = (tx + offsetPointLocal.x) * TSize.w;
                                    const int x1 = x0 + TSize.w;

                                    const int y0 = (ty + offsetPointLocal.y) * TSize.h;
                                    const int y1 = y0 + TSize.h;
                                }
                                else
                                {
                                    const int x0 = (tx + offsetPointLocal.x) * TSize.w;
                                    const int x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);

                                    const int y0 = (ty + offsetPointLocal.y) * TSize.h;
                                    const int y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);

                                    if(x0 >= x1)
                                    {
                                        continue;
                                    }

                                    if(y0 >= y1)
                                    {
                                        break;
                                    }

                                    if(spanrangeLocal.x1 <= x0 || spanrangeLocal.x0 >= x1 || spanrangeLocal.y0 >= y1)
                                    {
                                        continue;
                                    }

                                    if(spanrangeLocal.y1 <= y0)
                                    {
                                        break;
                                    }
                                }

                                assert(x1 > x0);
                                assert(y1 > y0);

                                const valLocal = vals[i];
                                if(none(valLocal))
                                {
                                    continue;
                                }

                                if(all(valLocal))
                                {
                                    tile.addTriangle(index, true);
                                    childrenFullMask |= (1 << i);
                                }
                                else
                                {
                                    const sy0 = max(spanrangeLocal.y0, y0);
                                    const sy1 = min(spanrangeLocal.y1, y1);
                                    assert(sy1 > sy0);

                                    auto mask = &masksLocal[tileOffset];
                                    assert(mask.data.length == TSize.h);
                                    if(tile.empty)
                                    {
                                        enum FullMask = mask.FullMask;
                                        const dy0 = sy0 - y0;
                                        assert(dy0 >= 0);
                                        mask.data[0..dy0] = 0;
                                        mask.fmask_t fmask = 0;

                                        const spans = spanrangeLocal.spns.ptr - spanrangeLocal.y0;
                                        auto maskData = mask.data.ptr;
                                        foreach(my; sy0..sy1)
                                        {
                                            const span = spans[my];
                                            const sx0 = max(span.x0, x0);
                                            const sx1 = min(span.x1, x1);
                                            const myr = my - y0;
                                            mask.type_t maskVal = 0;
                                            if(sx1 > sx0)
                                            {
                                                const sh0 = (sx0 - x0);
                                                const sh1 = (x0 + TSize.w - sx1);
                                                const val = (FullMask >> sh0) & (FullMask << sh1);
                                                assert(0 != val);
                                                maskVal = val;
                                                fmask |= ((cast(mask.fmask_t)(FullMask == val)) << myr);
                                            }
                                            maskData[myr] = maskVal;
                                        }

                                        const bool full = (FullMask == fmask);
                                        tile.addTriangle(index, full);
                                        if(full)
                                        {
                                            childrenFullMask |= (1 << i);
                                        }
                                        const dy1 = (y0 + mask.height) - sy1;
                                        assert(dy1 >= 0);
                                        mask.data[$ - dy1..$] = 0;
                                        mask.fmask = fmask;
                                        assert(full == mask.full);

                                    }
                                    else //tile.empty
                                    {
                                        assert(!mask.full);
                                        enum FullMask = mask.FullMask;
                                        mask.type_t visible = 0;
                                        const dy0 = sy0 - y0;
                                        assert(dy0 >= 0);
                                        mask.fmask_t fmask = mask.fmask;

                                        const spans = spanrangeLocal.spns.ptr - spanrangeLocal.y0;
                                        auto maskData = mask.data.ptr;
                                        foreach(my; sy0..sy1)
                                        {
                                            const span = spans[my];
                                            const sx0 = max(span.x0, x0);
                                            const sx1 = min(span.x1, x1);
                                            const myr = my - y0;
                                            if(sx1 > sx0)
                                            {
                                                const sh0 = (sx0 - x0);
                                                const sh1 = (x0 + TSize.w - sx1);
                                                const val = (FullMask >> sh0) & (FullMask << sh1);
                                                assert(0 != val);
                                                const oldMaskVal = maskData[myr];
                                                visible |= (val & ~oldMaskVal);
                                                const newMaskVal = oldMaskVal | val;
                                                maskData[myr] = newMaskVal;
                                                fmask |= ((cast(mask.fmask_t)(FullMask == newMaskVal)) << myr);
                                            }
                                        }

                                        if(0 != visible)
                                        {
                                            const bool full = (FullMask == fmask);
                                            tile.addTriangle(index, full);
                                            if(full)
                                            {
                                                childrenFullMask |= (1 << i);
                                            }
                                        }
                                        const dy1 = (y0 + mask.height) - sy1;
                                        assert(dy1 >= 0);
                                        mask.fmask = fmask;
                                        assert((FullMask == fmask) == mask.full);
                                    }
                                }
                            }
                            //htiles[Level - 1][(tx >> 1) + (ty >> 1) * tilesSizes[Level - 1].w].SetChildrenFullMask(childrenFullMask);
                            return childrenFullMask;
                        }
                        else static assert(false);
                    }

                    tile.setChildren();
                    if(yEdge ||
                        ((x * TileSize.w + TileSize.w) > (clipRect.x + clipRect.w)) ||
                        ((x * TileSize.w) < clipRect.x))
                    {
                        tile.SetChildrenFullMask(checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1,false)(x * 2, y * 2, u.vals));
                    }
                    else
                    {
                        tile.SetChildrenFullMask(checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1,true)(x * 2, y * 2, u.vals));
                    }
                }
            }
        }

        auto yrange = iota(
            (max(spanrange.y0, clipRect.y) / TileSize.h),
            ((min(spanrange.y1, clipRect.y + clipRect.h) + TileSize.h - 1) / TileSize.h));

        foreach(y; yrange)
        {
            updateLine(y);
        }
    }

    static void drawTiles(ParamsT,AllocT,HTileT,TileT,CacheT,PrepT)
        (auto ref ParamsT params, auto ref AllocT alloc, in Rect tilesDim, HTileT[][] htiles, TileT[] tiles, in Size[] tilesSizes, CacheT[] cache, PrepT[] prepared)
    {
        const clipRect = params.context.clipRect;
        void drawTile(Size TSize, int Level, bool Full, AllocT)(int tx, int ty, auto ref AllocT alloc)
        {
            static assert(TSize.w > 0 && TSize.h > 0);
            static assert(Level >= 0);
            enum FullDrawWidth = TSize.w;

            assert(tx >= 0);
            assert(tx < tilesSizes[Level].w);
            assert(ty >= 0);
            assert(ty < tilesSizes[Level].h);

            const x0 = tx * TSize.w;
            assert(x0 >= clipRect.x);
            if(!Full && x0 >= (clipRect.x + clipRect.w))
            {
                return;
            }
            const y0 = ty * TSize.h;
            assert(y0 >= clipRect.y);
            if(!Full && y0 >= (clipRect.y + clipRect.h))
            {
                return;
            }

            static if(Level < HighTileLevelCount)
            {
                auto tile = &htiles[Level][tx + ty * tilesSizes[Level].w];

                if(tile.hasChildren)
                {
                    foreach(i;0..4)
                    {
                        drawTile!(Size(TSize.w >> 1, TSize.h >> 1), Level + 1, Full)(tx * 2 + (i & 1), ty * 2 + ((i >> 1) & 1), alloc);
                    }
                }
                else if(tile.used)
                {
                    static if(Full)
                    {
                        const x1 = x0 + TSize.w;
                        const y1 = y0 + TSize.h;
                    }
                    else
                    {
                        const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                        const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                    }
                    assert(x1 > x0);
                    assert(y1 > y0);
                    assert(x0 >= clipRect.x);
                    assert(y0 >= clipRect.y);
                    assert(x1 <= clipRect.x + clipRect.w);
                    assert(y1 <= clipRect.y + clipRect.h);
                    const rect = Rect(x0, y0, x1 - x0, y1 - y0);

                    const index = tile.index;
                    if(rect.w == TSize.w)
                    {
                        drawPreparedTriangle!(FullDrawWidth, false)(alloc, rect, params.context, cache[index].extContext, prepared[index]);
                    }
                    else
                    {
                        drawPreparedTriangle!(0,false)(alloc, rect, params.context, cache[index].extContext, prepared[index]);
                    }
                }
                else static if(FillBackground)
                {
                    static if(Full)
                    {
                        const x1 = x0 + TSize.w;
                        const y1 = y0 + TSize.h;
                    }
                    else
                    {
                        const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                        const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                    }
                    assert(x1 > x0);
                    assert(y1 > y0);
                    assert(x0 >= clipRect.x);
                    assert(y0 >= clipRect.y);
                    assert(x1 <= clipRect.x + clipRect.w);
                    assert(y1 <= clipRect.y + clipRect.h);
                    const rect = Rect(x0, y0, x1 - x0, y1 - y0);

                    fillBackground(rect, params.context);
                }
            }
            else static if(Level == HighTileLevelCount)
            {
                auto tile = &tiles[tx + ty * tilesSizes[Level].w];
                if(tile.empty)
                {
                    static if(FillBackground)
                    {
                        static if(Full)
                        {
                            const x1 = x0 + TSize.w;
                            const y1 = y0 + TSize.h;
                        }
                        else
                        {
                            const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                            const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                        }
                        assert(x1 > x0);
                        assert(y1 > y0);
                        assert(x0 >= clipRect.x);
                        assert(y0 >= clipRect.y);
                        assert(x1 <= clipRect.x + clipRect.w);
                        assert(y1 <= clipRect.y + clipRect.h);
                        const rect = Rect(x0, y0, x1 - x0, y1 - y0);
                        fillBackground(rect, params.context);
                    }
                    return;
                }

                static if(Full)
                {
                    const x1 = x0 + TSize.w;
                    const y1 = y0 + TSize.h;
                }
                else
                {
                    const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                    const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                }
                assert(x1 > x0);
                assert(y1 > y0);
                assert(x0 >= clipRect.x);
                assert(y0 >= clipRect.y);
                assert(x1 <= clipRect.x + clipRect.w);
                assert(y1 <= clipRect.y + clipRect.h);
                const rect = Rect(x0, y0, x1 - x0, y1 - y0);

                auto buff = tile.buffer[0..tile.length];
                assert(buff.length > 0);

                if(tile.covered && (Full || (rect.w == FullDrawWidth)))
                {
                    const index = buff.back;
                    assert(index >= 0);
                    assert(index < cache.length);
                    drawPreparedTriangle!(FullDrawWidth,false)(alloc, rect, params.context, cache[index].extContext, prepared[index]);
                    buff.popBack;
                }
                else static if(FillBackground)
                {
                    const index = buff.back;
                    assert(index >= 0);
                    assert(index < cache.length);
                    drawPreparedTriangle!(0,true)(alloc, rect, params.context, cache[index].extContext, prepared[index]);
                    buff.popBack;
                }

                foreach(const index; buff.retro)
                {
                    assert(index >= 0);
                    assert(index < cache.length);
                    drawPreparedTriangle!(0,false)(alloc, rect, params.context, cache[index].extContext, prepared[index]);
                }
            }
            else static assert(false);
        }

        void drawTileDispatch(AllocT)(int x, int y, auto ref AllocT alloc)
        {
            if(((x * TileSize.w + TileSize.w) < (clipRect.x + clipRect.w)) &&
               ((y * TileSize.h + TileSize.h) < (clipRect.y + clipRect.h)))
            {
                drawTile!(TileSize,0,true)(x,y,alloc);
            }
            else
            {
                drawTile!(TileSize,0,false)(x,y,alloc);
            }
        }

        foreach(y;tilesDim.y..tilesDim.h)
        {
            foreach(x;tilesDim.x..tilesDim.w)
            {
                drawTileDispatch(x,y,alloc);
            }
        }
    }

    static void drawTriangle(CtxT1,CtxT2,VertT)
        (auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
    {
        assert(pverts.length == 3);
        alias PosT = Unqual!(typeof(VertT.pos.x));

        auto prepared = prepareTriangle(outContext, extContext, pverts);
        alias PreparedT = Unqual!(typeof(prepared));

        if(!prepared.valid)
        {
            return;
        }

        if(TiledRendering)
        {
            alias CacheElemT = CacheElem!(Unqual!(typeof(prepared.pack)), Unqual!CtxT2);
            enum CacheElemSize = CacheElemT.sizeof;
            alias FlushParamT = FlushParam!(Unqual!CtxT1);
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
                *(cast(FlushParamT*)outContext.rasterizerCache.ptr) = FlushParamT(&outContext);
                outContext.flushFunc = ownFunc;
            }

            auto newElem = CacheElemT(prepared.pack, extContext);
            (outContext.rasterizerCache.ptr + outContext.rasterizerCacheUsed)[0..CacheElemT.sizeof] = (cast(void*)&newElem)[0..CacheElemT.sizeof];
            outContext.rasterizerCacheUsed += CacheElemSize;
        }
        else
        {
            auto alloc = outContext.allocators[0];
            auto allocState1 = alloc.state;
            scope(exit) alloc.restoreState(allocState1);
            createTriangleSpans(alloc, outContext, extContext, prepared);

            if(!prepared.valid)
            {
                return;
            }

            //drawPreparedTriangle!(0,false)(alloc, outContext.clipRect, outContext, extContext, prepared);
        }
    }

}
