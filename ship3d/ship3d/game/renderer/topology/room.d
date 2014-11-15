module game.renderer.topology.room;

import game.units;
import game.renderer.topology.polygon;

final class Room
{
private:
    Vertex[]  mVertices;
    Polygon[] mPolygons;
public:
    this()
    {
        // Constructor code
    }

    void draw(T)(auto ref T renderer) const pure nothrow
    {
        foreach(const ref p; mPolygons)
        {
            p.draw(renderer);
        }
    }
}

