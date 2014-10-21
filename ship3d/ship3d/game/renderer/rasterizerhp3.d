module game.renderer.rasterizerhp3;

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

    struct LinesPack(PosT,LineT,bool Affine)
    {
    @nogc:
        alias vec3 = Vector!(PosT,3);
        alias PlaneT = Plane!(PosT);
        enum NumLines = 3;
        immutable LineT[NumLines] lines;

        static if(!Affine)
        {
            immutable PlaneT wplane;
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
                wplane = PlaneT(vec3(v1.pos.xy, cast(PosT)1 / v1.pos.w),
                                vec3(v2.pos.xy, cast(PosT)1 / v2.pos.w),
                                vec3(v3.pos.xy, cast(PosT)1 / v3.pos.w));
            }
        }

        void getBarycentric(int x, int y, PosT[] ret) const pure nothrow
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
                auto val = lines[li].val(x,y);
                static if(!Affine)
                {
                    val /= currw;
                }
                ret[i] = val;
            }
            ret[0] = cast(PosT)1 - ret[1] - ret[2];
        }
    }

    struct Tile(int TileWidth, int TileHeight, PosT,PackT,bool Affine)
    {
        immutable(PackT)* pack;
        enum NumLines = 3;
        int currx = void;
        int curry = void;
        PosT[NumLines] cx0 = void, cx1 = void;
        static if(!Affine)
        {
            PosT currw0 = void, currw1 = void;
        }

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
            static if(!Affine)
            {
                currw0 = pack.wplane.get(x,y);
                currw1 = currw0 - pack.wplane.bc * TileHeight;
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
            static if(!Affine)
            {
                const dw = pack.wplane.ac * -TileWidth;
                mixin("currw0 "~sign~"= dw;");
                mixin("currw1 "~sign~"= dw;");
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
            static if(!Affine)
            {
                currw0 = currw1;
                currw1 -= pack.wplane.bc * TileHeight;
            }
            curry += TileHeight;
        }
        @property auto check() const pure nothrow
        {
            uint ret = 0;
            foreach(j;TupleRange!(0,2))
            {
                foreach(i;TupleRange!(0,NumLines))
                {
                    import std.conv;
                    mixin("ret |= ((cx"~text(j)~"[i] > 0) << (i+"~text(NumLines * j)~"));");
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

    struct Spans(int Height,PosT,ColT,DpthT)
    {
        enum HasColor = !is(ColT : void);
        enum HasDepth = !is(DpthT : void);
        int[Height] x0 = void;
        int[Height] x1 = void;
        static if(HasColor)
        {
            ColT[Height] col0 = void;
            ColT[Height] col1 = void;
        }
        static if(HasDepth)
        {
            DpthT[Height] w0 = void;
            DpthT[Height] w1 = void;
        }

        void setX(int x) pure nothrow
        {
            x1[] = x;
        }

        void incX(int val) pure nothrow
        {
            static if(HasColor)
            {
                col0 = col1;
            }
            x0 = x1;
            foreach(i;TupleRange!(0,Height))
            {
                x1[i] += val;
            }
        }
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
        //alias PosTF = FixedPoint!(16,16,int);
        alias PosT = Unqual!(typeof(VertT.pos.x));
        static if(HasColor)
        {
            alias ColT = Unqual!(typeof(VertT.color));
            immutable ColT vcols[3] = [pverts[0].color,pverts[1].color,pverts[2].color];
            auto calcColor(T)(in T[] bary) pure nothrow
            in
            {
                assert(bary.length == vcols.length);
            }
            body
            {
                return vcols[0] * bary[0] + vcols[1] * bary[1] + vcols[2] * bary[2];
            }
        }
        else
        {
            alias ColT = void;
        }
        alias LineT   = Line!(PosT,Affine);
        alias PackT   = LinesPack!(PosT,LineT,Affine);
        alias TileT   = Tile!(MinTileWidth,MinTileHeight,PosT,PackT,Affine);
        alias PointT  = Point!(PosT,PackT,Affine);
        alias SpansT  = Spans!(MinTileHeight,PosT,ColT,PosT);

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        minX = max(mClipRect.x, minX);
        maxX = min(mClipRect.x + mClipRect.w, maxX);
        minY = max(mClipRect.y, minY);
        maxY = min(mClipRect.y + mClipRect.h, maxY);
        const upperVert = (pverts[0].pos.y < pverts[1].pos.y ?
                          (pverts[0].pos.y < pverts[2].pos.y ? pverts[0] : pverts[2]) :
                          (pverts[1].pos.y < pverts[2].pos.y ? pverts[1] : pverts[2]));

        immutable pack = PackT(pverts[0], pverts[1], pverts[2]);

        @nogc void drawSpans(LineT,SpansT)(auto ref LineT line, in auto ref SpansT spans, int y0, int y1) pure nothrow
        {
            foreach(y;y0..y1)
            {
                const my = y % MinTileHeight;
                ditherColorLine(line,spans.x0[my],spans.x1[my],my,spans.col0[my],spans.col1[my]);
                ++line;
            }
        }

        @nogc void fillTile(T)(auto ref T spans, int x0, int y0, int x1, int y1)
        {
            drawSpans(mBitmap[y0], spans, y0, y1);
        }
        @nogc void drawTile(int x0, int y0, int x1, int y1, int sx)
        {
            int sy = y0;
            auto pt = PointT(&pack, x0, sy);
            //mBitmap[sy][sx] = ColorWhite;
            outer1: while(true)
            {
                foreach(x;0..MinTileWidth - 1)
                {
                    if(pt.check()) break outer1;
                    pt.incX!"+"();
                }
                if(pt.check()) break outer1;
                ++sy;
                if(sy >= y1) return;
                pt.incY();
                foreach(x;0..MinTileWidth - 1)
                {
                    if(pt.check()) break outer1;
                    pt.incX!"-"();
                }
                if(pt.check()) break outer1;
                ++sy;
                if(sy >= y1) return;
                pt.incY();
            }
            SpansT spans = void;

            int ey = sy;
            outer2: while(ey < y1)
            {
                auto ptRight = pt;
                const my = ey % MinTileHeight;
                while(true) //move left
                {
                    if(pt.currx < x0) break;
                    if(!pt.check())
                    {
                        break;
                    }
                    pt.incX!"-"();
                }
                spans.x0[my] = pt.currx + 1;
                while(true) //move right
                {
                    if(ptRight.currx >= x1) break;
                    ptRight.incX!"+"();
                    if(!ptRight.check())
                    {
                        break;
                    }
                }
                spans.x1[my] = ptRight.currx;
                if(ey >= y1)
                {
                    break;
                }
                pt.incY();
                while(pt.currx <= ptRight.currx)
                {
                    if(pt.check())
                    {
                        ++ey;
                        continue outer2;
                    }
                    pt.incX!"+"();
                }
                break;
            }
            if(sy >= ey) return;

            static if(HasColor)
            {
                const my0 = sy % MinTileHeight;
                const my1 = (ey - 1) % MinTileHeight;
                PosT[3] bary = void;
                pack.getBarycentric(spans.x0[my0],     sy, bary);
                spans.col0[my0] = calcColor(bary);
                pack.getBarycentric(spans.x1[my0] - 1, sy, bary);
                spans.col1[my0] = calcColor(bary);
                pack.getBarycentric(spans.x0[my1],     ey, bary);
                spans.col0[my1] = calcColor(bary);
                pack.getBarycentric(spans.x1[my1] - 1, ey, bary);
                spans.col1[my1] = calcColor(bary);
                const hgt = ey - sy;
                ColT.interpolateLine(hgt, spans.col0[my0..my1 + 1], spans.col0[my0], spans.col0[my1]);
                ColT.interpolateLine(hgt, spans.col1[my0..my1 + 1], spans.col1[my0], spans.col1[my1]);
            }

            drawSpans(mBitmap[sy], spans, sy, ey);
        }

        const ux = cast(int)upperVert.pos.x + 1;
        const uy = cast(int)upperVert.pos.y;
        const tx = ux / MinTileWidth;
        const ty = uy / MinTileHeight;
        TileT currentTile    = TileT(&pack, tx * MinTileWidth, ty * MinTileHeight);
        TileT savedRightTile;
        /*foreach(y;minY..maxY)
        {
            mBitmap[y][minX..maxX] = ColorWhite;
        }*/
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
            int endX       = currentTile.currx;

            const y0 = max(currentTile.curry,uy);
            const y1 = currentTile.curry + MinTileHeight;

            //move left
            while(true)
            {
                currentTile.incX!("-")();
                tileMask >>= 6;
                tileMask |= (currentTile.check() << 6);

                if(none(tileMask))
                {
                    startX = currentTile.currx + MinTileWidth;
                    break;
                }

                if(all(tileMask))
                {
                    startFillX = min(startFillX, currentTile.currx);
                    endFillX   = max(  endFillX, currentTile.currx + MinTileWidth);
                }
            }

            //move right
            tileMask = (savedRightTile.check() << 6);
            while(true)
            {
                savedRightTile.incX!("+")();
                tileMask >>= 6;
                tileMask |= (savedRightTile.check() << 6);
                if(none(tileMask))
                {
                    endX = savedRightTile.currx - MinTileWidth;
                    break;
                }

                if(all(tileMask))
                {
                    startFillX = min(startFillX, savedRightTile.currx - MinTileWidth);
                    endFillX   = max(  endFillX, savedRightTile.currx);
                }
            }
            if(endFillX > startFillX)
            {
                for(auto x = startX; x < startFillX; x += MinTileWidth)
                {
                    const x0 = x;
                    const x1 = x0 + MinTileWidth;
                    const sx = clamp(ux, x0, x1 - 1);
                    drawTile(x0, y0, x1, y1, sx);
                }
                SpansT spans = void;
                spans.setX(startFillX);
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
                for(auto x = startFillX; x < endFillX; x += MinTileWidth)
                {
                    spans.incX(MinTileWidth);
                    static if(HasColor)
                    {
                        pack.getBarycentric(x + MinTileWidth, y0    , bary);
                        const col0 = calcColor(bary);
                        pack.getBarycentric(x + MinTileWidth, y1 - 1, bary);
                        const col1 = calcColor(bary);
                        ColT.interpolateLine!MinTileHeight(spans.col1[0..$], col0, col1);
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
                    drawTile(x0, y0, x1, y1, sx);
                }
            }
            else
            {
                for(auto x = startX; x < endX; x += MinTileWidth)
                {
                    const x0 = x;
                    const x1 = x0 + MinTileWidth;
                    const sx = clamp(ux, x0, x1 - 1);
                    drawTile(x0, y0, x1, y1, sx);
                }
            }

            currentTile.incY();
            tileMask = (currentTile.check() << 6);
            while(currentTile.currx < savedRightTile.currx)
            {
                currentTile.incX!("+")();
                tileMask >>= 6;
                tileMask |= (currentTile.check() << 6);
                if(!none(tileMask))
                {
                    continue outer;
                }
            }

            break;
        }
        //end
    }
}