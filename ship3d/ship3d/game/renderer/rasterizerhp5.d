module game.renderer.rasterizerhp5;

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

struct RasterizerHP5(BitmapT,TextureT)
{
@nogc:
private:
    BitmapT mBitmap;
    TextureT mTexture;
    Rect mClipRect;

    enum TileWidth  = 8;
    enum TileHeight = 8;

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
            const inc = (dy < 0 || (dy == 0 && dx > 0)) ? cast(PosT)1 / cast(PosT)8 : cast(PosT)0;
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

        void incY(int val) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cx[i] += (dy[i] * val);
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

    struct Spans(int Height,PosT,TextT)
    {
        TextT[2] uv00 = void;
        TextT[2] uv10 = void;
        TextT[2] uv01 = void;
        TextT[2] uv11 = void;
    }

    struct Context(TextT)
    {
        int x = void;
        int y = void;
        TextT u = void;
        TextT v = void;
        TextT dux = void;
        TextT dvx = void;
        TextT duy = void;
        TextT dvy = void;
    }
public:
    this(BitmapT b)
    in
    {
        assert(b !is null);
        assert(0 == (b.width  % TileWidth),  debugConv(b.width));
        assert(0 == (b.height % TileHeight), debugConv(b.height));
    }
    body
    {
        mBitmap = b;
        mClipRect = Rect(0, 0, mBitmap.width, mBitmap.height);
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
        static assert(HasTextures);
        static assert(HasTextures != HasColor);
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
        alias TileT   = Tile!(TileWidth,TileHeight,PosT,PackT);
        alias PointT  = Point!(PosT,PackT,Affine);
        alias SpansT  = Spans!(TileHeight,PosT,TextT);
        alias CtxT    = Context!(TextT);

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y) + 1;

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x) + 1;



        minX = max(mClipRect.x, minX);
        maxX = min(mClipRect.x + mClipRect.w, maxX);
        minY = max(mClipRect.y, minY);
        maxY = min(mClipRect.y + mClipRect.h, maxY);

        const upperVertInd = (pverts[0].pos.y < pverts[1].pos.y ?
                          (pverts[0].pos.y < pverts[2].pos.y ? 0 : 2) :
                          (pverts[1].pos.y < pverts[2].pos.y ? 1 : 2));
        const upperVert = pverts[upperVertInd];

        immutable pack = PackT(pverts[0], pverts[1], pverts[2]);

        @nogc void fillTile(T)(auto ref T spans, int x0, int y0, int x1, int y1)
        {
            assert(x0 >= 0,   debugConv(x0));
            assert(y0 >= 0,   debugConv(y0));
            assert(x1 > minX, debugConv(x1));
            assert(x0 < maxX, debugConv(x0));
            assert(y1 > minY, debugConv(y1));
            assert(y0 < maxY, debugConv(y0));

            alias TextT = Unqual!(typeof(spans.uv00[0]));
            TextT[2] uvs = spans.uv00;
            const TextT wdt = x1 - x0;
            const TextT hgt = y1 - y0;
            CtxT context = void;
            context.dux = (spans.uv10[0] - spans.uv00[0]) / wdt;
            context.dvx = (spans.uv10[1] - spans.uv00[1]) / wdt;
            context.duy = (spans.uv01[0] - spans.uv00[0]) / hgt;
            context.dvy = (spans.uv01[1] - spans.uv00[1]) / hgt;
            auto line = mBitmap[y0];
            foreach(y;y0..y1)
            {
                context.y = y;
                context.u = uvs[0];
                context.v = uvs[1];
                foreach(x;x0..x1)
                {
                    context.x = x;
                    line[x] = mTexture.get(context.u, context.v);
                    context.u += context.dux;
                    context.v += context.dvx;
                }
                uvs[0] += context.duy;
                uvs[1] += context.dvy;
                ++line;
            }
        }
        @nogc void drawTile(T)(auto ref T spans, int x0, int y0, int x1, int y1)
        {
            assert(x0 >= 0,   debugConv(x0));
            assert(y0 >= 0,   debugConv(y0));
            assert(x1 > minX, debugConv(x1));
            assert(x0 < maxX, debugConv(x0));
            assert(y1 > minY, debugConv(y1));
            assert(y0 < maxY, debugConv(y0));
            alias TextT = Unqual!(typeof(spans.uv00[0]));
            TextT[2] uvs = spans.uv00;
            const TextT wdt = x1 - x0;
            const TextT hgt = y1 - y0;
            CtxT context = void;
            context.dux = (spans.uv10[0] - spans.uv00[0]) / wdt;
            context.dvx = (spans.uv10[1] - spans.uv00[1]) / wdt;
            context.duy = (spans.uv01[0] - spans.uv00[0]) / hgt;
            context.dvy = (spans.uv01[1] - spans.uv00[1]) / hgt;
            int ys = y1;
            outer1: foreach(y;y0..y1)
            {
                auto pt = PointT(pack, x0, y);
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

            const TextT dy = ys - y0;
            uvs[0] += context.duy * dy;
            uvs[1] += context.dvy * dy;
            auto line = mBitmap[ys];
            foreach(y;ys..y1)
            {
                context.y = y;
                auto pt = PointT(pack, x0, y);
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
                const len = xe - xs;
                if(len > 0)
                {
                    context.u = uvs[0];
                    context.v = uvs[1];
                    const TextT dx = xs - x0;
                    context.u += (context.dux * dx);
                    context.v += (context.dvx * dx);
                    foreach(x;xs..xe)
                    {
                        context.x = x;
                        line[x] = mTexture.get(context.u, context.v);
                        context.u += context.dux;
                        context.v += context.dvx;
                    }
                }
                else
                {
                    break;
                }
                uvs[0] += context.duy;
                uvs[1] += context.dvy;
                ++line;
            }
        }

        int ux = cast(int)upperVert.pos.x;
        int uy = cast(int)upperVert.pos.y;
        if(uy >= maxY) return;
        if(uy >= minY && ux >= minX && ux <= maxX)
        {
        }
        else
        {
            bool test(in ref PointT pt00, in ref PointT pt10, in ref PointT pt01, in ref PointT pt11) nothrow
            {
                const mask = (pt00.vals() | pt10.vals() | pt01.vals() | pt11.vals());
                bool res = (0x0 != (mask & 0b001)) &&
                           (0x0 != (mask & 0b010)) &&
                           (0x0 != (mask & 0b100));
                if(res)
                {
                    const dx = (pt10.currx - pt00.currx);
                    const cx = pt00.currx + dx / 2;
                    if(dx <= 3)
                    {
                        ux = cx + 1;
                        uy = pt00.curry;
                        return true;
                    }
                    const pt0 = PointT(pack, cx, pt00.curry);
                    const pt1 = PointT(pack, cx, pt11.curry);
                    if(test(pt00, pt0, pt01, pt1)) return true;
                    if(test(pt0, pt10, pt1, pt11)) return true;
                }
                return false;
            }

            found: do
            {
                const mintx = (minX / TileWidth)     * TileWidth;
                const maxtx = ((maxX + TileHeight - 1) / TileWidth) * TileWidth;
                const minty = (minY / TileHeight)     * TileHeight;
                const maxty = ((maxY + TileHeight - 1) / TileHeight) * TileHeight;

                auto pt00 = PointT(pack, mintx, minty);
                auto pt10 = PointT(pack, maxtx, minty);
                auto pt01 = PointT(pack, mintx, minty + TileHeight);
                auto pt11 = PointT(pack, maxtx, minty + TileHeight);
                for(int y = minty; y < maxty; y += TileHeight)
                {
                    if(test(pt00, pt10, pt01, pt11))
                    {
                        break found;
                    }
                    pt00.incY(TileHeight);
                    pt10.incY(TileHeight);
                    pt01.incY(TileHeight);
                    pt11.incY(TileHeight);
                }
                return;
            }
            while(false);
        }

        const tx = ux / TileWidth;
        const ty = uy / TileHeight;
        TileT currentTile    = TileT(&pack, tx * TileWidth, ty * TileHeight);
        TileT savedRightTile;

        int y0 = uy;
        int y1 = currentTile.curry + TileHeight;
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
            uint tileMask  = (currentTile.check() << 6);
            savedRightTile = currentTile;
            int startX     = currentTile.currx;
            int startFillX =  9000;
            int endFillX   = -9000;
            int endX       = currentTile.currx + TileWidth;

            //move left
            while(currentTile.currx > (minX - TileWidth))
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
                    endFillX   = currentTile.currx + TileWidth;
                }
            }
            startX = currentTile.currx + TileWidth;

            //move right
            tileMask = (savedRightTile.check() << 6);
            while(savedRightTile.currx < (maxX + TileWidth))
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
                    startFillX = min(startFillX, savedRightTile.currx - TileWidth);
                    endFillX   = savedRightTile.currx;
                }
            }
            endX = savedRightTile.currx - TileWidth;
            startFillX = max(startFillX, startX);
            endFillX   = min(endFillX,   endX);

            assert(startX >= 0,                 debugConv(startX));
            assert(startX > (minX - TileWidth), debugConv(startX));
            assert(endX   < (maxX + TileWidth), debugConv(endX));
            assert(endX   >= endFillX);

            SpansT spans = void;
            if(endFillX > startFillX)
            {
                pack.getUV(startX, y0, spans.uv10);
                pack.getUV(startX, y1, spans.uv11);

                for(auto x = startX; x < startFillX; x += TileWidth)
                {
                    spans.uv00 = spans.uv10;
                    spans.uv01 = spans.uv11;
                    pack.getUV(x + TileWidth, y0, spans.uv10);
                    pack.getUV(x + TileWidth, y1, spans.uv11);

                    const x0 = x;
                    const x1 = x0 + TileWidth;
                    drawTile(spans, x0, y0, x1, y1);
                }
                for(auto x = startFillX; x < endFillX; x += TileWidth)
                {
                    spans.uv00 = spans.uv10;
                    spans.uv01 = spans.uv11;
                    pack.getUV(x + TileWidth, y0, spans.uv10);
                    pack.getUV(x + TileWidth, y1, spans.uv11);

                    const x0 = x;
                    const x1 = x0 + TileWidth;
                    fillTile(spans, x0, y0, x1, y1);
                }
                for(auto x = endFillX; x < endX; x += TileWidth)
                {
                    spans.uv00 = spans.uv10;
                    spans.uv01 = spans.uv11;
                    pack.getUV(x + TileWidth, y0, spans.uv10);
                    pack.getUV(x + TileWidth, y1, spans.uv11);

                    const x0 = x;
                    const x1 = x0 + TileWidth;
                    drawTile(spans, x0, y0, x1, y1);
                }
            }
            else
            {
                pack.getUV(startX, y0, spans.uv10);
                pack.getUV(startX, y1, spans.uv11);

                for(auto x = startX; x < endX; x += TileWidth)
                {
                    spans.uv00 = spans.uv10;
                    spans.uv01 = spans.uv11;
                    pack.getUV(x + TileWidth, y0, spans.uv10);
                    pack.getUV(x + TileWidth, y1, spans.uv11);

                    const x0 = x;
                    const x1 = x0 + TileWidth;
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
                    y1 = y0 + TileHeight;
                    continue outer;
                }
            }

            break;
        }
        //end
    }
}