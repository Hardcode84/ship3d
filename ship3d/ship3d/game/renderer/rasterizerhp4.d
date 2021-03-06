﻿module game.renderer.rasterizerhp4;

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

struct RasterizerHP4(BitmapT,TextureT,DepthT = void)
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
    enum MaxTileWidth  = 64;
    enum MaxTileHeight = 64;
    enum TileCoeff     = 8;

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

    }

    struct Tile(int TileWidth, int TileHeight, PosT,PackT)
    {
        immutable(PackT)* pack;
        enum NumLines = 3;
        int currx = void;
        int curry = void;
        PosT[NumLines] cx0 = void, cx1 = void, cy = void;
        uint mask = void;

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
                cy[i]  = val;
                cx0[i] = val;
                cx1[i] = val + pack.lines[i].dx * TileHeight;
            }
            currx = x;
            curry = y;
            mask = check();
        }

        void incX(string sign = "+")() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                const dx = pack.lines[i].dy * -TileWidth;
                mixin("cx0[i] "~sign~"= dx;");
                mixin("cx1[i] "~sign~"= dx;");
            }
            mixin("currx"~sign~"= TileWidth;");
            mask >>= (NumLines * 2);
            mask |= check();
        }

        void incY() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cy[i] += pack.lines[i].dx * TileHeight;
                cx0[i] = cy[i];
                cx1[i] = cy[i] + pack.lines[i].dx * TileHeight;
            }
            curry += TileHeight;
            mask = check();
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

        bool none() const pure nothrow
        {
            return 0x0 == (mask & 0b001_001_001_001) ||
                   0x0 == (mask & 0b010_010_010_010) ||
                   0x0 == (mask & 0b100_100_100_100);
        }
        bool all() const pure nothrow
        {
            return mask == 0b111_111_111_111;
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
            immutable ColT[3] vcols = [pverts[0].color,pverts[1].color,pverts[2].color];
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
        //alias TileT   = Tile!(MinTileWidth,MinTileHeight,PosT,PackT);
        alias SpansT  = Spans!(MinTileHeight,PosT,ColT,PosT);

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        minX = max(mClipRect.x, minX);
        maxX = min(mClipRect.x + mClipRect.w, maxX);
        minY = max(mClipRect.y, minY);
        maxY = min(mClipRect.y + mClipRect.h, maxY);

        immutable pack = PackT(pverts[0], pverts[1], pverts[2]);

        void drawTile(int x0, int y0, int x1, int y1)
        {
            auto line = mBitmap[y0];
            foreach(y;y0..y1)
            {
                line[x0..x1] = ColorGreen;
                ++line;
            }
        }

        void fillTile(int x0, int y0, int x1, int y1)
        {
            auto line = mBitmap[y0];
            foreach(y;y0..y1)
            {
                line[x0..x1] = ColorRed;
                ++line;
            }
        }

        void drawArea(int TileWidth, int TileHeight)(int tx0,int ty0, int tx1, int ty1) nothrow
        {
            enum LastLevel = (TileWidth == MinTileWidth && TileHeight == MinTileHeight);

            auto tile = Tile!(TileWidth,TileHeight,PosT,PackT)(&pack,tx0*TileWidth,ty0*TileHeight);
            foreach(ty;ty0..ty1)
            {
                const y0 = ty * TileHeight;
                const y1 = y0 + TileHeight;
                foreach(tx;tx0..tx1)
                {
                    const x0 = tx * TileWidth;
                    const x1 = x0 + TileWidth;
                    tile.incX();
                    static if(LastLevel)
                    {
                    }
                    else
                    {
                    }
                }
                tile.incY();
            }
        }
        void clipArea(int TileWidth, int TileHeight)() nothrow
        {
            const minTx =  minX / TileWidth;
            const maxTx = (maxX + TileWidth - 1) / TileWidth;
            const minTy =  minY / TileHeight;
            const maxTy = (maxY + TileHeight - 1) / TileHeight;
            drawArea!(TileWidth,TileHeight)(minTx,minTy,maxTx,maxTy);
        }
        clipArea!(MaxTileWidth,MaxTileHeight)();
        //end
    }
}