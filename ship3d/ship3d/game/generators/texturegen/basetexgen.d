module game .generators.basetexgen;

import game.units;
import game.topology.room;
import game.topology.polygon;

struct Point
{
    vec2_t pos;
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
    uint data;
    Point[] points;
    Edge[] edges;
    Polygon* src;
}

class BaseTexGen
{
public:
    this()
    {
    }
private:
}