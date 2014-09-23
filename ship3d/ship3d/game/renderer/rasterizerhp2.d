module game.renderer.rasterizerhp2;

import std.traits;
import std.algorithm;
import std.array;
import std.string;
import std.functional;
import std.range;

import gamelib.util;
import gamelib.math;

import game.units;

@nogc:

struct RasterizerHP2(BitmapT,TextureT,DepthT = void)
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
        PosT cx, cy;

        this(VT)(in VT v1, in VT v2, int minX, int minY, PosT baryInvDenom) pure nothrow
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            dx = (x2 - x1) * baryInvDenom;
            dy = (y2 - y1) * baryInvDenom;
            const inc = (dy < 0 || (dy == 0 && dx > 0)) ? cast(PosT)1 / cast(PosT)16 : cast(PosT)0;
            c = (dy * x1 - dx * y1) + inc * baryInvDenom;
            setXY(minX, minY);
        }

        void setXY(int x, int y) pure nothrow
        {
            cy = val(x, y);
            cx = cy;
        }

        void incX(int val) pure nothrow
        {
            cx -= dy * val;
        }

        void incY(int val) pure nothrow
        {
            cy += dx * val;
            cx = cy;
        }

        /*auto val(int x, int y) const pure nothrow
        {
            return c + dx * y - dy * x;
        }

        uint testTile(int x1, int y1, int x2, int y2) const pure nothrow
        {
            bool a00 = (val(x1, y1) > 0);
            bool a10 = (val(x2, y1) > 0);
            bool a01 = (val(x1, y2) > 0);
            bool a11 = (val(x2, y2) > 0);
            return (a00 << 0) | (a10 << 1) | (a01 << 2) | (a11 << 3);
        }*/

        @property auto curr() const pure nothrow { return cx; }
    }

    struct LinesPack(PosT,LineT,bool Affine)
    {
    @nogc:
        enum NumLines = 3;
        LineT[NumLines] lines;
        static if(!Affine)
        {
            immutable PosT[NumLines] w;
        }
        this(VT)(in VT v1, in VT v2, in VT v3, int minX, int minY) pure nothrow
        {
            const invDenom = cast(PosT)(1 / ((v2.pos - v1.pos).xy.wedge((v3.pos - v1.pos).xy)));
            lines = [
                LineT(v1, v2, minX, minY, invDenom),
                LineT(v2, v3, minX, minY, invDenom),
                LineT(v3, v1, minX, minY, invDenom)];
            curr11 = check();
            static if(!Affine)
            {
                w = [cast(PosT)v1.pos.w, cast(PosT)v2.pos.w, cast(PosT)v3.pos.w];
            }
        }

        void incX(int val) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                lines[i].incX(val);
            }
        }

        void incY(int val) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                lines[i].incY(val);
            }
        }

        void setXY(int x, int y) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                lines[i].setXY(x, y);
            }
        }

        auto check() const pure nothrow
        {
            //return all!"a.curr > 0"(lines[]);
            return lines[0].curr > 0 && lines[1].curr > 0 && lines[2].curr > 0;
        }

        auto testTile(int x1, int y1, int x2, int y2) const pure nothrow
        {
            uint res = 0;
            foreach(i;TupleRange!(0,NumLines))
            {
                res |= (lines[i].testTile(x1,y1,x2,y2) << (4 * i));
            }
            return res;
        }
    }


    struct Tile(int W, int H, PosT, ColT)
    {
    @nogc:
        static assert(ispow2(W));
        static assert(ispow2(H));
        enum HasColor = !is(ColT : void);
        enum NumLines = 3;

        immutable int xStart;
        int x0;
        int y0;

        static if(HasColor)
        {
            private static auto calcColor(VT)(in VT[] v, in PosT[] c) pure nothrow
            in
            {
                assert(v.length == NumLines);
                assert(c.length == NumLines);
            }
            body
            {
                ColT ret = v[0] * c[0];
                foreach(i;TupleRange(1,NumLines))
                {
                    ret += v[i] * c[i];
                }
                return ret;
            }
            private auto interpolateColor(PosT[] bary) const pure nothrow
            {
                return colors[0] * bary[0] + colors[1] * bary[1] + colors[2] * bary[2];
            }
            immutable ColT[NumLines] colors;
            ColT[H] cols0 = void, cols1 = void;
            ColT col11t = void;
        }
        this(PackT,VT)(in PackT pack, in VT[] v, int x, int y) pure nothrow
        in
        {
            assert(v.length == NumLines);
        }
        body
        {
            xStart = x - W;
            x0 = x - W;
            y0 = y - H;
            PosT[NumLines] bary11 = void;
            pack.getBarycentric(x1,y1,bary11);
            static if(HasColor)
            {
                colors = [v[0].color,v[1].color,v[2].color];
                col11t = interpolateColor(bary11);
            }
        }

        @property auto x1() const pure nothrow { return x0 + W; }
        @property auto y1() const pure nothrow { return y0 + H; }

        void incX(PackT)(in PackT pack) pure nothrow
        {
            x0 += W;
            PosT[NumLines] bary10 = void;
            PosT[NumLines] bary11 = void;
            pack.getBarycentric(x1,y0,bary10);
            pack.getBarycentric(x1,y1,bary11);
            static if(HasColor)
            {
                const col10 = interpolateColor(bary10);
                const col11 = interpolateColor(bary11);
                cols0 = cols1;
                ColT.interpolateLine!H(cols1[],col10,col11);
            }
        }

        void incY(PackT)(in PackT pack) pure nothrow
        {
            x0 = xStart;
            y0 += H;
            PosT[NumLines] bary11 = void;
            pack.getBarycentric(x1,y1,bary11);
            static if(HasColor)
            {
                const col10 = col11t;
                const col11 = interpolateColor(bary11);
                col11t = col11;
                ColT.interpolateLine!H(cols1[],col10,col11);
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

    @property auto texture() inout pure nothrow { return mTexture; }
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
        //alias PosT = FixedPoint!(28,4,int);
        alias PosT = Unqual!(typeof(VertT.pos.x));
        static if(HasColor)
        {
            alias ColT = Unqual!(typeof(VertT.color));
        }
        else
        {
            alias ColT = void;
        }
        alias LineT   = Line!(PosT,Affine);
        alias PackT   = LinesPack!(PosT,LineT,Affine);
        alias TileT   = Tile!(MinTileWidth,MinTileHeight,PosT,ColT);
        alias TileNCT = Tile!(MinTileWidth,MinTileHeight,PosT,void); //no color

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        minX = max(mClipRect.x, minX);
        maxX = min(mClipRect.x + mClipRect.w, maxX);
        minY = max(mClipRect.y, minY);
        maxY = min(mClipRect.y + mClipRect.h, maxY);

        /*const minTx = minX / MinTileWidth;
        const maxTx = (maxX + MinTileWidth - 1) / MinTileWidth;
        const minTy = minY / MinTileHeight;
        const maxTy = (maxY + MinTileHeight - 1) / MinTileHeight;
        foreach(ty;minTy..maxTy)
        {
            const y0 = (ty + 0) * MinTileHeight;
            const y1 = (ty + 1) * MinTileHeight;
            foreach(tx;minTx..maxTx)
            {
                const x0 = (tx + 0) * MinTileWidth;
                const x1 = (tx + 1) * MinTileWidth;
                auto res = pack.testTile(x0, y0, x1, y1);
                if((0 == (res & 0xf)) || (0 == (res & 0xf0)) || (0 == (res & 0xf00)))  continue;
                
                if(0xfff == res)
                {
                    //completely covered
                    fillTile(MinTileWidth, MinTileHeight, x0, y0);
                }
                else
                {
                    //patrially covered
                    drawTile(MinTileWidth, MinTileHeight, x0, y0);
                }
            }
        }*/
        void drawArea(int TileWidth, int TileHeight,T)(in T extPack, int tx0,int ty0, int tx1, int ty1)
        {
            enum NewTileWidth  = TileWidth  / TileCoeff;
            enum NewTileHeight = TileHeight / TileCoeff;
            Unqual!T pack0 = extPack;
            Unqual!T pack1 = extPack;

            foreach(ty;ty0..ty1 + 1)
            {
                pack1.incY(TileHeight);
                uint c = 0;
                c |= (pack0.curr << 0);
                c |= (pack1.curr << 1);
                bool line = false;
                int txStart = tx1;
                int txEnd   = tx0;
                foreach(tx;tx0..tx1 + 1)
                {
                    pack0.incX(TileWidth);
                    pack1.incX(TileWidth);
                    c |= (pack0.curr << 2);
                    c |= (pack1.curr << 3);
                    if(0x0 != c)
                    {
                        if(!line)
                        {
                            line = true;
                            txStart = tx;
                        }
                    }
                    else if(line)
                    {
                        txEnd = tx;
                        break;
                    }

                    c >>= 2;
                }
                if(txEnd > txStart)
                {
                    drawArea!(NewTileWidth,NewTileHeight)(,txStart,ty,txEnd,ty);
                }

                pack0.incY(TileHeight);
            }
        }
        void clipArea(int TileWidth, int TileHeight)()
        {
            const minTx =  minX / TileWidth;
            const maxTx = (maxX + TileWidth - 1) / TileWidth;
            const minTy =  minY / TileHeight;
            const maxTy = (maxY + TileHeight - 1) / TileHeight;
            const pack = PackT(pverts[0], pverts[1], pverts[2], minX, minY);
            drawArea!(TileWidth,TileHeight)(pack,minTx,minTy,maxTx,maxTy);
        }
        clipArea!(MaxTileWidth,MaxTileHeight);
        //end
    }
}