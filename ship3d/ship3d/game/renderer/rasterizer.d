module game.renderer.rasterizer;

import std.traits;
import std.algorithm;

import gamelib.util;

import game.units;

struct Rasterizer(BitmapT)
{
private:
    BitmapT mBitmap;
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
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        sort!("a.pos.y < b.pos.y")(pverts[0..$]);

        const e1xdiff = pverts[0].pos.x - pverts[2].pos.x;
        const e2xdiff = pverts[0].pos.x - pverts[1].pos.x;
        const e3xdiff = pverts[1].pos.x - pverts[2].pos.x;

        const e1ydiff = pverts[0].pos.y - pverts[2].pos.y;
        const e2ydiff = pverts[0].pos.y - pverts[1].pos.y;
        const e3ydiff = pverts[1].pos.y - pverts[2].pos.y;

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

        const factor1step = 1 / e1ydiff;
        auto factor1 = factor1step * minYinc;

        auto line = mBitmap[minY];
        /*import std.stdio;
        writeln();
        writeln(minY);
        writeln(midY);
        writeln(maxY);*/
        foreach(i;TupleRange!(0,2))
        {
            const x1Start = pverts[0].pos.x;
            const x1Diff  = e1xdiff;
            static if(0 == i)
            {
                const factor2step = 1 / e2ydiff;
                auto factor2  = factor2step * minYinc;
                const yStart  = minY;
                const yEnd    = midY;
                const x2Start = pverts[0].pos.x;
                const x2Diff  = e2xdiff;
            }
            else
            {
                const factor2step = 1 / e3ydiff;
                auto factor2  = factor2step * midYinc;
                const yStart  = midY;
                const yEnd    = maxY;
                const x2Start = pverts[1].pos.x;
                const x2Diff  = e3xdiff;
            }

            foreach(y;yStart..yEnd)
            {
                auto x1 = cast(int)(x1Start + x1Diff * factor1);
                auto x2 = cast(int)(x2Start + x2Diff * factor2);
                if(spanDir) swap(x1, x2);

                const x1inc = max(0, mClipRect.x - x1);
                x1 += x1inc;
                x2 = min(x2, mClipRect.x + mClipRect.w);

                drawSpan(line, x1, x2);
                factor1 += factor1step;
                factor2 += factor2step;
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

