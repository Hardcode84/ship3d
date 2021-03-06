﻿module game.renderer.rasterizerhp;

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

struct RasterizerHP(BitmapT,TextureT,DepthT = void)
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
    enum TreeCoeff = 2;
    enum MinTreeTileWidth = 64;
    enum MinTreeTileHeight = 64;

    struct Line(PosT,bool Affine)
    {
    @nogc:
        immutable PosT x1, y1;
        immutable PosT dx, dy, c;
        /*immutable FixedPoint!(28,4,int) x1, y1;
        immutable FixedPoint!(28,4,int) invDenom;
        immutable FixedPoint!(28,4,int) dx, dy, c;*/
        PosT cx, cy;

        this(VT)(in VT v1, in VT v2, int minX, int minY, PosT baryInvDenom) pure nothrow
        {
            x1 = v1.pos.x;
            const x2 = v2.pos.x;
            y1 = v1.pos.y;
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

        void incX() pure nothrow
        {
            cx -= dy;
        }

        void incY() pure nothrow
        {
            cy += dx;
            cx = cy;
        }

        auto val(int x, int y) const pure nothrow
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
        }

        @property auto curr() const pure nothrow { return cx; }

        @property auto barycentric(int x, int y) const pure nothrow
        {
            return c + dx * y - dy * x;
        }
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
            static if(!Affine)
            {
                w = [cast(PosT)v1.pos.w, cast(PosT)v2.pos.w, cast(PosT)v3.pos.w];
            }
        }

        void incX() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                lines[i].incX();
            }
        }

        void incY() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                lines[i].incY();
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

        void getBarycentric(int x, int y, PosT[] ret) const pure nothrow
        in
        {
            assert(ret.length == NumLines);
        }
        out
        {
            //assert(almost_equal(cast(PosT)1, ret.reduce!"a + b", 1.0f/255.0f), debugConv(ret.reduce!"a + b"));
        }
        body
        {
            foreach(i;TupleRange!(1,NumLines))
            {
                ret[i] = lines[(i + 1) % NumLines].barycentric(x,y);
            }
            ret[0] = cast(PosT)1 - ret[1] - ret[2];
            static if(!Affine)
            {
                PosT sw = ret[0] / w[0];
                foreach(i;TupleRange!(1,NumLines))
                {
                    sw += (ret[i] / w[i]);
                }
                foreach(i;TupleRange!(1,NumLines))
                {
                    ret[i] = ret[i] / (sw * w[i]);
                }
                ret[0] = cast(PosT)1 - ret[1] - ret[2];
            }
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

        auto pack = PackT(pverts[0], pverts[1], pverts[2], minX, minY);

        @nogc void drawTile(bool Fill = false)(int TileWidth, int TileHeight, int x0, int y0)
        {
            assert(TileWidth > 0);
            assert(TileHeight > 0);
            assert(0 == x0 % TileWidth);
            assert(0 == y0 % TileHeight);
            assert(x0 >= 0, debugConv(x0));
            assert(y0 >= 0, debugConv(y0));
            const x1 = min(maxX,x0 + TileWidth);
            const y1 = min(maxY,y0 + TileHeight);
            //assert(x1 < (maxX + TileWidth),  debugConv(x1)~" "~debugConv(maxX));
            //assert(y1 < (maxY + TileHeight), debugConv(y1)~" "~debugConv(maxY));
            static if(Fill)
            {
                auto tile = TileT(pack,pverts,x0,y0);
            }
            for(auto y = y0; y < y1; y += MinTileHeight)
            {
                static if(Fill) tile.incY(pack);
                const cy0 = max(minY,y);
                const cy1 = min(maxY,y + MinTileHeight);
                if(cy0 >= cy1) continue;
                for(auto x = x0; x < x1; x += MinTileWidth)
                {
                    static if(Fill) tile.incX(pack);
                    const cx0 = max(minX,x);
                    const cx1 = min(maxX,x + MinTileWidth);
                    if(cx0 >= cx1) continue;
                    @nogc void drawFixedSizeTile(bool Fill, int TileWidth, int TileHeight)(int x0, int y0, int x1, int y1)
                    {
                        auto line = mBitmap[y0];
                        static if(HasColor)
                        {
                            @nogc void fillColorLine(int x0, int x1, int y, in ColT col1, in ColT col2) nothrow
                            {
                                enum W = 8;
                                enum H = 8;
                                immutable ColT[2] cols = [col1, col2];
                                static immutable patterns = [
                                    [0,0,0,0,1,1,1,1],
                                    [0,0,0,1,0,1,1,1],
                                    [0,0,1,0,1,0,1,1],
                                    [0,1,0,1,0,1,0,1],
                                    
                                    [0,0,1,0,1,0,1,1],
                                    [0,1,0,1,0,1,0,1],
                                    [0,0,1,0,1,0,1,1],
                                    [0,0,0,1,0,1,1,1]];
                                static assert(patterns.length    == H);
                                static assert(patterns[0].length == W);
                                const p = patterns[y % H];
                                auto l = line[x0..x1];
                                foreach(x;0..l.length)
                                {
                                    const xw = x % W;
                                    l[x] = cols[p[xw]];
                                }
                                //ColT.interpolateLine!H(line[x0..x1],col1,col2);
                            }
                        }
                        static if(Fill)
                        {
                            foreach(y;y0..y1)
                            {
                                static if(HasColor)
                                {
                                    const col1 = tile.cols0[y % TileHeight];
                                    const col2 = tile.cols1[y % TileHeight];
                                    fillColorLine(x0, x1, y, col1,col2);
                                }
                                ++line;
                            }
                        }
                        else
                        {
                            auto pck = pack;
                            pck.setXY(x0,y0);
                            foreach(y;y0..y1)
                            {
                                int xStart = x1;
                                foreach(x;x0..x1)
                                {
                                    if(pck.check())
                                    {
                                        xStart = x;
                                        break;
                                    }
                                    pck.incX();
                                }
                                pck.incX();
                                int xEnd = x1;
                                foreach(x;(xStart + 1)..x1)
                                {
                                    if(!pck.check())
                                    {
                                        xEnd = x;
                                        break;
                                    }
                                    pck.incX();
                                }
                                //assert(xStart >= x0);
                                //assert(xEnd   <= x1);
                                
                                if(xEnd > xStart)
                                {
                                    static if(HasColor)
                                    {
                                        auto calcColor(int xt)
                                        {
                                            PosT[3] bary = void;
                                            pck.getBarycentric(xt,y, bary);
                                            ColT[3] colors = void;
                                            colors[0] = pverts[0].color * bary[0];
                                            colors[1] = pverts[1].color * bary[1];
                                            colors[2] = pverts[2].color * bary[2];
                                            return colors[0] + colors[1] + colors[2];
                                        }
                                        const col1 = calcColor(xStart);
                                        const col2 = calcColor(xEnd - 1);
                                        //ColT.interpolateLine(xEnd-xStart,line[xStart..xEnd],col1,col2);
                                        //line[xStart..xEnd] = ColorRed;
                                        fillColorLine(xStart,xEnd,y,col1,col2);
                                    }
                                }
                                pck.incY();
                                ++line;
                            }
                        }
                    }
                    drawFixedSizeTile!(Fill,MinTileWidth,MinTileHeight)(cx0,cy0,cx1,cy1);
                }
            }
        }

        @nogc void fillTile(int TileWidth, int TileHeight, int x0, int y0)
        {
            drawTile!true(TileWidth, TileHeight, x0, y0);
        }

        @nogc void drawAreaLevel(int TileWidth, int TileHeight)(int tx0, int ty0, int tx1, int ty1) nothrow
        {
            static assert(TileWidth  >= MinTileWidth);
            static assert(TileHeight >= MinTileHeight);
            enum FinalLevel = (TileWidth == MinTileWidth && TileHeight == MinTileHeight);
            auto yt0 = ty0 * TileHeight;
            foreach(ty;ty0..ty1)
            {
                if(yt0 >= maxY) break;
                const yt1 = yt0 + TileHeight;
                scope(exit) yt0 = yt1;
                auto xt0 = tx0 * TileWidth;
                foreach(tx;tx0..tx1)
                {
                    if(xt0 >= maxX) break;
                    const xt1 = xt0 + TileWidth;
                    scope(exit) xt0 = xt1;
                    const res = pack.testTile(xt0, yt0, xt1, yt1);
                    if((0 == (res & 0xf)) || (0 == (res & 0xf0)) || (0 == (res & 0xf00)))
                    {
                        //uncovered
                        continue;
                    }
                    else if(0xfff == res)
                    {
                        //completely covered
                        fillTile(TileWidth, TileHeight, xt0, yt0);
                    }
                    else
                    {
                        //patrially covered
                        static if(!FinalLevel)
                        {
                            enum Coeff = TreeCoeff;
                            enum NextTileWidth  = TileWidth  / Coeff;
                            enum NextTileHeight = TileHeight / Coeff;
                            static assert(NextTileWidth  >= MinTileWidth);
                            static assert(NextTileHeight >= MinTileHeight);
                            const ntx0 = tx * Coeff;
                            const nty0 = ty * Coeff;
                            const ntx1 = ntx0 + Coeff;
                            const nty1 = nty0 + Coeff;
                            drawAreaLevel!(NextTileWidth, NextTileHeight)(ntx0, nty0, ntx1, nty1);
                        }
                        else
                        {
                            drawTile(TileWidth, TileHeight, xt0, yt0);
                        }
                    }
                }
            }
        }

        @nogc void clipAreaLevel(int TileWidth, int TileHeight)(int x0, int y0, int x1, int y1)
        {
            const tx0 = x0 / TileWidth;
            const tx1 = (x1 + TileWidth - 1) / TileWidth;
            const ty0 = y0 / TileHeight;
            const ty1 = (y1 + TileHeight - 1) / TileHeight;
            drawAreaLevel!(TileWidth, TileHeight)(tx0,ty0,tx1,ty1);
        }

        clipAreaLevel!(MinTreeTileWidth,MinTreeTileHeight)(minX,minY,maxX,maxY);
        //
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
        //end
    }
}