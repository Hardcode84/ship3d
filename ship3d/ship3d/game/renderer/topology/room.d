module game.renderer.topology.room;

import game.units;
import game.renderer.topology.polygon;

final class Room
{
private:
    Vertex[]  mVertices;
    Polygon[] mPortals;
    Polygon[] mWalls;
public:
    this()
    {
        // Constructor code
    }

    void draw(T)(auto ref T renderer) const pure nothrow
    {
        foreach(const ref p; mPortals)
        {
            p.draw(renderer);
        }
        foreach(const ref p; mWalls)
        {
            p.draw(renderer);
        }
    }
}

