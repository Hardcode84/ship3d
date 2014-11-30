module game.renderer.rasterizerhp6;

import std.traits;
import std.algorithm;
import std.array;
import std.string;
import std.functional;
import std.range;
import std.c.stdlib: alloca;

import gamelib.util;
import gamelib.math;
import gamelib.graphics.graph;
import gamelib.memory.utils;

import game.units;

@nogc:

struct RasterizerHP6(bool HasTextures, bool WriteMask, bool ReadMask)
{
    static void drawIndexedTriangle(CtxT1,CtxT2,VertT,IndT)
        (auto ref CtxT1 outputContext, auto ref CtxT2 extContext, in VertT[] verts, in IndT[] indices) if(isIntegral!IndT)
    {
        assert(indices.length == 3);
        /*const c = (verts[indices[1]].pos.xyz - verts[indices[0]].pos.xyz).cross(verts[indices[2]].pos.xyz - verts[indices[0]].pos.xyz);
        if(c.z <= 0)
        {
            return;
        }*/
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        drawTriangle(outputContext,extContext, pverts);
    }

private:
    enum AffineLength = 32;
    struct Line(PosT)
    {
    @nogc:
        immutable PosT dx, dy, c;

        this(VT,ST)(in VT v1, in VT v2, in VT v3, in ST size) pure nothrow
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            const w1 = v1.pos.w;
            const w2 = v2.pos.w;
            //const w = Affine ? cast(PosT)1 : cast(PosT)v3.pos.w;
            //dx = (x2 - x1) / w;
            //dy = (y2 - y1) / w;
            //const inc = (dy < 0 || (dy == 0 && dx > 0)) ? cast(PosT)1 / cast(PosT)8 : cast(PosT)0;
            //c = (dy * x1 - dx * y1) + inc;
            dx = (y2 * w1 - y1 * w2) / size.w;
            dy = (x2 * w1 - x1 * w2) / size.h;
            const inc = (dy < 0 || (almost_equal(dy, 0) && dx > 0)) ? cast(PosT)1 / cast(PosT)8 : cast(PosT)0;//TODO: fix
            c  = (x1 * y2 - x2 * y1) - dy * (size.h / 2) + dx * (size.w / 2) - inc * (dy + dx);
        }

        auto val(int x, int y) const pure nothrow
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
        enum HasTexture = !is(TextT : void);
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
        this(VT,ST)(in VT v1, in VT v2, in VT v3, in ST size) pure nothrow
        {
            lines = [
                LineT(v1, v2, v3, size),
                LineT(v2, v3, v1, size),
                LineT(v3, v1, v2, size)];

            const mat = Matrix!(PosT,3,3)(v1.pos.x, v1.pos.y, v1.pos.w,
                                         v2.pos.x, v2.pos.y, v2.pos.w,
                                         v3.pos.x, v3.pos.y, v3.pos.w);
            const d = mat.det;
            if(d <= 0)
            {
                degenerate = true;
                return;
            }
            else
            {
                degenerate = false;
            }
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
                uplane = PlaneT(invMat * vec3(tu1,tu2,tu3), size);
                vplane = PlaneT(invMat * vec3(tv1,tv2,tv3), size);
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

    static void drawTriangle(CtxT1,CtxT2,VertT)
        (auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
    {
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
            /*foreach(y;srcMask.y0..srcMask.y1)
            {
                outContext.surface[y][srcMask.spans[y].x0] = ColorGreen;
                outContext.surface[y][srcMask.spans[y].x1 - 1] = ColorBlue;
            }*/
        }
        else
        {
            const minX = clipRect.x;
            const maxX = clipRect.x + clipRect.w;
            const minY = clipRect.y;
            const maxY = clipRect.y + clipRect.h;
        }
        /*outContext.surface[minY][minX] = ColorRed;
        outContext.surface[maxY - 1][maxX - 1] = ColorRed;
        outContext.surface[minY][maxX - 1] = ColorRed;
        outContext.surface[maxY - 1][minX] = ColorRed;*/
        if(minX >= maxX || minY >= maxY)
        {
            //debugOut("invalid minmax");
            return;
        }

        immutable pack = PackT(pverts[0], pverts[1], pverts[2], size);
        if(pack.degenerate)
        {
            //debugOut("degenerate");
            return;
        }

        struct Span
        {
            int x0, x1;
        }
        //version(LDC) pragma(LDC_never_inline);
        //auto spans = alignPointer!Span(alloca(size.h * Span.sizeof + Span.alignof))[0..size.h];
        Span[4096] spansRaw; //TODO: LDC crahes when used memory from alloca with optimization enabled
        auto spans = spansRaw[0..size.h];

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
                        if(++count > 2)
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
                    /*outContext.surface[y0][x0] = ColorRed;
                    outContext.surface[y1-1][x0] = ColorRed;
                    outContext.surface[y0][x1-1] = ColorRed;
                    outContext.surface[y1-1][x1-1] = ColorRed;*/
                    return false;
                }
                /*outContext.surface[y0][x0] = ColorGreen;
                outContext.surface[y1-1][x0] = ColorGreen;
                outContext.surface[y0][x1-1] = ColorGreen;
                outContext.surface[y1-1][x1-1] = ColorGreen;*/

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
            //debugOut("notfound");
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
                spans[pt.curry].x0 = clamp(x0, leftBound, rightBound);
                spans[pt.curry].x1 = clamp(x1, leftBound, rightBound);
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
                alias TexT = Unqual!(typeof(span.u));
                struct Context
                {
                    TexT u;
                    TexT v;
                    TexT dux;
                    TexT dvx;
                }
                Context ctx = {u: span.u, v: span.v, dux: span.dux, dvx: span.dvx};
                static if(FixedLen)
                {
                    extContext.texture.getLine!AffineLength(ctx,line[x1..x2]);
                }
                else
                {
                    foreach(x;x1..x2)
                    {
                        extContext.texture.getLine!1(ctx,line[x..x+1]);
                        ctx.u += ctx.dux;
                        ctx.v += ctx.dvx;
                    }
                }
            }
        }

        const sy = startPoint.curry;
        const bounds = fillLine(startPoint);
        const y1 = search!true(bounds, sy);
        const y0 = search!false(bounds, sy) + 1;

        static if(HasTextures)
        {
            const sx = spans[y0].x0;
            auto span = SpanT(pack, sx, y0);

            auto line = outContext.surface[y0];
            foreach(y;y0..y1)
            {
                const x0 = spans[y].x0;
                const x1 = spans[y].x1;
                span.incX(x0 - sx);
                int x = x0;
                while(true)
                {
                    const nx = (x + AffineLength);
                    if(nx < x1)
                    {
                        span.incX(AffineLength);
                        drawSpan!true(y, x, nx, span, line);
                    }
                    else
                    {
                        const rem = (x1 - x);
                        span.incX(rem);
                        drawSpan!false(y, x, x1, span, line);
                        break;
                    }
                    x = nx;
                }
                span.incY();
                ++line;
            }
        }

        static if(WriteMask)
        {
            void writeMask(bool Empty)()
            {
                static int i = 0;
                //++i;
                static immutable colors = [ColorRed,ColorGreen,ColorBlue];
                int mskMinX = maxX;
                int mskMaxX = minX;
                foreach(y;y0..y1)
                {
                    const x0 = spans[y].x0;
                    const x1 = spans[y].x1;
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

                    /*if(dstMask.spans[y].x1 > dstMask.spans[y].x0)
                    {
                        outContext.surface[y][dstMask.spans[y].x0..dstMask.spans[y].x1] = colors[i % 3];
                    }*/

                    /*if(x1 > x0)
                    {
                        outContext.surface[y][x0..x1] = colors[i % 3];
                    }*/

                    mskMinX = min(mskMinX, x0);
                    mskMaxX = max(mskMaxX, x1);
                }
                static if(Empty)
                {
                    dstMask.y0 = y0;
                    dstMask.y1 = y1;
                    dstMask.x0 = mskMinX;
                    dstMask.x1 = mskMaxX;
                }
                else
                {
                    dstMask.x0 = min(mskMinX, dstMask.x0);
                    dstMask.x1 = max(mskMaxX, dstMask.x1);
                    dstMask.y0 = min(y0, dstMask.y0);
                    dstMask.y1 = max(y1, dstMask.y1);
                }
                //debugOut("----");
                //debugOut(Empty);
                //debugOut(dstMask.isEmpty);
            }

            if(dstMask.isEmpty) writeMask!true();
            else                writeMask!false();
        }
        //outContext.surface[sy][startPoint.currx] = ColorGreen;
        //end
    }

}