module game.renderer.rasterizertiled3.trianglesplitter;

import std.algorithm;
import std.functional;

import game.units;

import game.renderer.rasterizertiled3.types;

@nogc pure nothrow:
void splitTriangle(alias AreaHandler,VertT)(in VertT[] verts, in Rect boundingRect)
{
    assert(3 == verts.length);
    import gamelib.types: Point;

    const size = Size(boundingRect.w, boundingRect.h);
    auto transformVert(T)(in T v)
    {
        const pos = (v.xy / v.z);
        return Point(
            cast(int)((pos.x * size.w + 0.5f) + size.w / 2),
            cast(int)((pos.y * size.h + 0.5f) + size.h / 2));
    }

    const Point[3] transformed = [
        transformVert(verts[0]),
        transformVert(verts[1]),
        transformVert(verts[2])];

    TriangleArea createArea(in TempEdge e0, in TempEdge e1) @nogc pure
    {
        //debugOut("createArea");
        const minY = max(e0.y0, e1.y0);
        const maxY = min(e0.y1, e1.y1);
        if(minY >= maxY)
        {
            return TriangleArea.init;
        }
        assert(maxY > minY);
        const edge0 = e0.createEdge(minY, maxY);
        const edge1 = e1.createEdge(minY, maxY);
        if(edge0.x0 == edge1.x0)
        {
            if(edge0.x1 < edge1.x1)
            {
                return TriangleArea(edge0, edge1, minY, maxY);
            }
            else if(edge0.x1 > edge1.x1)
            {
                return TriangleArea(edge1, edge0, minY, maxY);
            }
            else
            {
                return TriangleArea.init;
            }
        }
        else
        {
            if(edge0.x0 < edge1.x0)
            {
                return TriangleArea(edge0, edge1, minY, maxY);
            }
            else
            {
                assert(edge0.x0 > edge1.x0);
                return TriangleArea(edge1, edge0, minY, maxY);
            }
        }
        assert(false);
    }

    const minY = boundingRect.y;
    const maxY = boundingRect.y + boundingRect.h;
    if(!isTriangleExternal(verts, size))
    {
        const TempEdge[3] edges = [
            TempEdge(transformed[0],transformed[1], minY, maxY),
            TempEdge(transformed[1],transformed[2], minY, maxY),
            TempEdge(transformed[2],transformed[0], minY, maxY)];

        if(edges[0].valid)
        {
            if(edges[1].valid)
            {
                const area = createArea(edges[0],edges[1]);
                if(area.valid)
                {
                    unaryFun!AreaHandler(area);
                }
            }
            if(edges[2].valid)
            {
                const area = createArea(edges[0],edges[2]);
                if(area.valid)
                {
                    unaryFun!AreaHandler(area);
                }
            }
        }

        if(edges[1].valid && edges[2].valid)
        {
            const area = createArea(edges[1],edges[2]);
            if(area.valid)
            {
                unaryFun!AreaHandler(area);
            }
        }
    }
    else
    {
        /*const HSLine[3] lines = [
        HSLine(verts[indices[0]], verts[(indices[0] + 1) % 3], size),
        HSLine(verts[indices[1]], verts[(indices[1] + 1) % 3], size),
        HSLine(verts[indices[2]], verts[(indices[2] + 1) % 3], size)];*/
        debugOut("external");
    }
}

private:
auto isTriangleExternal(VertT)(in VertT[] verts, in Size size)
{
    assert(3 == verts.length);
    const w1 = verts[0].z;
    const w2 = verts[1].z;
    const w3 = verts[2].z;
    const x1 = verts[0].x;
    const x2 = verts[1].x;
    const x3 = verts[2].x;
    const y1 = verts[0].y;
    const y2 = verts[1].y;
    const y3 = verts[2].y;
    const dw = 0.001f;
    const sizeLim = 100000;
    const bool big = max(
        max(abs(x1 / w1), abs(x2 / w2), abs(x3 / w3)) * size.w,
        max(abs(y1 / w1), abs(y2 / w2), abs(y3 / w3)) * size.h) > sizeLim;
    return big || almost_equal(w1, 0, dw) || almost_equal(w2, 0, dw) || almost_equal(w3, 0, dw) || (w1 * w2 < dw) || (w1 * w3 < dw);
}

struct TempEdge
{
pure nothrow @nogc:
    Point pt0;
    Point pt1;
    int minY;
    int maxY;
    this(T)(in T p0, in T p1, int minY_, int maxY_)
    {
        if(p1.y >= p0.y)
        {
            pt0 = p0;
            pt1 = p1;
        }
        else
        {
            pt0 = p1;
            pt1 = p0;
        }
        minY = minY_;
        maxY = maxY_;
        assert(maxY >= minY);
    }

    @property auto y0() const
    {
        return max(pt0.y, minY);
    }

    @property auto y1() const
    {
        return min(pt1.y, maxY);
    }

    @property auto valid() const
    {
        return y1 > y0;
    }

    auto createEdge(int minY_, int maxY_) const
    {
        assert(maxY_ > minY_);
        assert(minY_ >= minY);
        assert(maxY_ <= maxY);
        const dy = pt1.y - pt0.y;
        assert(dy > 0);
        auto iter = TriangleAreaEdgeIterator(TriangleAreaEdge(pt0.x, pt1.x), dy, pt0.x);
        const dy0 = (minY_ - pt0.y);
        assert(dy0 >= 0);
        iter.incY(dy0);
        const x0 = iter.currx;
        //const err = iter.err;
        const dy1 = maxY_ - minY_;
        assert(dy1 > 0);
        iter.incY(dy1);
        const x1 = iter.currx;
        return TriangleAreaEdge(x0, x1);
    }
}