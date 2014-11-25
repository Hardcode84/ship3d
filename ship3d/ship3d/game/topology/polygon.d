module game.topology.polygon;

import game.units;
import game.topology.room;

import game.renderer.rasterizer2;
import game.renderer.rasterizerhp5;

struct Polygon
{
    Room               mRoom = null;
    const(Polygon)*    mConnection = null;
    //const(Polygon)*[4] mAdjasent = null;
    immutable(int)[]   mIndices;
    vec3_t[]           mNormals;
    texture_t          mTexture;

//pure nothrow:
    this(in int[] indices)
    {
        assert(indices.length % 3 == 0);
        mIndices = indices.idup;
    }

    @property bool isPortal() const { return mConnection != null; }
    @property auto indices()  inout { return mIndices[]; }
    @property auto room()     inout { return mRoom; }

    void updateNormals()
    {
        //debugOut("updateNormals");
        assert(mIndices.length > 0);
        assert(room !is null);
        const verts = room.vertices;
        mNormals.length = 1;
        foreach(i;0..mIndices.length / 3)
        {
            const i0 = mIndices[i * 3 + 0];
            const i1 = mIndices[i * 3 + 1];
            const i2 = mIndices[i * 3 + 2];
            const normal = cross(verts[i1].pos.xyz - verts[i0].pos.xyz, verts[i2].pos.xyz - verts[i0].pos.xyz).normalized;
            if(0 == i)
            {
                mNormals[0] = normal;
            }
            else
            {
                const d = max(abs(mNormals[0].x - normal.x),abs(mNormals[0].y - normal.y),abs(mNormals[0].z - normal.z));
                if(d > 0.01)
                {
                    mNormals ~= normal;
                }
            }
        }
    }

    bool checkNormals(in quat_t dir) const
    {
        foreach(const ref n;mNormals[])
        {
            if((dir * n).z > 0) return true;
        }
        return false;
    }

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
            renderer.drawIndexedTriangle!RasterizerHP5(ctx, transformedVerts[], mIndices[]);
            //renderer.drawIndexedTriangle!Rasterizer2(ctx, transformedVerts[], mIndices[]);
        }
    }
}

