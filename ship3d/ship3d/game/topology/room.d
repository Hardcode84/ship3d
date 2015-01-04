module game.topology.room;

import std.container;
import std.range;
import std.algorithm;

import game.units;
import game.world;
import game.entities.entity;
import game.topology.polygon;
import game.topology.entityref;
final class Room
{
private:
    World       mWorld;
    Vertex[]    mVertices;
    Polygon[]   mPolygons;

    //Array!EntityRef mEntities;
    EntityRef*[]     mEntities;
    bool             mNeedUdateEntities;
public:
//pure nothrow:
    this(World w, Vertex[] vertices, Polygon[] polygons)
    {
        assert(w !is null);
        mWorld = w;
        mVertices = vertices;
        mPolygons = polygons;
        foreach(ref p;mPolygons[])
        {
            p.room = this;
            p.calcPlanes();
        }
        calcAdjacent();
    }

    void invalidateEntities()                 { mNeedUdateEntities = true; }
    @property bool needUpdateEntities() const { return mNeedUdateEntities; }
    @property auto vertices()           inout { return mVertices[]; }
    @property auto polygons()           inout { return mPolygons[]; }
    @property world()                   inout { return mWorld; }

    void draw(RT, AT)(auto ref RT renderer, auto ref AT alloc, in vec3_t pos, in quat_t dir, in Entity srce, int depth) const
    {
        //debugOut("Room.draw");
        auto allocState = alloc.state;
        scope(exit) alloc.restoreState(allocState);

        const srcMat = renderer.getState().matrix;
        renderer.getState().matrix = srcMat * dir.inverse.to_matrix!(4,4)() * mat4_t.translation(-pos.x,-pos.y,-pos.z);
        const mat = renderer.getState().matrix;

        auto transformedVertices      = alloc.alloc!Vertex(mVertices.length);
        auto transformedVerticesFlags = alloc.alloc!bool(mVertices.length);
        transformedVerticesFlags[] = false;
        foreach(const ref p; mPolygons[])
        {
            const ignore = false;//p.isPortal && canFind(mInputListeners[], listener);
            if(!ignore)
            {
                foreach(ind; p.indices[])
                {
                    if(!transformedVerticesFlags[ind])
                    {
                        transformedVertices[ind] = renderer.transformVertex(mVertices[ind]);
                        transformedVerticesFlags[ind] = true;
                    }
                }
                p.draw(renderer, alloc, transformedVertices, pos, dir, srce, depth);
            }
        }

        //sort entities
        foreach(const ref e; mEntities)
        {
            auto entity = e.ent;
            renderer.getState().matrix = mat * mat4_t.translation(e.pos.x,e.pos.y,e.pos.z) * e.dir.to_matrix!(4,4)();
            entity.draw(renderer);
        }
    }

    void addEntity(Entity e, in vec3_t epos, in quat_t edir)
    {
        addEntity(e, epos, edir, null);
    }

    package void addEntity(Entity e, in vec3_t epos, in quat_t edir, in Room src)
    {
        assert(e !is null);
        //const id = world.generateId();
        auto r = world.erefAllocator.allocate();
        r.room = this;
        r.ent = e;
        r.pos = epos;
        r.dir = edir;

        mEntities ~= r;
        e.onAddedToRoom(r);
        mNeedUdateEntities = true;
    }

    void updateEntities()
    {
        //debugOut("updateEntities");
        scope(exit) mNeedUdateEntities = false;
        if(mEntities.empty) return;
        for(int i = cast(int)mEntities.length - 1; i >= 0; --i)
        {
            auto e = mEntities[i];
            auto entity = e.ent;
            const r = entity.radius() + 0.001f;
            const oldPos = e.pos;
            const newPos = oldPos + entity.posDelta * (entity.dir * e.dir.inverse);

            //update position
            auto dpos = vec3_t(0,0,0);
            bool moved = false;
            foreach(const ref p; polygons)
            {
                if(!p.isPortal)
                {
                    foreach(const ref pl; p.planes)
                    {
                        vec3_t norm = void;
                        if(pl.checkCollision(oldPos, newPos, r, norm))
                        {
                            dpos += norm * 1.001f;
                            moved = true;
                        }
                    }
                }
            }
            if(moved)
            {
                entity.move(dpos * (entity.dir * e.dir.inverse));
            }

            if(e.remove)
            {
                e.ent.onRemovedFromRoom(e);
                world.erefAllocator.free(e);
                mEntities[i] = mEntities[$ - 1];
                --mEntities.length;
            }
        }
    }

    package void updateEntityPos(EntityRef* e, in vec3_t dpos)
    {
        //debugOut("updateEntityPos");
        e.inside = true;
        e.correction = vec3_t(0,0,0);
        const r = e.ent.radius;
        const oldPos = e.pos;
        const newPos = oldPos + dpos;
        foreach(ref p; mPolygons[])
        {
            if(p.isPortal)
            {
                assert(1 == p.planes().length, debugConv(p.planes().length));
                const pl = p.planes()[0];

                const dist = pl.distance(newPos);
                enum portalCorrection = 0.001f;
                if(pl.checkPortal(newPos,r))
                {
                    //debugOut(dist);
                    if(!pl.checkPortal(oldPos,r))
                    {
                        p.connection.addEntity(e.ent, newPos, e.dir, this);
                    }

                    if(dist < -portalCorrection)
                    {
                        e.inside = false;
                    }
                    else if(almost_equal(dist, 0, portalCorrection))
                    {
                        e.correction += pl.normal * (2 * portalCorrection);
                    }

                    if(dist < (-r - portalCorrection))
                    {
                        e.remove = true;
                    }
                }
            } //isPortal
        } //foreach
        e.pos = newPos;
    }

    private void calcAdjacent()
    {
        foreach(i,ref p0; mPolygons[])
        {
            const ind0 = p0.indices.dup.sort;
        loop1: foreach(j,ref p1; mPolygons[])
            {
                if(i == j) continue;
                int same = 0;
                const ind1 = p1.indices.dup.sort;
                foreach(i0;ind0.uniq)
                {
                    const v0 = vertices[i0];
                    foreach(i1;ind1.uniq)
                    {
                        const v1 = vertices[i1];
                        if(almost_equal(v0.pos, v1.pos))
                        {
                            ++same;
                            if(same >= 2)
                            {
                                p0.addAdjacent(&p1);
                                continue loop1;
                            }
                        }
                    }
                }
            }
        }
    }
}