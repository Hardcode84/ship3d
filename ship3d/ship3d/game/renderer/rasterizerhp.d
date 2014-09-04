﻿module game.renderer.rasterizerhp;

import std.traits;
import std.algorithm;

import gamelib.util;

import game.units;

struct RasterizerHP(BitmapT,TextureT)
{
private:
    BitmapT mBitmap;
    TextureT mTexture;
    Rect mClipRect;

    enum MinTileWidth  = 16;
    enum MinTileHeight = 16;
    enum MaxTileWidth  = 2048;
    enum MaxTileHeight = 2048;

    struct Line(PosT)
    {
        immutable PosT dx, dy, c;
        PosT cx, cy;
        this(VT)(in VT v1, in VT v2, int minX, int minY) pure nothrow
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            dx = x2 - x1;
            dy = y2 - y1;
            c = (dy * x1 - dx * y1);
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
    }

    struct LinesPack(LineT)
    {
        LineT[3] lines;
        this(VT)(in VT v1, in VT v2, in VT v3, int minX, int minY) pure nothrow
        {
            lines = [LineT(v1, v2, minX, minY),LineT(v2, v3, minX, minY),LineT(v3, v1, minX, minY)];
        }

        void incX(int val) pure nothrow
        {
            foreach(ref line;lines)
            {
                line.incX(val);
            }
        }

        void incY(int val) pure nothrow
        {
            foreach(ref line;lines)
            {
                line.incY(val);
            }
        }

        void setXY(int x, int y) pure nothrow
        {
            foreach(ref line;lines)
            {
                line.setXY(x, y);
            }
        }

        auto check() const pure nothrow
        {
            return all!"a.curr > 0"(lines[]);
        }

        auto testTile(int x1, int y1, int x2, int y2) const pure nothrow
        {
            uint res = 0;
            foreach(i,ref line;lines)
            {
                res |= (line.testTile(x1,y1,x2,y2) << (4 * i));
            }
            return res;
        }
    }

    struct Tile(int W, int H, PosT)
    {
        immutable int x0, x1;
        immutable int y0, y1;
        this(int i)
        {
        }
    }
public:
    this(BitmapT b)
    {
        assert(b !is null);
        b.lock();
        mBitmap = b;
        mClipRect = Rect(0, 0, mBitmap.width, mBitmap.height);
    }
    
    ~this()
    {
        mBitmap.unlock();
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
    
    void drawIndexedTriangle(bool HasTextures = false, bool HasColor = true,VertT,IndT)(in VertT[] verts, in IndT[3] indices) if(isIntegral!IndT)
    {
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        //sort!("a.pos.y < b.pos.y")(pverts[0..$]);
        
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
    private void drawTriangle(bool HasTextures, bool HasColor,bool Affine,VertT)(in VertT[3] pverts)
    {
        static assert(HasTextures != HasColor);
        alias PosT = Unqual!(typeof(VertT.pos.x));
        static if(HasColor)
        {
            alias ColT = Unqual!(typeof(VertT.color));
        }
        else
        {
            alias ColT = void;
        }
        alias LineT = Line!(PosT);
        alias PackT = LinesPack!(LineT);

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        //debugOut(minX);
        //debugOut(maxX);
        //debugOut(minY);
        //debugOut(maxY);

        //auto line = mBitmap[minY];

        auto pack = PackT(pverts[0], pverts[1], pverts[2], minX, minY);

        void drawArea(int TileWidth, int TileHeight)(int x0, int y0, uint abc)
        {
            if(0x0 == abc)
            {
                //uncovered
                return;
            }
            else if(0xfff == abc)
            {
                //completely covered
                auto line = mBitmap[y0];
                foreach(y;y0..(x0 + TileHeight))
                {
                    foreach(x;x0..(x0 + TileWidth))
                    {
                        line[x] = ColorRed;
                    }
                    ++line;
                }
            }
            else
            {
                //patrially covered
                static if(TileWidth == MinTileWidth && TileHeight == MinTileHeight)
                {
                    pack.setXY(x0,y0);
                    auto line = mBitmap[y0];
                    foreach(y;y0..(y0 + TileHeight))
                    {
                        foreach(x;x0..(x0 + TileWidth))
                        {
                            if(pack.check())
                            {
                                line[x] = ColorGreen;
                            }
                            pack.incX(1);
                        }
                        pack.incY(1);
                        ++line;
                    }
                }
                else
                {
                    enum NewTileWidth  = TileWidth / 2;
                    enum NewTileHeight = TileHeight / 2;
                    const x1 = x0 + NewTileWidth;
                    const y1 = y0 + NewTileHeight;
                    const x2 = x1 + NewTileWidth;
                    const y2 = y1 + NewTileHeight;
                    const abc00 = pack.testTile(x0,y0,x1,y1);
                    const abc10 = pack.testTile(x1,y0,x2,y1);
                    const abc01 = pack.testTile(x0,y1,x1,y2);
                    const abc11 = pack.testTile(x1,y1,x2,y2);
                    drawArea!(NewTileWidth, NewTileHeight)(x0,y0,abc00);
                    drawArea!(NewTileWidth, NewTileHeight)(x1,y0,abc10);
                    drawArea!(NewTileWidth, NewTileHeight)(x0,y1,abc01);
                    drawArea!(NewTileWidth, NewTileHeight)(x1,y1,abc11);
                }
            }
        }

        void clipArea(int TileWidth, int TileHeight)(int x0, int y0)
        {
            static if(TileWidth == MinTileWidth && TileHeight == MinTileHeight)
            {
                const abc = pack.testTile(x0,y0,x0 + TileWidth,y0 + TileHeight);
                drawArea!(TileWidth, TileHeight)(x0, y0, abc);
            }
            else
            {
                const minTx = minX / TileWidth;
                const maxTx = maxX / TileWidth;
                const minTy = minY / TileHeight;
                const maxTy = maxY / TileHeight;
                const dTx = maxTx - minTx;
                const dTy = maxTy - minTy;
                if(dTx > 0 || dTy > 0)
                {
                    const abc = pack.testTile(x0,y0,x0 + TileWidth,y0 + TileHeight);
                    drawArea!(TileWidth,TileHeight)(x0, y0,abc);
                }
                else
                {
                    enum HalfTileWidth  = TileWidth / 2;
                    enum HalfTileHeight = TileHeight / 2;
                    clipArea!(HalfTileWidth, HalfTileHeight)(minTx * HalfTileWidth, minTy * HalfTileHeight);
                }
            }
        }

        clipArea!(MaxTileWidth,MaxTileHeight)(0,0);

        //const abc = pack.testTile(0,0,2048,2048);
        //drawArea!(2048,2048)(0,0,abc);

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
                if(0x0 == res) continue;

                if(0xfff == res)
                {
                    //completely covered
                    auto line = mBitmap[y0];
                    foreach(y;y0..y1)
                    {
                        foreach(x;x0..x1)
                        {
                            line[x] = ColorRed;
                        }
                        ++line;
                    }
                }
                else
                {
                    //patrially covered
                    pack.setXY(x0,y0);
                    auto line = mBitmap[y0];
                    foreach(y;y0..y1)
                    {
                        foreach(x;x0..x1)
                        {
                            if(pack.check())
                            {
                                line[x] = ColorGreen;
                            }
                            pack.incX(1);
                        }
                        pack.incY(1);
                        ++line;
                    }
                }
            }
        }*/
    }
}