module game.renderer.topology.polygon;

import game.units;
import game.renderer.topology.room;

struct Polygon
{
    Room*           mRoom;
    const(Polygon)* mConnection = null;
    int[6]          mIndices;
    vec4_t          mNormal;
    texture_t       mtexture;
    /*this()
    {
        // Constructor code
    }*/

    @property bool isPortal() const pure nothrow { return mConnection != null; }

    void draw(T)(auto ref T renderer) const pure nothrow
    {
        if(isPortal)
        {
        }
        else
        {
        }
    }
}

