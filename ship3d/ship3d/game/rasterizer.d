module game.rasterizer;

import std.traits;
import std.algorithm;

import game.units;

struct Rasterizer(BitmapT)
{
    BitmapT mBitmap;
    this(BitmapT b)
    {
        b.lock();
        mBitmap = b;
    }

    ~this()
    {
        mBitmap.unlock();
    }

    /*private struct Edge
    {
        const(Vertex)* v1, v2;
    }
    private struct Span
    {
    }*/
    void drawTriangle(in Vertex[3] verts)
    {
        const(Vertex)*[3] pverts;
        foreach(i,ref v; verts) pverts[i] = verts.ptr + i;
        sort!("a.pos.y < b.pos.y")(pverts[0..$]);
        //drawSpansBetweenEdges(Edge(pverts[0],pverts[2]),Edge(pverts[0], pverts[1]));
        //drawSpansBetweenEdges(Edge(pverts[0],pverts[2]),Edge(pverts[1], pverts[2]));

        const e1xdiff = pverts[0].pos.x - pverts[2].pos.x;
        const e2xdiff = pverts[0].pos.x - pverts[1].pos.x;
        const e3xdiff = pverts[1].pos.x - pverts[2].pos.x;

        const e1ydiff = pverts[0].pos.y - pverts[2].pos.y;
        const e2ydiff = pverts[0].pos.y - pverts[1].pos.y;
        const e3ydiff = pverts[1].pos.y - pverts[2].pos.y;

        const bool spanDir = ((e1xdiff / e1ydiff) * e2ydiff) < e2xdiff;

        const minY = cast(int)pverts[0].pos.y;
        const midY = cast(int)pverts[1].pos.y;
        const maxY = cast(int)pverts[2].pos.y;

        const factor1step = 1 / e1ydiff;
        Unqual!(typeof(factor1step)) factor1 = 0;
        auto factor2step = 1 / e2ydiff;
        Unqual!(typeof(factor2step)) factor2 = 0;

        auto line = mBitmap[minY];
        foreach(y;minY..midY)
        {
            auto x1 = cast(int)(pverts[0].pos.x + e1xdiff * factor1);
            auto x2 = cast(int)(pverts[0].pos.x + e2xdiff * factor2);
            if(spanDir) swap(x1, x2);
            drawSpan(line, x1, x2);
            factor1 += factor1step;
            factor2 += factor2step;
            ++line;
        }
        factor2step = 1 / e3ydiff;
        factor2 = 0;
        foreach(y;midY..maxY)
        {
            auto x1 = cast(int)(pverts[0].pos.x + e1xdiff * factor1);
            auto x2 = cast(int)(pverts[1].pos.x + e3xdiff * factor2);
            if(spanDir) swap(x1, x2);
            drawSpan(line, x1, x2);
            factor1 += factor1step;
            factor2 += factor2step;
            ++line;
        }
    }
    private void drawSpan(LineT)(auto ref LineT line, int x1, int x2)
    {
        assert(x2 >= x1);
        line[x1..x2] = ColorRed;
        /*foreach(x;x1..x2)
        {
        }*/
    }
    /*private void drawSpansBetweenEdges(in Edge e1, in Edge e2) pure nothrow
    {
        const e1xdiff = e1.v2.pos.x -  e1.v1.pos.x;
        const e2xdiff = e2.v2.pos.x -  e2.v1.pos.x;

        const e1ydiff = e1.v2.pos.y - e1.v1.pos.y;
        const e2ydiff = e2.v2.pos.y - e2.v1.pos.y;

        const factor1step = 1 / e1ydiff;
        auto factor1 = (e2.v1.pos.y - e1.v1.pos.y) * factor1step;
        const factor2step = 1 / e2ydiff;
        auto factor2 = cast(typeof(factor1))0;

        const minY = cast(int)e2.v1.pos.y;
        const maxY = cast(int)e2.v2.pos.y;
        foreach(y;minY..maxY)
        {
            factor1 += factor1step;
            factor2 += factor2step;
        }
    }*/
}

