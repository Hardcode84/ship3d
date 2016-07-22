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

    bool createArea(in TempEdge e0, in TempEdge e1, ref TriangleArea area) const pure nothrow @nogc
    {
        //debugOut("createArea");
        const minY = max(e0.y0, e1.y0);
        const maxY = min(e0.y1, e1.y1);
        if(minY >= maxY)
        {
            return false;
        }
        assert(maxY > minY);
        const edge0 = e0.createEdge(minY, maxY);
        const edge1 = e1.createEdge(minY, maxY);
        if(edge0.x0 == edge1.x0)
        {
            if(edge0.x1 < edge1.x1)
            {
                area = TriangleArea(edge0, edge1, minY, maxY);
                return true;
            }
            else if(edge0.x1 > edge1.x1)
            {
                area = TriangleArea(edge1, edge0, minY, maxY);
                return true;
            }
            else
            {
                return false;
            }
        }
        else
        {
            if(edge0.x0 < edge1.x0)
            {
                area = TriangleArea(edge0, edge1, minY, maxY);
                return true;
            }
            else
            {
                assert(edge0.x0 > edge1.x0);
                area = TriangleArea(edge1, edge0, minY, maxY);
                return true;
            }
        }
        assert(false);
    }

    const size = Size(boundingRect.w, boundingRect.h);
    if(!isTriangleExternal(verts, size))
    {
        const minY = boundingRect.y;
        const maxY = minY + size.h;

        const float fSizeW = cast(float)size.w;
        const float fSizeH = cast(float)size.h;
        const float halfSizeW = 0.5f + fSizeW / 2.0f;
        const float halfSizeH = 0.5f + fSizeH / 2.0f;
        auto transformVert(T)(in ref T v) const pure nothrow @nogc
        {
            const pos = (v.xy / v.z);
            return Point(
                cast(int)(pos.x * fSizeW + halfSizeW),
                cast(int)(pos.y * fSizeH + halfSizeH));
        }

        const transformed0 = transformVert(verts[0]);
        const transformed1 = transformVert(verts[1]);
        const edge0 = TempEdge(transformed0, transformed1, minY, maxY);
        const transformed2 = transformVert(verts[2]);
        const edge1 = TempEdge(transformed1, transformed2, minY, maxY);
        const edge2 = TempEdge(transformed2, transformed0, minY, maxY);

        TriangleArea[3] areas = void;
        int totalAreas = 0;
        const bool[3] edgesValid = [edge0.valid,edge1.valid,edge2.valid];
        if(edgesValid[0])
        {
            if(edgesValid[1])
            {
                if(createArea(edge0,edge1,areas[totalAreas]))
                {
                    ++totalAreas;
                }
            }
            if(edgesValid[2])
            {
                if(createArea(edge0,edge2,areas[totalAreas]))
                {
                    ++totalAreas;
                }
            }
        }

        if(edgesValid[1] && edgesValid[2])
        {
            if(createArea(edge1,edge2,areas[totalAreas]))
            {
                ++totalAreas;
            }
        }

        foreach(const ref area; areas[0..totalAreas])
        {
            assert(area.valid);
            unaryFun!AreaHandler(area);
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
    enum sizeLim = 100000;
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
    //int minY;
    //int maxY;
    int y0;
    int y1;
    this(T)(in T p0, in T p1, int minY_, int maxY_)
    {
        assert(maxY_ >= minY_);
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
        //minY = minY_;
        //maxY = maxY_;
        y0 = max(pt0.y, minY_);
        y1 = min(pt1.y, maxY_);
    }

    /*@property auto y0() const
    {
        return max(pt0.y, minY);
    }

    @property auto y1() const
    {
        return min(pt1.y, maxY);
    }*/

    @property auto valid() const
    {
        return y1 > y0;
    }

    auto createEdge(int minY_, int maxY_) const
    {
        assert(maxY_ > minY_);
        //assert(minY_ >= minY);
        //assert(maxY_ <= maxY);
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