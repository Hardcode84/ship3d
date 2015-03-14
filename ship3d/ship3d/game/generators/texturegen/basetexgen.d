module game .generators.basetexgen;

import std.array;
import std.algorithm;
import std.range;

import gamelib.range;

import game.units;
import game.topology.room;
import game.topology.polygon;

struct Point
{
    //vec3_t pos;
    vec2_t tpos;
}

struct Edge
{
    Poly* poly;
    Edge* connection;
    int i1, i2;     //index
    int ci1, ci2;   //connection index
}

struct Poly
{
    Point[] points;
    Edge[] edges;
    Polygon* src;
    this(Point[] pts, Polygon* p)
    {
        points = pts;
        src = p;
        edges = p.indices[].cycle.adjacent.map!(a => Edge(&this,null,a[0],a[1],0,0)).take(p.indices[].length).array;
    }
    this(this)
    {
        edges = edges[].map!(a => Edge(&this,a.connection,a.i1,a.i2,a.ci1,a.ci2)).array;
    }
}

Poly[] createTopology(Room[] rooms)
{
    auto app = appender!(Poly[]);
    app.reserve(rooms[].map!(a => a.polygons[]).joiner.filter!(a => !a.isPortal).count);
    foreach(room;rooms[])
    {
        auto points = room.vertices[].map!(a => Point(/*a.pos,*/a.tpos)).array;
        app.put(room.polygons[].filter!(a => !a.isPortal).map!((ref a) => Poly(points,&a)));
    }
    auto ret = app.data;
    Poly*[Polygon*] mapping;
    foreach(ref p;ret[])
    {
        mapping[p.src] = &p;
    }
    foreach(ref poly;ret[])
    {
        foreach(ref edge;poly.edges)
        {
            foreach(adjPoly,adjInd,adjSrcInd;lockstep(poly.src.adjacentPolys,poly.src.adjacentIndices,poly.src.adjacentSrcIndices))
            {
                if(tuple(edge.i1,edge.i2) != adjSrcInd && tuple(edge.i2,edge.i1) != adjSrcInd) continue;
                if(!adjPoly.isPortal)
                {
                    auto poly1 = mapping[adjPoly];
                    assert(poly1 !is null);
                    edge.connection = poly1.edges.map!((ref a) => &a).find!((a,b) => (tuple(a.i1,a.i2) == b || tuple(a.i2,a.i1) == b))(adjInd).front;
                    edge.ci1 = adjInd[0];
                    edge.ci2 = adjInd[1];
                }
                else
                {
                    assert(adjPoly.adjacentIndices.length == adjPoly.connectionIndices.length);
                    //foreach(adjConPoly,adjSrcInd,adjInd;lockstep(adjPoly.connectionAdjacent,
                }
                break;
            }
        }
    }
    return ret;
}
