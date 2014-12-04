module game.topology.polygon;

import game.units;
import game.topology.room;
import game.topology.plane;

import game.renderer.spanmask;
import game.renderer.rasterizerhybrid;

struct Polygon
{
    Room               mRoom = null;
    Plane[]            mPlanes;
    Polygon*           mConnection = null;
    vec3_t             mConnectionOffset;
    quat_t             mConnectionDir;
    //const(Polygon)*[4] mAdjasent = null;
    immutable(int)[]   mIndices;
    texture_t          mTexture = null;

//pure nothrow:
    this(in int[] indices)
    {
        assert(indices.length % 3 == 0);
        mIndices = indices.idup;
    }

    @property bool isPortal() const { return mConnection != null; }
    @property auto indices()  inout { return mIndices[]; }
    @property auto room()     inout { return mRoom; }
    @property auto planes()   inout { return mPlanes[]; }

    void connect(Polygon* poly, in vec3_t pos, in quat_t dir)
    {
        assert(poly !is null);
        mConnection = poly;
        mConnectionOffset = pos;
        mConnectionDir    = dir;
        poly.mConnection = &this;
        poly.mConnectionOffset = -pos;
        poly.mConnectionDir = dir.inverse;
    }

    void draw(RT,AT)(auto ref RT renderer, auto ref AT alloc, in Vertex[] transformedVerts, in vec3_t pos, in quat_t dir, int depth) const
    {
        //debugOut("polygon.draw");


        if(isPortal)
        {
            if(depth > 0)
            {
                renderer.pushState();
                scope(exit) renderer.popState();
                renderer.getState().dstMask = SpanMask(renderer.getState().size, alloc);
                renderer.getState().dstMask.invalidate;
                //draw mask
                struct Context1
                {
                }
                Context1 ctx;
                alias RastT1 = RasterizerHybrid!(false,true,true);
                renderer.drawIndexedTriangle!RastT1(ctx, transformedVerts[], mIndices[]);
                if(!renderer.getState().dstMask.isEmpty)
                {
                    renderer.getState().mask = renderer.getState().dstMask;
                    mConnection.room.draw(renderer, alloc, mConnectionOffset, mConnectionDir, depth - 1);
                }
            }
        }
        else
        {
            struct Context2
            {
                const(texture_t) texture;
            }
            Context2 ctx = {texture: mTexture};
            alias RastT2 = RasterizerHybrid!(true,false,true);
            renderer.drawIndexedTriangle!RastT2(ctx, transformedVerts[], mIndices[]);
        }
    }
}