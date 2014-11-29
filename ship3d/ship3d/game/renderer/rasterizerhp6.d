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

struct RasterizerHP6
{
    void drawIndexedTriangle(bool HasTextures,CtxT1,CtxT2,VertT,IndT)
        (auto ref CtxT1 outputContext, auto ref CtxT2 extContext, in VertT[] verts, in IndT[] indices) if(isIntegral!IndT)
    {
        assert(indices.length == 3);
        const c = (verts[indices[1]].pos.xyz - verts[indices[0]].pos.xyz).cross(verts[indices[2]].pos.xyz - verts[indices[0]].pos.xyz);
        if(c.z <= 0)
        {
            return;
        }
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;

        const e1xdiff = pverts[0].pos.x - pverts[2].pos.x;
        const e2xdiff = pverts[0].pos.x - pverts[1].pos.x;

        const e1ydiff = pverts[0].pos.y - pverts[2].pos.y;
        const e2ydiff = pverts[0].pos.y - pverts[1].pos.y;

        const cxdiff = ((e1xdiff / e1ydiff) * e2ydiff) - e2xdiff;
        const affine = false;//(abs(cxdiff) > AffineLength * 25);

        if(affine) drawTriangle!(HasTextures, true)(outputContext,extContext, pverts);
        else       drawTriangle!(HasTextures, false)(outputContext,extContext, pverts);
    }
}

private:
enum AffineLength = 32;
struct Line(PosT,bool Affine)
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
        dy = (y2 * w1 - y1 * w2) / size.w;
        dx = (x2 * w1 - x1 * w2) / size.h;
        const inc = (dy < 0 || (dy == 0 && dx > 0)) ? cast(PosT)1 / cast(PosT)8 : cast(PosT)0;//TODO: fix
        c  = (x1 * y2 - x2 * y1) - dx * (size.h / 2) + dy * (size.w / 2) - inc * (dy + dx);
    }

    auto val(int x, int y) const pure nothrow
    {
        return c + dx * y - dy * x;
    }
}

struct Plane(PosT)
{
@nogc:
    immutable PosT ac;
    immutable PosT bc;
    immutable PosT dc;
    this(V)(in V v1, in V v2, in V v3) pure nothrow
    {
        const v12 = v2 - v1;
        const v13 = v3 - v1;

        const norm = cross(v12,v13);
        //ax + by + cz = d
        ac = norm.x / norm.z;
        bc = norm.y / norm.z;
        dc = ac * v1.x + bc * v1.y + v1.z;
    }

    auto get(int x, int y) const pure nothrow
    {
        //z = d/c - (a/c)x - (b/c)y)
        return dc - ac * x - bc * y;
    }
}

struct LinesPack(PosT,TextT,LineT,bool Affine)
{
@nogc:
    enum HasTexture = !is(TextT : void);
    alias vec3 = Vector!(PosT,3);
    alias PlaneT = Plane!(PosT);
    enum NumLines = 3;
    immutable LineT[NumLines] lines;

    static if(!Affine)
    {
        immutable PlaneT wplane;
    }
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

        const x1 = (v1.pos.x / v1.pos.w) * size.w + size.w / 2;
        const x2 = (v2.pos.x / v2.pos.w) * size.w + size.w / 2;
        const x3 = (v3.pos.x / v3.pos.w) * size.w + size.w / 2;
        const y1 = (v1.pos.y / v1.pos.w) * size.h + size.h / 2;
        const y2 = (v2.pos.y / v2.pos.w) * size.h + size.h / 2;
        const y3 = (v3.pos.y / v3.pos.w) * size.h + size.h / 2;
        const w1 = v1.pos.w;
        const w2 = v2.pos.w;
        const w3 = v3.pos.w;

        static if(!Affine)
        {
            wplane = PlaneT(vec3(cast(PosT)x1, cast(PosT)y1, cast(PosT)1 / w1),
                            vec3(cast(PosT)x2, cast(PosT)y2, cast(PosT)1 / w2),
                            vec3(cast(PosT)x3, cast(PosT)y3, cast(PosT)1 / w3));
        }
        static if(HasTexture)
        {
            const TextT tu1 = v1.tpos.u;
            const TextT tu2 = v2.tpos.u;
            const TextT tu3 = v3.tpos.u;
            const TextT tv1 = v1.tpos.v;
            const TextT tv2 = v2.tpos.v;
            const TextT tv3 = v3.tpos.v;
            static if(Affine)
            {
                uplane = PlaneTtex(vec3tex(cast(TextT)x1, cast(TextT)y1, tu1),
                                   vec3tex(cast(TextT)x2, cast(TextT)y2, tu2),
                                   vec3tex(cast(TextT)x3, cast(TextT)y3, tu3));
                vplane = PlaneTtex(vec3tex(cast(TextT)x1, cast(TextT)y1, tv1),
                                   vec3tex(cast(TextT)x2, cast(TextT)y2, tv2),
                                   vec3tex(cast(TextT)x3, cast(TextT)y3, tv3));
            }
            else
            {
                uplane = PlaneTtex(vec3tex(cast(TextT)x1, cast(TextT)y1, tu1 / cast(TextT)w1),
                                   vec3tex(cast(TextT)x2, cast(TextT)y2, tu2 / cast(TextT)w2),
                                   vec3tex(cast(TextT)x3, cast(TextT)y3, tu3 / cast(TextT)w3));
                vplane = PlaneTtex(vec3tex(cast(TextT)x1, cast(TextT)y1, tv1 / cast(TextT)w1),
                                   vec3tex(cast(TextT)x2, cast(TextT)y2, tv2 / cast(TextT)w2),
                                   vec3tex(cast(TextT)x3, cast(TextT)y3, tv3 / cast(TextT)w3));
            }
        }
    }
}

struct Point(PosT,PackT,bool Affine)
{
    enum NumLines = 3;
    int currx = void;
    int curry = void;
    PosT[NumLines] cx = void;
    PosT[NumLines] dx = void;
    PosT[NumLines] dy = void;
    this(PackT)(in ref PackT p, int x, int y) pure nothrow
    {
        foreach(i;TupleRange!(0,NumLines))
        {
            const val = p.lines[i].val(x, y);
            cx[i] = val;
            dx[i] = -p.lines[i].dy;
            dy[i] =  p.lines[i].dx;
        }
        currx = x;
        curry = y;
    }

    void incX(int val) pure nothrow
    {
        foreach(i;TupleRange!(0,NumLines))
        {
            cx[i] += dx[i] * val;
        }
        currx += val;
    }

    void incY(int val) pure nothrow
    {
        foreach(i;TupleRange!(0,NumLines))
        {
            cx[i] += dy[i] * val;
        }
        curry += val;
    }

    bool check() const pure nothrow
    {
        return cx[0] > 0 && cx[1] > 0 && cx[2] > 0;
    }

    uint vals() const pure nothrow
    {
        return (cast(uint)(cx[0] > 0) << 0) |
               (cast(uint)(cx[1] > 0) << 1) |
               (cast(uint)(cx[2] > 0) << 2);
    }
}

struct Span(PosT,bool Affine)
{
    static if(!Affine)
    {
        PosT wStart = void, wCurr = void;
        immutable PosT dwx, dwy;
    }
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
        suStart =  pack.uplane.get(x, y);
        suCurr  =  suStart;
        dsux    = -pack.uplane.ac;
        dsuy    = -pack.uplane.bc;

        svStart =  pack.vplane.get(x, y);
        svCurr  =  svStart;
        dsvx    = -pack.vplane.ac;
        dsvy    = -pack.vplane.bc;
        static if(!Affine)
        {
            wStart =  pack.wplane.get(x, y);
            wCurr  =  wStart;
            dwx    = -pack.wplane.ac;
            dwy    = -pack.wplane.bc;
        }
        else
        {
            dux = dsux;
            dvx = dsvx;
        }
    }

    void incX(int dx)
    {
        suCurr += dsux * dx;
        svCurr += dsvx * dx;
        static if(Affine)
        {
            u = u1;
            v = v1;
            u1 = suCurr;
            v1 = svCurr;
        }
        else
        {
            u = u1;
            v = v1;
            wCurr += dwx * dx;
            u1 = suCurr / wCurr;
            v1 = svCurr / wCurr;
            dux = (u1 - u) / dx;
            dvx = (v1 - v) / dx;
        }
    }

    void incY()
    {
        static if(!Affine)
        {
            wStart += dwy;
            wCurr  = wStart;
        }
        suStart += dsuy;
        suCurr  = suStart;
        svStart += dsvy;
        svCurr  = svStart;
    }
}

void drawTriangle(bool HasTextures,bool Affine,CtxT1,CtxT2,VertT)
    (auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
{
    static assert(HasTextures);
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
    alias LineT   = Line!(PosT,Affine);
    alias PackT   = LinesPack!(PosT,TextT,LineT,Affine);
    alias PointT  = Point!(PosT,PackT,Affine);
    alias SpanT   = Span!(PosT,Affine);

    const clipRect = outContext.clipRect;
    const size = outContext.size;

    const minX = clipRect.x;
    const maxX = clipRect.x + clipRect.w;
    const minY = clipRect.y;
    const maxY = clipRect.y + clipRect.h;

    immutable pack = PackT(pverts[0], pverts[1], pverts[2], size);

    //find first valid point

    bool findStart(int x, int y, ref PointT start)
    {
        enum W = 5;
        enum H = 5;
        x -= W / 2;
        y -= H / 2;

        foreach(i; TupleRange!(0,H))
        {
            const sy = y + i;
            auto pt = PointT(pack, x, sy);
            int count = 0;
            foreach(j; TupleRange!(0,W))
            {
                const sx = x + j;
                if(sx >= minX && sx < maxX &&
                   sy >= minY && sy < maxY &&
                   pt.check())
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
            //const x = cast(int)v.pos.x;
            //const y = cast(int)v.pos.y;
            if(findStart(x, y, startPoint))
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
            const cx = x0 + (x1 - x0) / 2;
            const cy = y0 + (y1 - y0) / 2;
            if((x1 - x0) <= 4 &&
               (y1 - y0) <= 4)
            {
                return findStart(cx, cy, startPoint);
            }
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

    struct Span
    {
        int x0, x1;
    }

    //version(LDC) pragma(LDC_never_inline);
    //auto spans = alignPointer!Span(alloca(size.h * Span.sizeof + Span.alignof))[0..size.h];
    Span[4096] spansRaw; //TODO: LDC crahes when used memory from alloca with optimization enabled
    auto spans = spansRaw[0..size.h];

    auto fillLine(in ref PointT pt)
    {
        enum Step = 64;
        const leftBound  = minX;
        const rightBound = maxX;
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
            spans[pt.curry].x0 = x0;
            spans[pt.curry].x1 = x1;
            return vec2i(x0, x1);
        }
        assert(false);
    }

    bool findPoint(T)(int y, in T bounds, out int x)
    {
        //debugOut("find point");
        const x0 = max(bounds.x - 4, minX);
        const x1 = min(bounds.y + 4, maxX);
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
        enum Step = 64;
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

    const sx = spans[y0].x0;
    auto span = SpanT(pack, sx, y0);

    auto line = outContext.surface[y0];
    foreach(y;y0..y1)
    {
        const x0 = spans[y].x0;
        const x1 = spans[y].x1;
        //outContext.surface[y][x0..x1] = ColorRed;
        span.incX(x0 - sx);
        static if(Affine)
        {
            int x = x0;
            const xend = (x1 - AffineLength);
            for(; x < xend; x += AffineLength)
            {
                span.incX(AffineLength);
                drawSpan!true(y, x, x + AffineLength, span, line);
            }
            span.incX(1);
            drawSpan!false(y, x, x1, span, line);
        }
        else
        {
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
        }
        span.incY();
        ++line;
    }
    //outContext.surface[sy][startPoint.currx] = ColorGreen;
    //end
}