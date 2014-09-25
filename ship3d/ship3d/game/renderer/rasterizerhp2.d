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
    enum MaxTileWidth  = 8;
    enum MaxTileHeight = 8;
    enum TileCoeff     = 8;

    struct Line(PosT,bool Affine)
    {
    @nogc:
        immutable PosT dx, dy, c;
        //PosT cx = void, cy = void;

        this(VT)(in VT v1, in VT v2, int x, int y, PosT baryInvDenom) pure nothrow
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            dx = (x2 - x1) * baryInvDenom;
            dy = (y2 - y1) * baryInvDenom;
            const inc = (dy < 0 || (dy == 0 && dx > 0)) ? cast(PosT)1 / cast(PosT)16 : cast(PosT)0;
            c = (dy * x1 - dx * y1) + inc * baryInvDenom;
            //setXY(x,y);
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
            immutable PosT[NumLines] w;
        }
        this(VT)(in VT v1, in VT v2, in VT v3, int x, int y) pure nothrow
        {
            const invDenom = 1.0f;//cast(PosT)(1 / ((v2.pos - v1.pos).xy.wedge((v3.pos - v1.pos).xy)));
            lines = [
                LineT(v1, v2, x, y, invDenom),
                LineT(v2, v3, x, y, invDenom),
                LineT(v3, v1, x, y, invDenom)];
            static if(!Affine)
            {
                w = [cast(PosT)v1.pos.w, cast(PosT)v2.pos.w, cast(PosT)v3.pos.w];
            }
        }

        /*void incX(int val) pure nothrow
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

        auto all() const pure nothrow
        {
            //return all!"a.curr > 0"(lines[]);
            return lines[0].curr > 0 && lines[1].curr > 0 && lines[2].curr > 0;
        }

        auto any() const pure nothrow
        {
            //return any!"a.curr > 0"(lines[]);
            return lines[0].curr > 0 || lines[1].curr > 0 || lines[2].curr > 0;
        }*/
    }
    struct Tile(PosT,PackT)
    {
    @nogc:
        const(PackT)* pack;
        enum NumLines = 3;
        PosT[NumLines] cx, cy;

        this(in PackT* p, int x, int y)
        {
            pack = p;
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
        }
        
        void incY(int val) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cy[i] += pack.lines[i].dx * val;
                cx[i] = cy[i];
            }
        }

        @property auto all() const pure nothrow
        {
            //return all!"a.curr > 0"(lines[]);
            return cx[0] > 0 && cx[1] > 0 && cx[2] > 0;
        }

        @property auto any() const pure nothrow
        {
            //return any!"a.curr > 0"(lines[]);
            return cx[0] > 0 || cx[1] > 0 || cx[2] > 0;
        }

        @property auto check() const pure nothrow
        {
            uint ret = 0;
            ret |= (all << 0);
            ret |= (any << 1);
            return ret;
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
        alias TileT   = Tile!(PosT,PackT);

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
            //pack0.incY(-TileHeight);
            //pack1.incY(-TileHeight);
            foreach(ty;ty0..ty1)
            {
                const y0 = ty * TileHeight;
                if(y0 >= maxY) break;
                pack1.incY(TileHeight);
                uint c = 0;
                //debugOut("---");
                c |= (pack0.check << 0);
                c |= (pack1.check << 2);
                int txStart = tx1;
                foreach(tx;tx0..tx1)
                {
                    mBitmap[y0][tx*TileWidth] = ColorRed;
                    pack0.incX(TileWidth);
                    pack1.incX(TileWidth);
                    c |= (pack0.check << 4);
                    c |= (pack1.check << 6);
                    if(0x0 != c)
                    {
                        //debugOut("brk");
                        txStart = tx;
                        break;
                    }
                    c >>= 4;
                }
                //debugOut(txStart);

                static if(LastLevel)
                {
                    @nogc void drawTile(bool Fill)(int x0, int y0,int x1, int y1) nothrow
                    {
                        auto pack = pack0;
                        pack.setXY(x0,y0);
                        
                        auto line = mBitmap[y0];
                        foreach(y;y0..y1)
                        {
                            static if(Fill)
                            { 
                                line[x0..x1] = ColorRed;
                            }
                            else
                            {
                                pack.incY(1);
                                foreach(x;x0..x1)
                                {
                                    pack.incX(1);
                                    if(pack.all)
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
                    foreach(tx;(txStart)..tx1)
                    {
                        mBitmap[y0][tx*TileWidth] = ColorRed;
                        const x0 = tx * TileWidth;
                        const x1 = x0 + TileWidth;
                       
                        if(0xff == c)
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
                        c >>= 4;
                        c |= (pack0.check << 4);
                        c |= (pack1.check << 6);
                        if(0x0 == c)
                        {
                            break;
                        }
                    }
                }
                else
                {
                    static assert(false);
                    /*int txEnd = tx1;
                    foreach(tx;(txStart + 1)..tx1)
                    {
                        pack0.incX(TileWidth);
                        pack1.incX(TileWidth);
                        c |= (pack0.all << 2);
                        c |= (pack1.all << 3);
                        if(0x0 == c)
                        {
                            txEnd = tx;
                            break;
                        }
                        c >>= 2;
                    }

                    if(txEnd > txStart)
                    {
                        enum NewTileWidth  = TileWidth  / TileCoeff;
                        enum NewTileHeight = TileHeight / TileCoeff;
                        pack.incX(TileWidth * (txStart - tx0));
                        drawArea!(NewTileWidth,NewTileHeight)(pack,
                                                              txStart * TileCoeff,
                                                              ty      * TileCoeff,
                                                              txEnd   * TileCoeff,
                                                              ty      * TileCoeff);
                    }*/
                }

                pack0.incY(TileHeight);
                //pack1.incY(TileHeight);
            }
        }
        void clipArea(int TileWidth, int TileHeight)()
        {
            const minTx =  minX / TileWidth;
            const maxTx = (maxX + TileWidth - 1) / TileWidth;
            const minTy =  minY / TileHeight;
            const maxTy = (maxY + TileHeight - 1) / TileHeight;
            auto pack = PackT(pverts[0], pverts[1], pverts[2], minTx * TileWidth, minTy * TileHeight);
            //pack.incX(64);
            drawArea!(TileWidth,TileHeight)(pack,minTx,minTy,maxTx,maxTy);
        }
        /*foreach(y;minY..maxY)
        {
            mBitmap[y][minX..maxX] = ColorWhite;
        }*/
        clipArea!(8,8)();
        //end
    }
}