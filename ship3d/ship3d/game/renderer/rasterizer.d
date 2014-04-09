module game.renderer.rasterizer;

import std.traits;
import std.algorithm;

import gamelib.util;

import game.units;

struct Rasterizer(BitmapT,TextureT)
{
private:
    BitmapT mBitmap;
    TextureT mTexture;
    Rect mClipRect;
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

    void drawIndexedTriangle(VertT,IndT)(in VertT[] verts, in IndT[3] indices) if(isIntegral!IndT)
    {
        alias PosT = typeof(VertT.pos.x);
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        sort!("a.pos.y < b.pos.y")(pverts[0..$]);

        const e1xdiff = pverts[0].pos.x - pverts[2].pos.x;
        const e2xdiff = pverts[0].pos.x - pverts[1].pos.x;

        const e1ydiff = pverts[0].pos.y - pverts[2].pos.y;
        const e2ydiff = pverts[0].pos.y - pverts[1].pos.y;

        struct Edge
        {
        private:
            PosT factor;
            immutable PosT factorStep;
            immutable PosT xStart;
            immutable PosT xDiff;
        public:
            this(VT)(in VT v1, in VT v2, int inc) pure nothrow
            {
                const ydiff = v1.pos.y - v2.pos.y;
                factorStep = 1 / ydiff;
                factor = factorStep * inc;
                xStart = v1.pos.x;
                xDiff = v1.pos.x - v2.pos.x;
            }

            @property auto x() const pure nothrow { return xStart + xDiff * factor; }
            ref auto opUnary(string op: "++")() pure nothrow { factor += factorStep; return this; }
        }

        const bool spanDir = ((e1xdiff / e1ydiff) * e2ydiff) < e2xdiff;

        auto minY = cast(int)pverts[0].pos.y;
        auto midY = cast(int)pverts[1].pos.y;
        auto maxY = cast(int)pverts[2].pos.y;

        const minYinc = max(0, mClipRect.y - minY);
        const midYinc = max(0, mClipRect.y - midY);
        minY += minYinc;
        midY += midYinc;
        maxY = min(maxY, mClipRect.y + mClipRect.h);
        if(minY >= maxY) return;
        midY = min(midY, maxY);

        auto edge1 = Edge(pverts[0], pverts[2], minYinc);

        auto line = mBitmap[minY];

        foreach(i;TupleRange!(0,2))
        {
            static if(0 == i)
            {
                const yStart  = minY;
                const yEnd    = midY;
                auto edge2 = Edge(pverts[0], pverts[1], minYinc);
            }
            else
            {
                const yStart  = midY;
                const yEnd    = maxY;
                auto edge2 = Edge(pverts[1], pverts[2], midYinc);
            }

            foreach(y;yStart..yEnd)
            {
                auto x1 = cast(int)edge1.x;
                auto x2 = cast(int)edge2.x;
                if(spanDir) swap(x1, x2);

                const x1inc = max(0, mClipRect.x - x1);
                x1 += x1inc;
                x2 = min(x2, mClipRect.x + mClipRect.w);

                drawSpan(line, x1, x2);
                ++edge1;
                ++edge2;
                ++line;
            }
        }
    }
    private void drawSpan(LineT)(auto ref LineT line, int x1, int x2)
    {
        if(x1 >= x2) return;
        line[x1..x2] = ColorRed;
        /*foreach(x;x1..x2)
        {
        }*/
    }
}

