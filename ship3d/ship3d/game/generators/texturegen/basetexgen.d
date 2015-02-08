module game .generators.basetexgen;

import std.array;
import std.algorithm;
import std.range;

import game.units;
import game.topology.room;
import game.topology.polygon;

struct Point
{
    vec3_t pos;
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
        auto r = p.indices[].cycle;
        edges = zip(r, r.dropOne).map!(a => Edge(&this,null,a[0],a[1],0,0)).take(p.indices[].length).array;
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
        auto points = room.vertices[].map!(a => Point(a.pos,a.tpos)).array;
        app.put(room.polygons[].filter!(a => !a.isPortal).map!((ref a) => Poly(points,&a)));
    }
    auto ret = app.data;
    Poly*[Polygon*] mapping;
    foreach(ref p;ret[])
    {
        mapping[p.src] = &p;
    }
    foreach(ref p;ret[])
    {
        foreach(a;p.src.adjacentPolys)
        {
            if(!a.isPortal)
            {
            }
            else
            {
            }
        }
    }
    return ret;
}

class BaseTexGen
{
public:
    this()
    {
    }
private:
}