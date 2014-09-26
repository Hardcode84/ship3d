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

        this(VT)(in VT v1, in VT v2, in PosT baryInvDenom) pure nothrow
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            dx = (x2 - x1) * baryInvDenom;
            dy = (y2 - y1) * baryInvDenom;
            const inc = (dy < 0 || (dy == 0 && dx > 0)) ? cast(PosT)1 / cast(PosT)16 : cast(PosT)0;
            c = (dy * x1 - dx * y1) + inc * baryInvDenom;
        }

        /*void setXY(int x, int y) pure nothrow
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
        }*/

        auto val(int x, int y) const pure nothrow
        {
            return c + dx * y - dy * x;
        }

        //@property auto curr() const pure nothrow { return cx; }
    }

    struct LinesPack(PosT,LineT,bool Affine)
    {
    @nogc:
        enum NumLines = 3;
        LineT[NumLines] lines;
        static if(!Affine)
        {
            immutable PosT[NumLines] sw;
        }
        this(VT)(in VT v1, in VT v2, in VT v3) pure nothrow
        {
            const invDenom = cast(PosT)(1 / ((v2.pos - v1.pos).xy.wedge((v3.pos - v1.pos).xy)));
            lines = [
                LineT(v1, v2, invDenom),
                LineT(v2, v3, invDenom),
                LineT(v3, v1, invDenom)];
            static if(!Affine)
            {
                sw = [
                    cast(PosT)1 / v1.pos.w,
                    cast(PosT)1 / v2.pos.w,
                    cast(PosT)1 / v3.pos.w];
            }
        }

    }
    struct Tile(PosT,PackT,bool Affine)
    {
    @nogc:
        const(PackT)* pack;
        enum NumLines = 3;
        PosT[NumLines] cx, cy;
        static if(!Affine)
        {
            PosT sw = void;
            immutable PosT swdx, swdy;
        }

        this(in PackT* p, int x, int y)
        {
            pack = p;
            static if(!Affine)
            {
            }
            setXY(x,y);
        }
        void setXY(int x, int y) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cy[i] = pack.lines[i].val(x, y);
                cx[i] = cy[i];
            }
        }

        void incX(int val) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cx[i] -= pack.lines[i].dy * val;
            }
            static if(!Affine)
            {
                sw += swdx * val;
            }
        }
        
        void incY(int val) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cy[i] += pack.lines[i].dx * val;
                cx[i] = cy[i];
            }
            static if(!Affine)
            {
                sw += swdy * val;
            }
        }

        @property auto all() const pure nothrow
        {
            //return all!"a.curr > 0"(lines[]);
            return cx[0] > 0 && cx[1] > 0 && cx[2] > 0;
        }

        @property auto check() const pure nothrow
        {
            uint ret = 0;
            foreach(i;TupleRange!(0,NumLines))
            {
                ret |= ((cx[i] > 0) << i);
            }
            return ret;
        }

        void getBarycentric(PosT[] ret) const pure nothrow
        in
        {
            assert(ret.length == NumLines);
        }
        out
        {
            assert(almost_equal(cast(PosT)1, ret.sum, 1.0f/255.0f), debugConv(ret.sum));
        }
        body
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                //static if(Affine)
                {
                    ret[i] = cx[i];
                }
                /*else
                {
                    ret[i] = cx[i] * sw[i];
                }*/
            }

        }

        /*@property auto w() const pure nothrow
        {
            static if(Affine)
            {
                return 1;
            }
            else
            {
                return cast(PosT)1 / sw;
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
        alias TileT   = Tile!(PosT,PackT,Affine);

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        minX = max(mClipRect.x, minX);
        maxX = min(mClipRect.x + mClipRect.w, maxX);
        minY = max(mClipRect.y, minY);
        maxY = min(mClipRect.y + mClipRect.h, maxY);


        void drawArea(int TileWidth, int TileHeight,T)(in T extPack, int tx0,int ty0, int tx1, int ty1)
        {
            enum LastLevel = (TileWidth == MinTileWidth && TileHeight == MinTileHeight);

            auto pack0 = TileT(&extPack,tx0*TileWidth,ty0*TileHeight);
            auto pack1 = pack0;
            foreach(ty;ty0..ty1)
            {
                const y0 = ty * TileHeight;
                if(y0 >= maxY) break;
                pack1.incY(TileHeight);
                uint c = 0;
                c |= (pack0.check << 0);
                c |= (pack1.check << 3);
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
                int txStart = tx1;
                foreach(tx;tx0..tx1)
                {
                    //mBitmap[y0][tx*TileWidth] = ColorRed;
                    pack0.incX(TileWidth);
                    pack1.incX(TileWidth);
                    c |= (pack0.check << 6);
                    c |= (pack1.check << 9);
                    if(!none(c))
                    {
                        txStart = tx;
                        break;
                    }
                    c >>= 6;
                }

                static if(LastLevel)
                {
                    PosT[3] bary0 = void;
                    PosT[3] bary1 = void;
                    static if(HasColor)
                    {
                        ColT[TileHeight] cols0 = void;
                        ColT[TileHeight] cols1 = void;
                    }
                    @nogc void drawTile(bool Fill)(int x0, int y0,int x1, int y1) nothrow
                    {
                        static if(!Fill)
                        {
                            TileT tile = TileT(&extPack,x0,y0);
                        }

                        auto line = mBitmap[y0];
                        foreach(y;y0..y1)
                        {
                            static if(Fill)
                            { 
                                line[x0..x1] = ColorRed;
                            }
                            else
                            {
                                tile.incY(1);
                                foreach(x;x0..x1)
                                {
                                    tile.incX(1);
                                    if(tile.all)
                                    {
                                        line[x] = ColorGreen;
                                    }
                                    else
                                    {
                                        //line[x] = ColorBlue;
                                    }
                                }
                            }
                            ++line;
                        }
                    }

                    const y1 = y0 + TileHeight;
                    foreach(tx;txStart..tx1)
                    {
                        //mBitmap[y0][tx*TileWidth] = ColorRed;
                        const x0 = tx * TileWidth;
                        const x1 = x0 + TileWidth;
                        if(all(c))
                        {
                            //fully covered
                            drawTile!(true)(x0,y0,x1,y1);
                        }
                        else
                        {
                            //patrially covered
                            drawTile!(false)(x0,y0,x1,y1);
                        }
                        pack0.incX(TileWidth);
                        pack1.incX(TileWidth);
                        c >>= 6;
                        c |= (pack0.check << 6);
                        c |= (pack1.check << 9);
                        if(none(c))
                        {
                            break;
                        }
                    }
                }
                else
                {
                    int txEnd = tx1;//txStart;
                    foreach(tx;txStart..tx1)
                    {
                        //mBitmap[y0][tx*TileWidth] = ColorRed;
                        pack0.incX(TileWidth);
                        pack1.incX(TileWidth);
                        c >>= 6;
                        c |= (pack0.check << 6);
                        c |= (pack1.check << 9);
                        if(none(c))
                        {
                            txEnd = tx + 1;
                            break;
                        }
                    }


                    if(txEnd > txStart)
                    {
                        enum NewTileWidth  = TileWidth  / TileCoeff;
                        enum NewTileHeight = TileHeight / TileCoeff;
                        drawArea!(NewTileWidth,NewTileHeight)(extPack,
                                                              txStart  * TileCoeff,
                                                              ty       * TileCoeff,
                                                              txEnd    * TileCoeff,
                                                              (ty + 1) * TileCoeff);
                    }
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
            auto pack = PackT(pverts[0], pverts[1], pverts[2]);
            //pack.incX(64);
            drawArea!(TileWidth,TileHeight)(pack,minTx,minTy,maxTx,maxTy);
        }
        /*foreach(y;minY..maxY)
        {
            mBitmap[y][minX..maxX] = ColorWhite;
        }*/
        clipArea!(MaxTileWidth,MaxTileHeight)();
        //end
    }
}