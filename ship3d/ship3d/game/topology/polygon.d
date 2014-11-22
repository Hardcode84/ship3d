module game.topology.polygon;

import game.units;
import game.topology.room;

import game.renderer.rasterizer2;

struct Polygon
{
    Room               mRoom = null;
    const(Polygon)*    mConnection = null;
    //const(Polygon)*[4] mAdjasent = null;
    immutable(int)[]   mIndices;
    //vec4_t             mNormal;
    texture_t          mTexture;

pure nothrow:
    this(in int[] indices)
    {
        assert(indices.length % 3 == 0);
        mIndices = indices.idup;
    }

    @property bool isPortal() const { return mConnection != null; }
    @property auto indices()  inout { return mIndices[]; }
    @property auto room()     inout { return mRoom; }

    void draw(T)(auto ref T renderer, in Vertex[] transformedVerts, in vec3_t pos, in quat_t dir) const
    {
        //debugOut("polygon.draw");
        struct Context
        {
            const(texture_t) texture;
        }
        Context ctx = {texture: mTexture};
        if(isPortal)
        {
            assert(false);
        }
        else
        {
            renderer.drawIndexedTriangle!Rasterizer2(ctx, transformedVerts[], mIndices[]);
        }
    }
}

