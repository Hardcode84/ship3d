module game.topology.polygon;

import std.typecons;
import std.array;
import std.algorithm;
import std.range;
import std.exception;

import gamelib.range;

import game.units;
import game.topology.room;
import game.topology.plane;

import game.entities.entity;

import game.renderer.spanmask;

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
    immutable(int)[]    mTriangleIndices;
    Plane               mPlane;

    texture_t           mTexture = null;
    lightmap_t          mLightmap = null;
    Polygon*[]          mAdjacent;
    Tuple!(int,int)[]   mAdjacentSrcIndices;
    Tuple!(int,int)[]   mAdjacentIndices;

    Polygon*            mConnection = null;
    vec3_t              mConnectionOffset;
    quat_t              mConnectionDir;
    Polygon*[]          mConnectionAdjacent;
    Tuple!(int,int)[]   mConnectionIndices;

    invariant
    {
        assert(mAdjacent.length == mAdjacentIndices.length);
        assert(mAdjacent.length == mAdjacentSrcIndices.length);
        //assert(mConnectionAdjacent.length == mConnectionIndices.length);
        //assert(mConnection is null || (mAdjacent.length == mConnectionAdjacent.length && mAdjacentIndices == mConnectionIndices));
    }
public:
//pure nothrow:
    this(in int[] indices, in vec3_t centerOffset, in PolygonType type)
    {
        assert(indices.length > 0);
        mType = type;
        mCenterOffset = centerOffset;
        mIndices = indices.idup;
        mTriangleIndices = chain(indices[0].only, adjacent(indices.dropOne).map!(a => only(cast(int)a[0],a[1])).joiner(indices[0..1])).array.assumeUnique;
        assert(mTriangleIndices.length > 0);
        assert(mTriangleIndices.length % 3 == 0);
    }

    package void calcPlanes()
    {
        assert(room !is null);
        assert(mTriangleIndices.length % 3 == 0);
        auto planes = createPlanes(vertices, mTriangleIndices[]);
        assert(planes.length == 1);
        mPlane = planes[0];
    }

    @property type()                const { return mType; }
    @property texture(texture_t t)        { mTexture = t; }
    @property lightmap(lightmap_t l)      { mLightmap = l; }
    @property isPortal()            const { return mConnection != null; }
    @property indices()             inout { return mIndices[]; }
    @property triangleIndices()     inout { return mTriangleIndices; }
    @property vertices()            inout { return room.vertices; }
    @property polyVertices()        const { return indices[].map!(a => vertices[a]); }
    @property room()                inout { return mRoom; }
    @property room(Room r)                { mRoom = r; }
    @property connection()          inout { return mConnection; }
    @property plane()               const { return mPlane; }
    @property adjacentPolys()       inout { return mAdjacent[]; }
    @property adjacentIndices()     const { return mAdjacentIndices[]; }
    @property adjacentSrcIndices()  const { return mAdjacentSrcIndices[]; }
    @property connectionAdjacent()  inout { return mConnectionAdjacent[]; }
    @property connectionOffset()    const { return mConnectionOffset; }
    @property connectionDir()       const { return mConnectionDir; }
    @property connectionIndices()   const { return mConnectionIndices[]; }

    auto distance(in vec3_t pos) const
    {
        return plane.distance(pos);
    }

    package void addAdjacent(Polygon* poly, int srci1, int srci2, int i1, int i2)
    {
        assert(poly !is null);
        assert(!canFind(adjacentPolys, poly));
        mAdjacent ~= poly;
        mAdjacentSrcIndices ~= tuple(srci1,srci2);
        mAdjacentIndices ~= tuple(i1,i2);
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
        const dir0 = quat_t.from_unit_vectors(-plane.normal,vec3_t(0,0,1));
        const dir1 = quat_t.from_unit_vectors(poly.plane.normal,vec3_t(0,0,1));
        const dir2 = quat_t.axis_rotation(rot,poly.plane.normal);
        const offset = (mCenterOffset * dir0 - poly.mCenterOffset * dir1) * dir1.inverse;
        connect(poly, offset, (dir0.inverse * dir1 * dir2));
    }

    private void connect(Polygon* poly, in vec3_t pos, in quat_t dir)
    {
        assert(!canFind(adjacentPolys, poly));
        assert(poly !is null);
        assert(poly !is &this);
        mConnection            = poly;
        mConnectionOffset      = pos;
        mConnectionDir         = dir.normalized;
        poly.mConnection       = &this;
        poly.mConnectionOffset = (-pos) * mConnectionDir;
        poly.mConnectionDir    = dir.inverse.normalized;
        updateConnecionIndices();
        updateConnectionAdjacent();
        poly.updateConnecionIndices();
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
        mConnectionIndices = newInd.cycle.adjacent.take(count).array;
    }

    private void updateConnectionAdjacent()
    {
        assert(isPortal);
        assert(!adjacentPolys.empty);
        auto con = connection;
        mConnectionAdjacent.length = adjacentPolys.length;
        enum eps = 0.001f;
    outer: foreach(i,p1;adjacentPolys[])
        {
            foreach(p2;con.adjacentPolys[])
            {
                if(cartesianProduct(p1.polyVertices.map!(a => a.pos),p2.polyVertices.map!(a => transformFromPortal(a.pos)))
                    .filter!(a => almost_equal(a[0],a[1],eps)).take(2).count == 2)
                    mConnectionAdjacent[i] = p2;
                {
                    continue outer;
                }
            }
            assert(false, "Cannot find adjacent polygon");
        }
    }

    void draw(bool DynLights, RT,AT,VT)(auto ref RT renderer, auto ref AT alloc, in VT[] transformedVerts, in vec3_t pos, in quat_t dir, in Entity srce, int depth) const
    {
        if(isPortal)
        {
            if(depth > 0)
            {
                renderer.pushState();
                scope(exit) renderer.popState();
                bool drawPortal = false;
                const pl = plane;

                {
                    renderer.state.dstMask = SpanMask(renderer.state.size, alloc);
                    renderer.state.dstMask.invalidate;
                    //draw mask
                    struct Context1 {}
                    Context1 ctx;
                    alias RastT1 = Rasterizer!(false,true,true,false);
                    renderer.drawIndexedTriangle!RastT1(alloc, ctx, transformedVerts[], mTriangleIndices[]);
                    if(!renderer.state.dstMask.isEmpty)
                    {
                        renderer.state.mask = renderer.state.dstMask;
                        drawPortal = true;
                    }
                }

                if(drawPortal)
                {
                    mConnection.room.draw(renderer, alloc, -mConnectionOffset, mConnectionDir.inverse, srce, depth - 1);
                }
            }
        }
        else
        {
            import game.renderer.light;
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
            alias RastT2 = Rasterizer!(true,false,true,DynLights);
            renderer.drawIndexedTriangle!RastT2(alloc, ctx, transformedVerts[], mTriangleIndices[]);
        }
    }
}