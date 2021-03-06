﻿module game.renderer.rasterizerhp3;

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

struct RasterizerHP3(BitmapT,TextureT,DepthT = void)
{
@nogc:
private:
    BitmapT mBitmap;
    TextureT mTexture;
    enum HasDepth = !is(DepthT : void);
    static if(HasDepth)
    {
        DepthT mDepthMap;
    }
    Rect mClipRect;

    enum MinTileWidth  = 8;
    enum MinTileHeight = 8;

    struct Line(PosT,bool Affine)
    {
    @nogc:
        immutable PosT dx, dy, c;

        this(VT)(in VT v1, in VT v2, in VT v3, in PosT baryInvDenom) pure nothrow
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            const w = Affine ? cast(PosT)1 : cast(PosT)v3.pos.w;
            dx = (x2 - x1) * baryInvDenom / w;
            dy = (y2 - y1) * baryInvDenom / w;
            const inc = (dy < 0 || (dy == 0 && dx > 0)) ? cast(PosT)1 / cast(PosT)16 : cast(PosT)0;
            c = (dy * x1 - dx * y1) + inc * baryInvDenom / w;
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
                LineT(v1, v2, v3, invDenom),
                LineT(v2, v3, v1, invDenom),
                LineT(v3, v1, v2, invDenom)];

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

        void getBarycentric(T)(int x, int y, T[] ret) const pure nothrow
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
        }
    }

    struct Tile(int TileWidth, int TileHeight, PosT,PackT)
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
    }

    struct Point(PosT,PackT,bool Affine)
    {
        enum NumLines = 3;
        int currx = void;
        int curry = void;
        PosT[NumLines] cx = void;
        PosT[NumLines] dx = void;
        PosT[NumLines] dy = void;
        this(PackT)(in PackT p, int x, int y) pure nothrow
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

        void incX(string sign)() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                mixin("cx[i] "~sign~"= dx[i];");
            }
            mixin("currx"~sign~"= 1;");
        }

        void incY() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cx[i] += dy[i];
            }
            curry += 1;
        }

        bool check() const pure nothrow
        {
            return cx[0] > 0 && cx[1] > 0 && cx[2] > 0;
        }
    }

    struct Spans(int Height,PosT,ColT,DpthT,TextT)
    {
        enum HasColor   = !is(ColT : void);
        enum HasDepth   = !is(DpthT : void);
        enum HasTexture = !is(TextT : void);
        int[Height] x0 = void;
        int[Height] x1 = void;
        static if(HasColor)
        {
            ColT[Height] col0 = void;
            ColT[Height] col1 = void;
        }
        static if(HasTexture)
        {
            TextT[2] uv00 = void;
            TextT[2] uv10 = void;
            TextT[2] uv01 = void;
            TextT[2] uv11 = void;
            //immutable TextT[2] duvx;
            //immutable TextT[2] duvy;
        }
        static if(HasDepth)
        {
            DpthT[Height] w0 = void;
            DpthT[Height] w1 = void;
        }
        /*this(PackT)(in ref PackT pack) pure nothrow
        {
            static if(HasTexture)
            {
                duvx = [-pack.uplane.ac,-pack.vplane.ac];
                duvy = [-pack.uplane.bc,-pack.vplane.bc];
            }
        }*/

        /*void setXY(PackT)(in ref PackT pack, int x, int y) pure nothrow
        {
            static if(HasTexture)
            {
                pack.
            }
        }

        void incX(int val) pure nothrow
        {
            static if(HasColor)
            {
                col0 = col1;
            }
            static if(HasTexture)
            {
                uv00 = uv10;
                uv01 = uv11;
            }
        }*/
    }
public:
    this(BitmapT b)
    in
    {
        assert(b !is null);
        assert(0 == (b.width  % MinTileWidth));
        assert(0 == (b.height % MinTileHeight));
        static if(HasDepth)
        {
            assert(mDepthMap !is null);
        }
    }
    body
    {
        mBitmap = b;
        mClipRect = Rect(0, 0, mBitmap.width, mBitmap.height);
    }

    static if(HasDepth)
    {
        this(BitmapT b, DepthT d)
        in
        {
            assert(d ! is null);
            assert(b.width  == d.width);
            assert(b.height == d.height);
        }
        body
        {
            mDepthMap = d;
            this(b);
        }
    }

    @property auto texture()       inout pure nothrow { return mTexture; }
    @property void texture(TextureT tex) pure nothrow { mTexture = tex; }

    @property void clipRect(in Rect rc) pure nothrow
    {
        const srcLeft   = rc.x;
        const srcTop    = rc.y;
        const srcRight  = rc.x + rc.w;
        const srcBottom = rc.y + rc.h;
        const dstLeft   = max(0, srcLeft);
        const dstTop    = max(0, srcTop);
        const dstRight  = min(srcRight,  mBitmap.width);
        const dstBottom = min(srcBottom, mBitmap.height);
        mClipRect = Rect(dstLeft, dstTop, dstRight - dstLeft, dstBottom - dstTop);
    }

    void drawIndexedTriangle(bool HasTextures = false, bool HasColor = true,VertT,IndT)(in VertT[] verts, in IndT[3] indices) pure nothrow if(isIntegral!IndT)
    {
        const c = (verts[1].pos.xyz - verts[0].pos.xyz).cross(verts[2].pos.xyz - verts[0].pos.xyz);
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

        if(affine) drawTriangle!(HasTextures, HasColor,true)(pverts);
        else       drawTriangle!(HasTextures, HasColor,false)(pverts);
    }
    @nogc private void drawTriangle(bool HasTextures, bool HasColor,bool Affine,VertT)(in VertT[3] pverts) pure nothrow
    {
        static assert(HasTextures != HasColor);
        //alias PosT = FixedPoint!(16,16,int);
        alias PosT = Unqual!(typeof(VertT.pos.x));
        static if(HasColor)
        {
            alias ColT = Unqual!(typeof(VertT.color));
            immutable ColT[3] vcols = [pverts[0].color,pverts[1].color,pverts[2].color];
            auto calcColor(T)(in T[] bary) pure nothrow
            {
                assert(bary.length == vcols.length);
                return vcols[0] * bary[0] + vcols[1] * bary[1] + vcols[2] * bary[2];
            }
        }
        else
        {
            alias ColT = void;
        }

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
        alias TileT   = Tile!(MinTileWidth,MinTileHeight,PosT,PackT);
        alias PointT  = Point!(PosT,PackT,Affine);
        alias SpansT  = Spans!(MinTileHeight,PosT,ColT,void,TextT);

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        minX = max(mClipRect.x, minX);
        maxX = min(mClipRect.x + mClipRect.w, maxX);
        minY = max(mClipRect.y, minY);
        maxY = min(mClipRect.y + mClipRect.h, maxY);
        const minTX = (minX / MinTileWidth) * MinTileWidth;
        const maxTX = (1 + (maxX - 1) / MinTileWidth) * MinTileWidth;
        const upperVert = (pverts[0].pos.y < pverts[1].pos.y ?
                          (pverts[0].pos.y < pverts[2].pos.y ? pverts[0] : pverts[2]) :
                          (pverts[1].pos.y < pverts[2].pos.y ? pverts[1] : pverts[2]));
        const lowerVert = (pverts[0].pos.y > pverts[1].pos.y ?
                          (pverts[0].pos.y > pverts[2].pos.y ? pverts[0] : pverts[2]) :
                          (pverts[1].pos.y > pverts[2].pos.y ? pverts[1] : pverts[2]));

        immutable pack = PackT(pverts[0], pverts[1], pverts[2]);

        static if(HasTextures)
        {
            immutable tw = mTexture.width - 1;
            immutable th = mTexture.height - 1;
            const tview = mTexture.view();
        }

        @nogc void drawSpans(bool Fill,LineT,SpansT)(auto ref LineT line, in auto ref SpansT spans, int x0, int y0, int x1, int y1) /*pure*/ nothrow
        {
            static if(HasTextures)
            {
                alias TextT = Unqual!(typeof(spans.uv00[0]));
                TextT[2] uvs = spans.uv00;
                TextT[2] uv  = spans.uv00;
                TextT wdt = x1 - x0;
                TextT hgt = y1 - y0;
                const dux = (spans.uv10[0] - spans.uv00[0]) / wdt;
                const dvx = (spans.uv10[1] - spans.uv00[1]) / wdt;
                const duy = (spans.uv01[0] - spans.uv00[0]) / hgt;
                const dvy = (spans.uv01[1] - spans.uv00[1]) / hgt;
                const oldX0 = x0;
            }
            foreach(y;y0..y1)
            {
                const my = y % MinTileHeight;
                static if(!Fill)
                {
                    static if(HasTextures)
                    {
                        const TextT dx = spans.x0[my] - oldX0;
                        uv[0] += (dux * dx);
                        uv[1] += (dvx * dx);
                    }
                    x0 = spans.x0[my];
                    x1 = spans.x1[my];
                }
                static if(HasColor)
                {
                    ditherColorLine(line,x0,x1,my,spans.col0[my],spans.col1[my]);
                }
                static if(HasTextures)
                {
                    foreach(x;x0..x1)
                    {
                        const tx = cast(int)(uv[0] * tw) & tw;
                        const ty = cast(int)(uv[1] * th) & th;
                        line[x] = tview[ty][tx];
                        uv[0] += dux;
                        uv[1] += dvx;
                    }
                    uvs[0] += duy;
                    uvs[1] += dvy;
                    uv = uvs;
                }
                ++line;
            }
        }

        @nogc void fillTile(T)(auto ref T spans, int x0, int y0, int x1, int y1)
        {
            assert(x0 >= 0,   debugConv(x0));
            assert(y0 >= 0,   debugConv(y0));
            assert(x1 > minX, debugConv(x1));
            assert(x0 < maxX, debugConv(x0));
            assert(y1 > minY, debugConv(y1));
            assert(y0 < maxY, debugConv(y0));
            drawSpans!true(mBitmap[y0], spans, x0, y0, x1, y1);
        }
        @nogc void drawTile(T)(auto ref T spans, int x0, int y0, int x1, int y1)
        {
            assert(x0 >= 0,   debugConv(x0));
            assert(y0 >= 0,   debugConv(y0));
            assert(x1 > minX, debugConv(x1));
            assert(x0 < maxX, debugConv(x0));
            assert(y1 > minY, debugConv(y1));
            assert(y0 < maxY, debugConv(y0));
            int ys = y1;
            outer1: foreach(y;y0..y1)
            {
                auto pt = PointT(&pack, x0, y);
                foreach(x;x0..x1)
                {
                    if(pt.check())
                    {
                        ys = y;
                        break outer1;
                    }
                    pt.incX!"+"();
                }
            }
            int ye = y1;
            foreach(y;ys..y1)
            {
                auto pt = PointT(&pack, x0, y);
                int xs = x1;
                foreach(x;x0..x1)//find first valid pixel in line
                {
                    if(pt.check())
                    {
                        xs = x;
                        break;
                    }
                    pt.incX!"+"();
                }
                int xe = x1;
                foreach(x;xs..x1)//find last valid
                {
                    if(!pt.check())
                    {
                        xe = x;
                        break;
                    }
                    pt.incX!"+"();
                }
                if(xe > xs)
                {
                    const my = y % MinTileHeight;
                    spans.x0[my] = xs;
                    spans.x1[my] = xe;
                }
                else
                {
                    ye = y;
                    break;
                }
            }
            if(ys >= ye) return;

            const my0 = ys % MinTileHeight;
            const my1 = (ye - 1) % MinTileHeight;
            static if(HasColor)
            {
                const hgt = ye - ys;
                PosT[3] bary = void;
                pack.getBarycentric(spans.x0[my0]    , ys    , bary);
                spans.col0[my0] = calcColor(bary);
                pack.getBarycentric(spans.x1[my0] - 1, ys    , bary);
                spans.col1[my0] = calcColor(bary);
                pack.getBarycentric(spans.x0[my1]    , ye - 1, bary);
                spans.col0[my1] = calcColor(bary);
                pack.getBarycentric(spans.x1[my1] - 1, ye - 1, bary);
                spans.col1[my1] = calcColor(bary);
                ColT.interpolateLine(hgt, spans.col0[my0..my1 + 1], spans.col0[my0], spans.col0[my1]);
                ColT.interpolateLine(hgt, spans.col1[my0..my1 + 1], spans.col1[my0], spans.col1[my1]);
            }
            static if(HasTextures)
            {
                pack.getUV(x0, ys, spans.uv00);
                pack.getUV(x1, ys, spans.uv10);
                pack.getUV(x0, ye, spans.uv01);
                //pack.getUV(x1, ye, spans.uv11);
            }

            drawSpans!false(mBitmap[ys], spans, x0, ys, x1, ye);
        }

        int ux, uy;
        if(upperVert.pos.y >= minY)
        {
            ux = cast(int)upperVert.pos.x;
            uy = cast(int)upperVert.pos.y;
        }
        else
        {
            const dx = lowerVert.pos.x - upperVert.pos.x;
            const dy = lowerVert.pos.y - upperVert.pos.y;
            ux = clamp(cast(int)(upperVert.pos.x + dx * (minY - upperVert.pos.y) / dy), minX, maxX - 1);
            uy = minY;
        }
        const tx = ux / MinTileWidth;
        const ty = uy / MinTileHeight;
        TileT currentTile    = TileT(&pack, tx * MinTileWidth, ty * MinTileHeight);
        TileT savedRightTile;

        int y0 = uy;
        int y1 = currentTile.curry + MinTileHeight;
        outer: while(true)
        {
            auto none(in uint val) pure nothrow
            {
                return 0x0 == (val & 0b001_001_001_001) ||
                       0x0 == (val & 0b010_010_010_010) ||
                       0x0 == (val & 0b100_100_100_100);
            }
            auto all(in uint val) pure nothrow
            {
                return val == 0b111_111_111_111;
            }
            uint tileMask = (currentTile.check() << 6);
            savedRightTile = currentTile;
            int startX     = currentTile.currx;
            int startFillX =  9000;
            int endFillX   = -9000;
            int endX       = currentTile.currx + MinTileWidth;

            //move left
            while(currentTile.currx > (minX - MinTileWidth))
            {
                currentTile.incX!("-")();
                tileMask >>= 6;
                tileMask |= (currentTile.check() << 6);

                if(none(tileMask))
                {
                    break;
                }

                if(all(tileMask))
                {
                    startFillX = currentTile.currx;
                    endFillX   = currentTile.currx + MinTileWidth;
                }
            }
            startX = currentTile.currx + MinTileWidth;

            //move right
            tileMask = (savedRightTile.check() << 6);
            while(savedRightTile.currx < (maxX + MinTileWidth))
            {
                savedRightTile.incX!("+")();
                tileMask >>= 6;
                tileMask |= (savedRightTile.check() << 6);
                if(none(tileMask))
                {
                    break;
                }

                if(all(tileMask))
                {
                    startFillX = min(startFillX, savedRightTile.currx - MinTileWidth);
                    endFillX   = savedRightTile.currx;
                }
            }
            startFillX = max(startFillX, startX);
            endFillX   = min(endFillX,   endX);
            endX = savedRightTile.currx - MinTileWidth;

            assert(startX >= 0,                    debugConv(startX));
            assert(startX > (minX - MinTileWidth), debugConv(startX));
            assert(endX   < (maxX + MinTileWidth), debugConv(endX));
            assert(endX   >= endFillX);

            SpansT spans = void;
            if(endFillX > startFillX)
            {
                for(auto x = startX; x < startFillX; x += MinTileWidth)
                {
                    const x0 = x;
                    const x1 = x0 + MinTileWidth;
                    const sx = clamp(ux, x0, x1 - 1);
                    drawTile(spans, x0, y0, x1, y1);
                }
                //spans.setX(startFillX);
                PosT[3] bary = void;
                static if(HasColor)
                {
                    {
                        pack.getBarycentric(startFillX, y0    , bary);
                        const col0 = calcColor(bary);
                        pack.getBarycentric(startFillX, y1 - 1, bary);
                        const col1 = calcColor(bary);
                        ColT.interpolateLine!MinTileHeight(spans.col1[0..$], col0, col1);
                    }
                }
                static if(HasTextures)
                {
                    pack.getUV(startFillX, y0, spans.uv10);
                    pack.getUV(startFillX, y1, spans.uv11);
                }
                for(auto x = startFillX; x < endFillX; x += MinTileWidth)
                {
                    static if(HasColor)
                    {
                        spans.col0 = spans.col1;
                        pack.getBarycentric(x + MinTileWidth, y0    , bary);
                        const col0 = calcColor(bary);
                        pack.getBarycentric(x + MinTileWidth, y1 - 1, bary);
                        const col1 = calcColor(bary);
                        ColT.interpolateLine!MinTileHeight(spans.col1[0..$], col0, col1);
                    }
                    static if(HasTextures)
                    {
                        spans.uv00 = spans.uv10;
                        spans.uv01 = spans.uv11;
                        pack.getUV(x + MinTileWidth, y0, spans.uv10);
                        pack.getUV(x + MinTileWidth, y1, spans.uv11);
                    }
                    const x0 = x;
                    const x1 = x0 + MinTileWidth;
                    fillTile(spans, x0, y0, x1, y1);
                }
                for(auto x = endFillX; x < endX; x += MinTileWidth)
                {
                    const x0 = x;
                    const x1 = x0 + MinTileWidth;
                    const sx = clamp(ux, x0, x1 - 1);
                    drawTile(spans, x0, y0, x1, y1);
                }
            }
            else
            {
                for(auto x = startX; x < endX; x += MinTileWidth)
                {
                    const x0 = x;
                    const x1 = x0 + MinTileWidth;
                    const sx = clamp(ux, x0, x1 - 1);
                    drawTile(spans, x0, y0, x1, y1);
                }
            }

            if(y1 >= maxY) break;

            currentTile = TileT(&pack, startX, y1);
            tileMask = (currentTile.check() << 6);
            while(currentTile.currx < endX)
            {
                currentTile.incX!("+")();
                tileMask >>= 6;
                tileMask |= (currentTile.check() << 6);
                if(!none(tileMask))
                {
                    y0 = y1;
                    y1 = y0 + MinTileHeight;
                    continue outer;
                }
            }

            break;
        }
        //end
    }
}