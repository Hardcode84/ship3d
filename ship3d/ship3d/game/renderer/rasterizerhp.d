module game.renderer.rasterizerhp;

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

        /*void drawArea(int TileWidth, int TileHeight)(in int x0, in int y0, in uint abc)
        {
            if(0x0 == abc)
            {
                //uncovered
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
                    line1.setXY(x0, y0);
                    line2.setXY(x0, y0);
                    line3.setXY(x0, y0);
                    auto line = mBitmap[y0];
                    foreach(y;y0..(y0 + TileHeight))
                    {
                        foreach(x;x0..(x0 + TileWidth))
                        {
                            if(line1.curr > 0 && line2.curr > 0 && line3.curr > 0)
                            {
                                line[x] = ColorGreen;
                            }
                            line1.incX(1);
                            line2.incX(1);
                            line3.incX(1);
                        }
                        line1.incY(1);
                        line2.incY(1);
                        line3.incY(1);
                        ++line;
                    }
                }
                else
                {
                    enum NewTileWidth = TileWidth / 2;
                    enum NewTileHeight = TileHeight / 2;
                    const x1 = x0 + NewTileWidth;
                    const y1 = y0 + NewTileHeight;
                }
            }


            const minTx = minX / TileWidth;
            const maxTx = (maxX + TileWidth - 1) / TileWidth;
            const minTy = minY / TileHeight;
            const maxTy = (maxY + TileHeight - 1) / TileHeight;
            foreach(ty;minTy..maxTy)
            {
                const y0 = (ty + 0) * TileHeight;
                const y1 = (ty + 1) * TileHeight;
                foreach(tx;minTx..maxTx)
                {
                    const x0 = (tx + 0) * TileWidth;
                    const x1 = (tx + 1) * TileWidth;
                    const a = line1.testTile(x0, y0, x1, y1);
                    const b = line2.testTile(x0, y0, x1, y1);
                    const c = line3.testTile(x0, y0, x1, y1);
                    if(0x0 == a && 0x0 == b && 0x0 == c) continue; //uncovered
                    
                    if(0xf == a && 0xf == b && 0xf == c)
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
                        line1.setXY(x0, y0);
                        line2.setXY(x0, y0);
                        line3.setXY(x0, y0);
                        auto line = mBitmap[y0];
                        foreach(y;y0..y1)
                        {
                            foreach(x;x0..x1)
                            {
                                if(line1.curr > 0 && line2.curr > 0 && line3.curr > 0)
                                {
                                    line[x] = ColorGreen;
                                }
                                line1.incX(1);
                                line2.incX(1);
                                line3.incX(1);
                            }
                            line1.incY(1);
                            line2.incY(1);
                            line3.incY(1);
                            ++line;
                        }
                    }
                }
            }
        }*/

        const minTx = minX / MinTileWidth;
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
        }
    }
}