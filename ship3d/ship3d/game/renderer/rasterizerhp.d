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

    enum TileWidth  = 8;
    enum TileHeight = 8;

    struct Line(PosT)
    {
        immutable PosT dx, dy, c;
        PosT cx, cy;
        this(VT)(in VT v1, in VT v2, int minX, int minY)
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            dx = x2 - x1;
            dy = y2 - y1;
            c = (dy * x1 - dx * y1);
            cy = c + dx * minY - dy * minX;
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

        @property auto curr() const pure nothrow { return cx; } 
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

        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);

        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        //debugOut(minX);
        //debugOut(maxX);
        //debugOut(minY);
        //debugOut(maxY);

        auto line = mBitmap[minY];

        auto line1 = LineT(pverts[0], pverts[1], minX, minY);
        auto line2 = LineT(pverts[1], pverts[2], minX, minY);
        auto line3 = LineT(pverts[2], pverts[0], minX, minY);

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

                /*if(line1.curr > 0 &&
                   line2.curr > 0 &&
                   line3.curr > 0)
                {
                    line[x] = ColorRed;
                }*/
                line1.incX(1);
                line2.incX(1);
                line3.incX(1);
            }
            line1.incY(1);
            line2.incY(1);
            line3.incY(1);
            line++;
        }
    }
}