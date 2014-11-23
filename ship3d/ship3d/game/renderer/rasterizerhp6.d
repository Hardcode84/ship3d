module game.renderer.rasterizerhp6;

import std.traits;
import std.algorithm;
import std.array;
import std.string;
import std.functional;
import std.range;

import gamelib.util;
import gamelib.math;
import gamelib.graphics.graph;

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
        const reverseSpans = (cxdiff < 0);
        const affine = false;//(abs(cxdiff) > AffineLength * 25);

        if(affine) drawTriangle!(HasTextures, true)(outputContext,extContext, pverts);
        else       drawTriangle!(HasTextures, false)(outputContext,extContext, pverts);
    }
}

private:
struct Line(PosT,bool Affine)
{
@nogc:
    immutable PosT dx, dy, c;

    this(VT)(in VT v1, in VT v2, in VT v3) pure nothrow
    {
        const x1 = v1.pos.x;
        const x2 = v2.pos.x;
        const y1 = v1.pos.y;
        const y2 = v2.pos.y;
        const w = Affine ? cast(PosT)1 : cast(PosT)v3.pos.w;
        dx = (x2 - x1) / w;
        dy = (y2 - y1) / w;
        c = (dy * x1 - dx * y1);
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
    this(VT)(in VT v1, in VT v2, in VT v3) pure nothrow
    {
        const invDenom = cast(PosT)(1 / ((v2.pos - v1.pos).xy.wedge((v3.pos - v1.pos).xy)));
        lines = [
            LineT(v1, v2, v3),
            LineT(v2, v3, v1),
            LineT(v3, v1, v2)];

        static if(!Affine)
        {
            wplane = PlaneT(vec3(cast(PosT)v1.pos.x, cast(PosT)v1.pos.y, cast(PosT)1 / v1.pos.w),
                            vec3(cast(PosT)v2.pos.x, cast(PosT)v2.pos.y, cast(PosT)1 / v2.pos.w),
                            vec3(cast(PosT)v3.pos.x, cast(PosT)v3.pos.y, cast(PosT)1 / v3.pos.w));
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
                uplane = PlaneTtex(vec3tex(cast(TextT)v1.pos.x, cast(TextT)v1.pos.y, tu1),
                                   vec3tex(cast(TextT)v2.pos.x, cast(TextT)v2.pos.y, tu2),
                                   vec3tex(cast(TextT)v3.pos.x, cast(TextT)v3.pos.y, tu3));
                vplane = PlaneTtex(vec3tex(cast(TextT)v1.pos.x, cast(TextT)v1.pos.y, tv1),
                                   vec3tex(cast(TextT)v2.pos.x, cast(TextT)v2.pos.y, tv2),
                                   vec3tex(cast(TextT)v3.pos.x, cast(TextT)v3.pos.y, tv3));
            }
            else
            {
                uplane = PlaneTtex(vec3tex(cast(TextT)v1.pos.x, cast(TextT)v1.pos.y, tu1 / cast(TextT)v1.pos.w),
                                   vec3tex(cast(TextT)v2.pos.x, cast(TextT)v2.pos.y, tu2 / cast(TextT)v2.pos.w),
                                   vec3tex(cast(TextT)v3.pos.x, cast(TextT)v3.pos.y, tu3 / cast(TextT)v3.pos.w));
                vplane = PlaneTtex(vec3tex(cast(TextT)v1.pos.x, cast(TextT)v1.pos.y, tv1 / cast(TextT)v1.pos.w),
                                   vec3tex(cast(TextT)v2.pos.x, cast(TextT)v2.pos.y, tv2 / cast(TextT)v2.pos.w),
                                   vec3tex(cast(TextT)v3.pos.x, cast(TextT)v3.pos.y, tv3 / cast(TextT)v3.pos.w));
            }
        }
    }

    /*void getBarycentric(T)(int x, int y, T[] ret) const pure nothrow
    in
    {
        assert(ret.length == NumLines);
    }
    out
    {
        //assert(almost_equal(cast(PosT)1, ret.sum, 1.0f/255.0f), debugConv(ret.sum));
    }
    body
    {
        static if(!Affine)
        {
            const currw = wplane.get(x,y);
        }
        foreach(i;TupleRange!(1,NumLines))
        {
            enum li = (i + 1) % NumLines;
            static if(Affine)
            {
                ret[i] = lines[li].val(x,y);
            }
            else
            {
                ret[i] = lines[li].val(x,y) / currw;
            }
        }
        ret[0] = cast(PosT)1 - ret[1] - ret[2];
    }
    void getUV(T)(int x, int y, T[] ret) const pure nothrow
    in
    {
        assert(ret.length == 2);
    }
    body
    {
        static if(Affine)
        {
            ret[0] = uplane.get(x,y);
            ret[1] = vplane.get(x,y);
        }
        else
        {
            const currw = wplane.get(x,y);
            ret[0] = uplane.get(x,y) / currw;
            ret[1] = vplane.get(x,y) / currw;
        }
    }*/
}

/*struct Tile(int TileWidth, int TileHeight, PosT,PackT)
{
    immutable(PackT)* pack;
    enum NumLines = 3;
    int currx = void;
    int curry = void;
    PosT[NumLines] cx0 = void, cx1 = void;

    this(in immutable(PackT)* p, int x, int y) pure nothrow
    {
        pack = p;
        setXY(x,y);
    }

    void setXY(int x, int y) pure nothrow
    {
        foreach(i;TupleRange!(0,NumLines))
        {
            const val = pack.lines[i].val(x, y);
            cx0[i] = val;
            cx1[i] = val + pack.lines[i].dx * TileHeight;
        }
        currx = x;
        curry = y;
    }

    void incX(string sign)() pure nothrow
    {
        foreach(i;TupleRange!(0,NumLines))
        {
            const dx = pack.lines[i].dy * -TileWidth;
            mixin("cx0[i] "~sign~"= dx;");
            mixin("cx1[i] "~sign~"= dx;");
        }
        mixin("currx"~sign~"= TileWidth;");
    }

    void incY() pure nothrow
    {
        foreach(i;TupleRange!(0,NumLines))
        {
            cx0[i] = cx1[i];
            cx1[i] += pack.lines[i].dx * TileHeight;
        }
        curry += TileHeight;
    }
    @property auto check() const pure nothrow
    {
        uint test(T)(in T val) pure nothrow
        {
            union u_t
            {
                static assert(T.sizeof == uint.sizeof);
                T v;
                uint i;
            }
            u_t u;
            u.v = val;
            return (~u.i) >> 31;
        }
        uint ret = 0;
        foreach(j;TupleRange!(0,2))
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                import std.conv;
                mixin("ret |= (test(cx"~text(j)~"[i]) << (i+"~text(NumLines * j)~"));");
            }
        }
        return ret;
    }
}*/

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

/*struct Spans(int Height,PosT,TextT)
{
    TextT[2] uv00 = void;
    TextT[2] uv10 = void;
    TextT[2] uv01 = void;
    TextT[2] uv11 = void;
}*/

struct Context(TextT)
{
    enum HasTextures = !is(TextT : void);
    int x = void;
    int y = void;
    static if(HasTextures)
    {
        TextT u = void;
        TextT v = void;
        TextT dux = void;
        TextT dvx = void;
        TextT duy = void;
        TextT dvy = void;
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
    //alias TileT   = Tile!(TileWidth,TileHeight,PosT,PackT);
    alias PointT  = Point!(PosT,PackT,Affine);
    //alias SpansT  = Spans!(TileHeight,PosT,TextT);
    alias CtxT    = Context!(TextT);

    int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
    int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y) + 1;

    int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
    int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x) + 1;

    const clipRect = outContext.clipRect;
    const size = outContext.size;
    /*minX = max(clipRect.x, minX);
    maxX = min(clipRect.x + clipRect.w, maxX);
    minY = max(clipRect.y, minY);
    maxY = min(clipRect.y + clipRect.h, maxY);*/
    minX = clipRect.x;
    maxX = clipRect.x + clipRect.w;
    minY = clipRect.y;
    maxY = clipRect.y + clipRect.h;

    immutable pack = PackT(pverts[0], pverts[1], pverts[2]);

    //find first valid point
    Vector!(int,2) start;
findStart: do
    {
        foreach(const ref v; pverts)
        {
            const w = v.pos.w;
            enum W = 3;
            enum H = 3;
            const x = cast(int)((v.pos.x / w) * size.w) + size.w / 2 - W / 2;
            const y = cast(int)((v.pos.y / w) * size.h) + size.h / 2 - H / 2;
            auto pt = PointT(pack, x, y);
            foreach(i; TupleRange!(0,H))
            {
                const sy = y + i;
                foreach(j; TupleRange(0,W))
                {
                    const sx = x + j;
                    if(sx >= minX && sx < maxX &&
                       sy >= minY && sy < maxY &&
                       pt.check())
                    {
                        start.x = sx;
                        start.y = sy;
                        break findStart;
                    }
                    static if(j != (W - 1))
                    {
                        pt.incX(0 == i % 2 ? 1 : -1);
                    }
                }
                static if(i != (H - 1))
                {
                    pt.incY(1);
                }
            }
        }
        //TODO: check edges
        //nothing found
        return;
    }
    while(false);

    auto fillLine(T)(in ref PointT pt, auto ref T line)
    {
        enum Step = 32;
        const leftBound  = minX;
        const rightBound = maxX;
        if(leftBound < rightBound)
        {
            int findLeft()
            {
                PointT newPt = pt;
                while(newPt.currx > (leftBound + Step))
                {
                    newPt.incX(-Step);
                    if(newPt.check())
                    {
                        const x0 = newPt.currx;
                        const x1 = x0 + Step;
                        line[x0..x1] = ColorRed;
                    }
                    else
                    {
                        const x1 = newPt.currx + Step;
                        foreach(i;0..Step)
                        {
                            newPt.incX(1);
                            if(newPt.check())
                            {
                                const x0 = newPt.currx;
                                line[x0..x1] = ColorBlue;
                                return x0;
                            }
                        }
                    }
                }
                const x1 = newPt.currx;
                const rem = x1 - leftBound;
                foreach(i;0..rem)
                {
                    newPt.incX(-1);
                    if(!newPt.check())
                    {
                        const x0 = newPt.currx + 1;
                        line[x0..x1] = ColorWhite;
                        return x0;
                    }
                }
                line[leftBound..x1] = ColorGreen;
                return leftBound;
            } //find left
            int findRight()
            {
                PointT newPt = pt;
                while(newPt.currx < (rightBound - Step))
                {
                    newPt.incX(Step);
                    if(newPt.check())
                    {
                        const x1 = newPt.currx;
                        const x0 = x1 - Step;
                        line[x0..x1] = ColorGreen;
                    }
                    else
                    {
                        const x0 = newPt.currx - Step;
                        foreach(i;0..Step)
                        {
                            newPt.incX(-1);
                            if(newPt.check())
                            {
                                const x1 = newPt.currx + 1;
                                line[x0..x1] = ColorGreen;
                                return x1;
                            }
                        }
                    }
                }
                const x0 = newPt.currx;
                const rem = rightBound - x0;
                foreach(i;0..rem)
                {
                    newPt.incX(1);
                    if(!newPt.check())
                    {
                        const x1 = newPt.currx;
                        line[x0..x1] = ColorWhite;
                        return x1;
                    }
                }
                line[x0..rightBound] = ColorRed;
                return rightBound;
            } //find right
            const x0 = findLeft();
            const x1 = findRight();
            return Vector!(int, 2)(x0, x1);
        }
        return Vector!(int, 2)(0, 0);
    }

    const startPoint = PointT(pack, start.x, start.y);

    //end
}