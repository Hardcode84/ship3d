﻿module game.renderer.rasterizerhybrid2;

import std.traits;
import std.algorithm;
import std.array;
import std.string;
import std.functional;
import std.range;

import gamelib.util;
import gamelib.graphics.graph;
import gamelib.memory.utils;
import gamelib.memory.arrayview;

import game.units;

@nogc:

struct RasterizerHybrid2(bool HasTextures, bool WriteMask, bool ReadMask, bool HasLight)
{
    static void drawIndexedTriangle(AllocT,CtxT1,CtxT2,VertT,IndT)
        (auto ref AllocT alloc, auto ref CtxT1 outputContext, auto ref CtxT2 extContext, in VertT[] verts, in IndT[] indices) if(isIntegral!IndT)
    {
        assert(indices.length == 3);
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        drawTriangle(alloc, outputContext, extContext, pverts);
    }

private:
    enum AffineLength = 16;
    struct Line(PosT)
    {
    pure nothrow:
    @nogc:
        immutable PosT dx, dy, c;

        this(VT,ST)(in VT v1, in VT v2, in VT v3, in ST size)
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            const w1 = v1.pos.w;
            const w2 = v2.pos.w;
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
    pure nothrow:
    @nogc:
        immutable PosT dx;
        immutable PosT dy;
        immutable PosT c;
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
    @nogc:
        immutable bool degenerate;
        immutable bool external;
        enum HasTexture = !is(TextT : void);
        alias vec2 = Vector!(PosT,2);
        alias vec3 = Vector!(PosT,3);
        alias PlaneT = Plane!(PosT);
        enum NumLines = 3;
        immutable LineT[NumLines] lines;

        immutable PlaneT wplane;

        static if(HasTexture)
        {
            alias vec3tex = Vector!(TextT,3);
            alias PlaneTtex = Plane!(TextT);
            immutable PlaneTtex uplane;
            immutable PlaneTtex vplane;
        }
        static if(HasLight)
        {
            immutable PlaneT refXplane, refYplane, refZplane;
            immutable vec3 normal;
        }
        this(VT,ST)(in VT v1, in VT v2, in VT v3, in ST size) pure nothrow
        {
            lines = [
                LineT(v1, v2, v3, size),
                LineT(v2, v3, v1, size),
                LineT(v3, v1, v2, size)];

            const w1 = v1.pos.w;
            const w2 = v2.pos.w;
            const w3 = v3.pos.w;
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const x3 = v3.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            const y3 = v3.pos.y;
            const mat = Matrix!(PosT,3,3)(x1, y1, w1,
                                          x2, y2, w2,
                                          x3, y3, w3);
            const d = mat.det;
            if(d <= 0 || (w1 > 0 && w2 > 0 && w3 > 0))
            {
                degenerate = true;
                return;
            }
            degenerate = false;
            const dw = 0.0001;
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
    pure nothrow:
        enum NumLines = 3;
        int currx = void;
        int curry = void;
        PosT[NumLines] cx = void;
        PosT[NumLines] dx = void;
        PosT[NumLines] dy = void;
        this(PackT)(in ref PackT p, int x, int y)
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                const val = p.lines[i].val(x, y);
                cx[i] = val;
                dx[i] = -p.lines[i].dx;
                dy[i] =  p.lines[i].dy;
            }
            currx = x;
            curry = y;
        }

        void incX(int val)
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cx[i] += dx[i] * val;
            }
            currx += val;
        }

        void incY(int val)
        {
            foreach(i;TupleRange!(0,NumLines))
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
    pure nothrow:
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
    pure nothrow:
    @nogc:
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
            foreach(i;TupleRange!(0,Len))
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

    struct SpanRange
    {
        struct Span
        {
            int x0, x1;
        }
        int y0;
        int y1;
        Span[] spans;
    }

    static void drawTriangle(AllocT,CtxT1,CtxT2,VertT)
        (auto ref AllocT alloc, auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
    {
        assert(pverts.length == 3);
        //alias PosT = FixedPoint!(16,16,int);
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
        alias PointT  = Point!(PosT);
        alias SpanT   = Span!(PosT);
        static if(HasLight)
        {
            alias LightProxT = LightProxy!(AffineLength, PosT);
        }

        const clipRect = outContext.clipRect;
        const size = outContext.size;

        static if(ReadMask)
        {
            const srcMask = &outContext.mask;
            if(srcMask.isEmpty)
            {
                return;
            }
        }
        static if(WriteMask)
        {
            auto  dstMask = &outContext.dstMask;
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
            return;
        }

        immutable pack = PackT(pverts[0], pverts[1], pverts[2], size);
        if(pack.degenerate)
        {
            return;
        }

        SpanRange spanrange;
        spanrange.spans = alloc.alloc!(SpanRange.Span)(size.h);

        if(PointT(pack, minX, minY).check() &&
           PointT(pack, maxX, minY).check() &&
           PointT(pack, minX, maxY).check() &&
           PointT(pack, maxX, maxY).check())
        {
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
                spanrange.spans[y].x0 = xc0;
                spanrange.spans[y].x1 = xc1;
            }
        }
        else if(pack.external)
        {
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
                    auto pt = PointT(pack, xs, y);
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
                foreach(const ref v; pverts)
                {
                    const w = v.pos.w;
                    const x = cast(int)((v.pos.x / w) * size.w) + size.w / 2;
                    const y = cast(int)((v.pos.y / w) * size.h) + size.h / 2;


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
                    auto ptc0 = PointT(pack, cx, y0);
                    auto pt0c = PointT(pack, x0, cy);
                    auto ptcc = PointT(pack, cx, cy);
                    auto pt1c = PointT(pack, x1, cy);
                    auto ptc1 = PointT(pack, cx, y1);
                    return checkQuad(pt00, ptc0, pt0c, ptcc) ||
                           checkQuad(ptc0, pt10, ptcc, pt1c) ||
                           checkQuad(pt0c, ptcc, pt01, ptc1) ||
                           checkQuad(ptcc, pt1c, ptc1, pt11);
                }
                if(checkQuad(PointT(pack, minX, minY),
                             PointT(pack, maxX, minY),
                             PointT(pack, minX, maxY),
                             PointT(pack, maxX, maxY)))
                {
                    goto found;
                }
                //nothing found
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
                    static import gamelib.math;
                    spanrange.spans[pt.curry].x0 = gamelib.math.clamp(x0, leftBound, rightBound);
                    spanrange.spans[pt.curry].x1 = gamelib.math.clamp(x1, leftBound, rightBound);
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
                const pt0 = PointT(pack, x0, y);
                const pt1 = PointT(pack, x1, y);
                if(none(pt0.vals() | (pt1.vals() << 3)))
                {
                    return false;
                }
                enum Step = 16;
                if((x1 - x0) >= Step)
                {
                    foreach(i;0..Step)
                    {
                        auto pt = PointT(pack, x0 + i, y);
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
                auto pt = PointT(pack, e, y);
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
                    const cp = PointT(pack, p0.currx + d / 2, y);
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
                    const pt = PointT(pack, x, y);
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
            foreach(int i,const ref v; pverts[])
            {
                const pos = (v.pos.xy / v.pos.w);
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
                immutable FP dx;
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

                @property x() const { return cast(int)(currX + 1.0f); }
            }

            Edge[3] edges = void;
            bool revX = void;
            if(sortedPos[1].y < sortedPos[2].y)
            {
                revX = true;
                edges[] = [
                    Edge(sortedPos[0],sortedPos[2]),
                    Edge(sortedPos[0],sortedPos[1]),
                    Edge(sortedPos[1],sortedPos[2])];
            }
            else
            {
                revX = false;
                edges[] = [
                    Edge(sortedPos[0],sortedPos[1]),
                    Edge(sortedPos[0],sortedPos[2]),
                    Edge(sortedPos[2],sortedPos[1])];
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
                                    spanrange.spans[y].x0 = xc0;
                                }
                                spanrange.spans[y].x1 = xc1;
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
        } //external
        if(spanrange.y0 >= spanrange.y1) return;

        static if(HasTextures)
        {
            static if(HasLight)
            {
                auto lightProx = LightProxT(alloc,pack,spanrange,extContext);
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
                            auto opCall(T)(in T val,int) const { return val; }
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
                        extContext.texture.getLine!AffineLength(ctx,line[x1..x2]);
                    }
                    else
                    {
                        enum SmallLine = 4;
                        foreach(sx;0..(x2 - x1) / SmallLine)
                        {
                            extContext.texture.getLine!SmallLine(ctx,line[ctx.x..ctx.x+SmallLine]);
                            ctx.u += ctx.dux * SmallLine;
                            ctx.v += ctx.dvx * SmallLine;
                            ctx.x += SmallLine;
                        }
                        foreach(x;ctx.x..x2)
                        {
                            extContext.texture.getLine!1(ctx,line[x..x+1]);
                            ctx.u += ctx.dux;
                            ctx.v += ctx.dvx;
                            ++ctx.x;
                        }
                    }
                }
            }

            const sx = spanrange.spans[spanrange.y0].x0;
            auto span = SpanT(pack, sx, spanrange.y0);

            auto line = outContext.surface[spanrange.y0];
            foreach(y;spanrange.y0..spanrange.y1)
            {
                const x0 = spanrange.spans[y].x0;
                const x1 = spanrange.spans[y].x1;
                span.incX(x0 - sx);
                static if(HasLight)
                {
                    lightProx.setXY(x0, y);
                }
                int x = x0;
                {
                    const nx = (x + (AffineLength - 1)) & ~(AffineLength - 1);
                    if(nx > x && nx < x1)
                    {
                        static if(HasLight) lightProx.incX();
                        span.incX(nx - x - 1);
                        drawSpan!false(y, x, nx, span, line);
                        x = nx;
                    }
                }
                foreach(i;0..((x1-x) / AffineLength))
                {
                    span.incX(AffineLength);
                    static if(HasLight) lightProx.incX();
                    drawSpan!true(y, x, x + AffineLength, span, line);
                    x += AffineLength;
                }
                const rem = (x1 - x);
                if(rem > 0)
                {
                    span.incX(rem);
                    static if(HasLight) lightProx.incX();
                    drawSpan!false(y, x, x1, span, line);
                }
                /*if(pack.external)
                {
                    line[x0..x1] = ColorRed;
                }
                else
                {
                    line[x0..x1] = ColorBlue;
                }*/
                span.incY();
                ++line;
            }
        }

        static if(WriteMask)
        {
            void writeMask(bool Empty)()
            {
                static immutable colors = [ColorRed,ColorGreen,ColorBlue];
                int mskMinX = maxX;
                int mskMaxX = minX;
                foreach(y;spanrange.y0..spanrange.y1)
                {
                    const x0 = spanrange.spans[y].x0;
                    const x1 = spanrange.spans[y].x1;
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
                    dstMask.y0 = spanrange.y0;
                    dstMask.y1 = spanrange.y1;
                    dstMask.x0 = mskMinX;
                    dstMask.x1 = mskMaxX;
                }
                else
                {
                    dstMask.x0 = min(mskMinX, dstMask.x0);
                    dstMask.x1 = max(mskMaxX, dstMask.x1);
                    dstMask.y0 = min(spanrange.y0, dstMask.y0);
                    dstMask.y1 = max(spanrange.y1, dstMask.y1);
                }
            }

            if(dstMask.isEmpty) writeMask!true();
            else                writeMask!false();
        }
        //end
    }

}