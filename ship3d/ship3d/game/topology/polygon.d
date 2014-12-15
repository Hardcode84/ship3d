module game.topology.polygon;

import game.units;
import game.topology.room;
import game.topology.plane;

import game.entities.entity;

import game.renderer.spanmask;
import game.renderer.rasterizerhybrid;

struct Polygon
{
private:
    Room               mRoom = null;
    Plane[]            mPlanes;
    Polygon*           mConnection = null;
    vec3_t             mConnectionOffset;
    quat_t             mConnectionDir;
    immutable(int)[]   mIndices;
    texture_t          mTexture = null;
public:
//pure nothrow:
    this(in int[] indices)
    {
        assert(indices.length > 0);
        assert(indices.length % 3 == 0);
        mIndices = indices.idup;
    }

    package void calcPlanes()
    {
        assert(mPlanes.length == 0);
        assert(room !is null);
        assert(indices.length % 3 == 0);
        const verts = vertices;
        foreach(i;0..indices.length / 3)
        {
            const i0 = indices[i * 3 + 0];
            const i1 = indices[i * 3 + 1];
            const i2 = indices[i * 3 + 2];
            const p = Plane(verts[i0].pos, verts[i1].pos, verts[i2].pos);
            if(0 == mPlanes.length || p != mPlanes[$ - 1])
            {
                mPlanes ~= p;
            }
        }
    }

    @property void texture(texture_t t) { mTexture = t; }
    @property bool isPortal()     const { return mConnection != null; }
    @property auto indices()      inout { return mIndices[]; }
    @property auto vertices()     inout { return room.vertices; }
    @property auto room()         inout { return mRoom; }
    @property void room(Room r)         { mRoom = r; }
    @property auto connection()   inout { return mConnection; }
    @property auto planes()       inout { return mPlanes[]; }

    package void addEntity(Entity e, in vec3_t pos, in quat_t dir, in Room src)
    {
        assert(isPortal);
        room.addEntity(e, (pos + mConnectionOffset) * mConnectionDir, mConnectionDir * dir);
    }

    void connect(Polygon* poly, in vec3_t pos, in quat_t dir)
    {
        assert(poly !is null);
        mConnection            = poly;
        mConnectionOffset      = pos;
        mConnectionDir         = dir;
        poly.mConnection       = &this;
        poly.mConnectionOffset = (-pos) * dir;
        poly.mConnectionDir    = dir.inverse;
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
                bool drawPortal = false;

                assert(1 == planes.length);


                {
                    renderer.getState().dstMask = SpanMask(renderer.getState().size, alloc);
                    renderer.getState().dstMask.invalidate;
                    //draw mask
                    struct Context1 {}
                    Context1 ctx;
                    alias RastT1 = RasterizerHybrid!(false,true,true);
                    renderer.drawIndexedTriangle!RastT1(ctx, transformedVerts[], mIndices[]);
                    if(!renderer.getState().dstMask.isEmpty)
                    {
                        renderer.getState().mask = renderer.getState().dstMask;
                        drawPortal = true;
                    }
                }

                //debugOut(drawPortal);
                if(drawPortal)
                {
                    //debugOut("draw port");
                    mConnection.room.draw(renderer, alloc, -mConnectionOffset, mConnectionDir.inverse, depth - 1);
                }
            }
        }
        else
        {
            struct Context2
            {
                const(texture_t) texture;
            }
            assert(mTexture !is null);
            Context2 ctx = {texture: mTexture};
            alias RastT2 = RasterizerHybrid!(true,false,true);
            renderer.drawIndexedTriangle!RastT2(ctx, transformedVerts[], mIndices[]);
        }
    }
}