module game.renderer.rasterizerhp2;

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

    struct Tile(PosT,PackT,bool Affine)
    {
    @nogc:
        const(PackT)* pack;
        enum NumLines = 3;
        PosT[NumLines] cx = void, cy = void;
        static if(!Affine)
        {
            PosT currw = void;
            PosT prevw = void;
        }

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
            static if(!Affine)
            {
                currw = pack.wplane.get(x,y);
                prevw = currw;
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
                currw -= pack.wplane.ac * val;
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
                currw = prevw - pack.wplane.bc * val;
                prevw = currw;
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

        void getBarycentric(int dx = 0)(PosT[] ret) const pure nothrow
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
            foreach(i;TupleRange!(1,NumLines))
            {
                enum li = (i + 1) % NumLines;
                auto val = cx[li] - pack.lines[li].dy * dx;
                static if(!Affine)
                {
                    val /= (currw - pack.wplane.ac * dx);
                }
                ret[i] = val;
            }
            ret[0] = cast(PosT)1 - ret[1] - ret[2];
        }
    }

    struct Span(PosT,ColT,DpthT)
    {
        enum HasColor = !is(ColT : void);
        enum HasDepth = !is(DpthT : void);
        int x0, x1;
        int y;
        static if(HasColor)
        {
            ColT col0 = void, col1 = void;
        }
        static if(HasDepth)
        {
            DpthT w0 = void, w1 = void;
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
        alias TileT   = Tile!(PosT,PackT,Affine);
        alias SpanT   = Span!(PosT,ColT,PosT);

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        minX = max(mClipRect.x, minX);
        maxX = min(mClipRect.x + mClipRect.w, maxX);
        minY = max(mClipRect.y, minY);
        maxY = min(mClipRect.y + mClipRect.h, maxY);
        @nogc drawSpan(LineT,SpanT)(auto ref LineT line, in ref SpanT span) nothrow
        {
            static if(HasColor)
            {
                ditherColorLine(line,span.x0,span.x1,span.y,span.col0,span.col1);
            }
        }

        @nogc void fillTile(int TileWidth, int TileHeight,T)(in T extPack, int x0, int y0, int x1, int y1) nothrow
        {
            TileT tile0 = TileT(&extPack,x0,y0);
            TileT tile1 = tile0;
            tile1.incY(TileHeight);
            PosT[3] bary0 = void;
            PosT[3] bary1 = void;
            tile0.getBarycentric(bary0);
            tile1.getBarycentric(bary1);
            static if(HasColor)
            {
                ColT[TileHeight] cols0 = void;
                ColT[TileHeight] cols1 = void;
                {
                    const col0 = calcColor(bary0);
                    const col1 = calcColor(bary1);
                    ColT.interpolateLine!TileHeight(cols1[],col0,col1);
                }
            }
            enum xMask = ~(TileWidth - 1);
            for(auto x = x0; x < x1; x = (x + TileWidth) & xMask)
            {
                cols0 = cols1;

                tile0.incX(TileWidth);
                tile1.incX(TileWidth);
                tile0.getBarycentric(bary0);
                tile1.getBarycentric(bary1);
                static if(HasColor)
                {
                    const col0 = calcColor(bary0);
                    const col1 = calcColor(bary1);
                    ColT.interpolateLine!TileHeight(cols1[],col0,col1);
                }
                auto line = mBitmap[y0];
                foreach(y;y0..y1)
                {
                    //const ny = y % TileHeight;
                    //static if(HasColor) ditherColorLine(line,x,x + TileWidth,y,cols0[ny],cols1[ny]);
                    SpanT span = {x0:x,x1:x + TileWidth, y:y};
                    static if(HasColor)
                    {
                        const ny = y % TileHeight;
                        span.col0 = cols0[ny];
                        span.col1 = cols1[ny];
                    }
                    drawSpan(line,span);
                    ++line;
                }
            }
        }

        @nogc void drawTile(int TileWidth, int TileHeight,T)(in T extPack, int x0, int y0, int x1, int y1) nothrow
        {
            TileT tile = TileT(&extPack,x0,y0);
            auto line = mBitmap[y0];
            foreach(y;y0..y1)
            {
                static if(HasColor)
                {
                    ColT col0 = void;
                    ColT col1 = void;
                }
                int xStart = x1;
                foreach(x;x0..x1)
                {
                    if(tile.all)
                    {
                        static if(HasColor)
                        {
                            PosT bary[3] = void;
                            tile.getBarycentric(bary);
                            col0 = calcColor(bary);
                        }
                        xStart = x;
                        break;
                    }
                    tile.incX(1);
                }
                tile.incX(x1 - xStart - 1);
                int xEnd = x1;
                foreach_reverse(x;xStart..x1)
                {
                    if(tile.all)
                    {
                        xEnd = x + 1;
                        break;
                    }
                    tile.incX(-1);
                }
                static if(HasColor)
                {
                    PosT bary[3] = void;
                    tile.getBarycentric(bary);
                    col1 = calcColor(bary);
                }
                assert(xStart >= x0);
                assert(xEnd   <= x1);
                
                if(xEnd > xStart)
                {
                    enum xMask = ~(TileWidth - 1);
                    const xFullStart = (xStart + TileWidth) & xMask;
                    const xFullEnd   = xEnd & xMask;
                    if((xFullEnd - xFullStart) > -TileWidth)
                    {
                        tile.incX(xFullStart - xEnd);
                        tile.getBarycentric(bary);
                        SpanT span = {x0:xStart,x1:xFullStart, y:y};
                        static if(HasColor)
                        {
                            ColT col = calcColor(bary);
                            //ditherColorLine(line,xStart,xFullStart,y,col0,col);
                            span.col0 = col0;
                            span.col1 = col;
                        }
                        drawSpan(line,span);
                        for(int x = xFullStart; x < xFullEnd; x += TileWidth)
                        {
                            tile.incX(TileWidth);
                            tile.getBarycentric(bary);
                            SpanT span = {x0:x,x1:x + TileWidth, y:y};
                            static if(HasColor)
                            {
                                col0 = col;
                                col = calcColor(bary);
                                ditherColorLine(line,x,x + TileWidth,y,col0,col);
                            }
                        }
                        static if(HasColor) ditherColorLine(line,xFullEnd,xEnd,y,col,col1);
                    }
                    else
                    {
                        static if(HasColor) ditherColorLine(line,xStart,xEnd,y,col0,col1);
                    }
                }
                tile.incY(1);
                ++line;
            }
        }

        void drawArea(int TileWidth, int TileHeight,T)(in T extPack, int tx0,int ty0, int tx1, int ty1) nothrow
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
                    const y1 = y0 + TileHeight;
                    //first patrially covered iterations
                    int txStartFull = tx1;
                    foreach(tx;txStart..tx1)
                    {
                        //mBitmap[y0][tx*TileWidth] = ColorRed;
                        if(all(c))
                        {
                            //fully covered
                            txStartFull = tx;
                            break;
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
                    {
                        const x0 = txStart     * TileWidth;
                        const x1 = txStartFull * TileWidth;
                        drawTile!(TileWidth,TileHeight)(extPack,x0,y0,x1,y1);
                    }
                    if(txStartFull < tx1)
                    {
                        int txStartFullEnd = tx1;
                        //full covered iterations
                        foreach(tx;txStartFull..tx1)
                        {
                            //mBitmap[y0][tx*TileWidth] = ColorGreen;
                            if(!all(c))
                            {
                                txStartFullEnd = tx;
                                break;
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
                        {
                            const x0 = txStartFull    * TileWidth;
                            const x1 = txStartFullEnd * TileWidth;
                            fillTile!(TileWidth,TileHeight)(extPack,x0,y0,x1,y1);
                        }

                        int txEnd = tx1;
                        foreach(tx;txStartFullEnd..tx1)
                        {
                            //mBitmap[y0][tx*TileWidth] = ColorBlue;
                            assert(!all(c));
                            if(none(c))
                            {
                                txEnd = tx;
                                break;
                            }
                            pack0.incX(TileWidth);
                            pack1.incX(TileWidth);
                            c >>= 6;
                            c |= (pack0.check << 6);
                            c |= (pack1.check << 9);
                        }
                        if(txStartFullEnd < txEnd)
                        {
                            const x0 = txStartFullEnd * TileWidth;
                            const x1 = txEnd          * TileWidth;
                            drawTile!(TileWidth,TileHeight)(extPack,x0,y0,x1,y1);
                        }
                    }
                }
                else //LastLevel
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
        void clipArea(int TileWidth, int TileHeight)() nothrow
        {
            const minTx =  minX / TileWidth;
            const maxTx = (maxX + TileWidth - 1) / TileWidth;
            const minTy =  minY / TileHeight;
            const maxTy = (maxY + TileHeight - 1) / TileHeight;
            auto pack = PackT(pverts[0], pverts[1], pverts[2]);
            drawArea!(TileWidth,TileHeight)(pack,minTx,minTy,maxTx,maxTy);
        }
        clipArea!(MaxTileWidth,MaxTileHeight)();
        //end
    }
}