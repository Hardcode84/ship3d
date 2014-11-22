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

    this(in int[] indices) pure nothrow
    {
        assert(indices.length % 3 == 0);
        mIndices = indices.idup;
    }

    @property bool isPortal() const pure nothrow { return mConnection != null; }

    void draw(T)(auto ref T renderer, in vec3_t pos, in quat_t dir) const pure nothrow
    {
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
            renderer.drawIndexedTriangle!Rasterizer2(ctx, mRoom.vertices, mIndices[]);
        }
    }
}

