module game.topology.polygon;

import std.algorithm;
import std.range;

import game.units;
import game.topology.room;
import game.topology.plane;

import game.entities.entity;

import game.renderer.spanmask;
import game.renderer.rasterizerhybrid2;
import game.renderer.light;

enum PolygonType
{
    Up,
    Down,
    Left,
    Right,
    Front,
    Back
}

struct Polygon
{
private:
    immutable PolygonType mType;
    immutable vec3_t    mCenterOffset;
    Room                mRoom = null;
    immutable(int)[]    mIndices;
    Plane[]             mPlanes;

    immutable(int)[]    mConnectionIndices;
    texture_t           mTexture = null;
    lightmap_t          mLightmap = null;
    Polygon*[]          mAdjacent;

    Polygon*            mConnection = null;
    vec3_t              mConnectionOffset;
    quat_t              mConnectionDir;
    Polygon*[]          mConnectionAdjacent;
public:
//pure nothrow:
    this(in int[] indices, in vec3_t centerOffset, in PolygonType type)
    {
        assert(indices.length > 0);
        assert(indices.length % 3 == 0);
        mType = type;
        mCenterOffset = centerOffset;
        mIndices = indices.idup;
    }

    package void calcPlanes()
    {
        assert(mPlanes.length == 0);
        assert(room !is null);
        assert(indices.length % 3 == 0);
        mPlanes = createPlanes(vertices, indices);
    }

    @property type()                const { return mType; }
    @property texture(texture_t t)        { mTexture = t; }
    @property lightmap(lightmap_t l)      { mLightmap = l; }
    @property isPortal()            const { return mConnection != null; }
    @property indices()             inout { return mIndices[]; }
    @property vertices()            inout { return room.vertices; }
    @property polyVertices()        const { return indices[].map!(a => vertices[a]); }
    @property room()                inout { return mRoom; }
    @property room(Room r)                { mRoom = r; }
    @property connection()          inout { return mConnection; }
    @property planes()              inout { return mPlanes[]; }
    @property adjacent()            inout { return mAdjacent[]; }
    @property connectionAdjacent()  inout { return mConnectionAdjacent[]; }
    @property connectionOffset()    const { return mConnectionOffset; }
    @property connectionDir()       const { return mConnectionDir; }

    auto distance(in vec3_t pos) const
    {
        assert(planes.length == 1);
        return planes[0].distance(pos);
    }

    package void addAdjacent(Polygon* poly)
    {
        assert(!canFind(adjacent, poly));
        mAdjacent ~= poly;
    }

    package void addEntity(Entity e, in vec3_t pos, in quat_t dir, in Room src)
    {
        assert(isPortal);
        room.addEntity(e, (pos + mConnectionOffset) * mConnectionDir, mConnectionDir * dir);
    }

    auto transformFromPortal(in vec3_t pos) const
    {
        assert(isPortal);
        return (pos + connectionOffset) * connectionDir;
    }

    void connect(Polygon* poly, in pos_t rot = 0)
    {
        assert(!isPortal);
        assert(!poly.isPortal);
        assert(poly !is null);
        assert(planes.length == 1);
        assert(poly.planes.length == 1);
        const dir0 = quat_t.from_unit_vectors(-planes[0].normal,vec3_t(0,0,1));
        const dir1 = quat_t.from_unit_vectors(poly.planes[0].normal,vec3_t(0,0,1));
        const dir2 = quat_t.axis_rotation(rot,poly.planes[0].normal);
        const offset = (mCenterOffset * dir0 - poly.mCenterOffset * dir1) * dir1.inverse;
        connect(poly, offset, (dir0.inverse * dir1 * dir2));
    }

    private void connect(Polygon* poly, in vec3_t pos, in quat_t dir)
    {
        assert(!canFind(adjacent, poly));
        assert(poly !is null);
        assert(poly !is &this);
        mConnection            = poly;
        mConnectionOffset      = pos;
        mConnectionDir         = dir.normalized;
        poly.mConnection       = &this;
        poly.mConnectionOffset = (-pos) * mConnectionDir;
        poly.mConnectionDir    = dir.inverse.normalized;
        updateConnecionIndices();
        poly.updateConnecionIndices();
        updateConnectionAdjacent();
        poly.updateConnectionAdjacent();
    }

    void disconnect()
    {
        assert(isPortal);
        connection.disconnectImpl();
        disconnectImpl();
    }

    private void disconnectImpl()
    {
        mConnection = null;
        mConnectionAdjacent.length = 0;
    }

    private void updateConnecionIndices()
    {
        assert(isPortal);
        auto con = connection;
        const count = indices.length;
        assert(count == con.indices.length);
        int[] newInd;
        newInd.length = count;
    outer: foreach(i,ind;indices[])
        {
            foreach(conInd;con.indices[])
            {
                enum eps = 0.001f;
                if(almost_equal(vertices[ind].pos,transformFromPortal(con.vertices[conInd].pos),eps))
                {
                    newInd[i] = conInd;
                    continue outer;
                }
            }
            assert(false, "Cannot find adjacent point");
        }
        mConnectionIndices = newInd.idup;
    }

    private void updateConnectionAdjacent()
    {
        assert(isPortal);
        assert(!adjacent.empty);
        auto con = connection;
        mConnectionAdjacent.length = adjacent.length;
        enum eps = 0.001f;
    outer: foreach(i,p1;adjacent[])
        {
            foreach(p2;con.adjacent[])
            {
                if(cartesianProduct(p1.polyVertices.map!(a => a.pos),p2.polyVertices.map!(a => transformFromPortal(a.pos)))
                    .filter!(a => almost_equal(a[0],a[1],eps)).take(2).count == 2)
                {
                    mConnectionAdjacent[i] = p2;
                    continue outer;
                }
            }
            assert(false, "Cannot find adjacent polygon");
        }
    }

    void draw(bool DynLights, RT,AT,VT)(auto ref RT renderer, auto ref AT alloc, in VT[] transformedVerts, in vec3_t pos, in quat_t dir, in Entity srce, int depth)
    {
        if(isPortal)
        {
            if(depth > 0)
            {
                renderer.pushState();
                scope(exit) renderer.popState();
                bool drawPortal = false;

                assert(1 == planes.length);
                const pl = planes[0];

                {
                    renderer.getState().dstMask = SpanMask(renderer.getState().size, alloc);
                    renderer.getState().dstMask.invalidate;
                    //draw mask
                    struct Context1 {}
                    Context1 ctx;
                    alias RastT1 = RasterizerHybrid2!(false,true,true,false);
                    renderer.drawIndexedTriangle!RastT1(alloc, ctx, transformedVerts[], mIndices[]);
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
                    mConnection.room.draw(renderer, alloc, -mConnectionOffset, mConnectionDir.inverse, srce, depth - 1);
                }
            }
        }
        else
        {
            struct Context2
            {
                const texture_t texture;
                static if(DynLights)
                {
                    const Light[] lights;
                }
                const LightController lightController;
            }
            assert(mTexture !is null);
            static if(DynLights)
            {
                Context2 ctx = {texture: mTexture, lights: room.lights, lightController: room.lightController};
            }
            else
            {
                Context2 ctx = {texture: mTexture, lightController: room.lightController};
            }
            alias RastT2 = RasterizerHybrid2!(true,false,true,DynLights);
            renderer.drawIndexedTriangle!RastT2(alloc, ctx, transformedVerts[], mIndices[]);
        }
    }
}