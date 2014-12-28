﻿module game.topology.room;

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
    @property world() inout { return mWorld; }
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
                foreach(i; p.indices[])
                {
                    if(!transformedVerticesFlags[i])
                    {
                        transformedVertices[i] = renderer.transformVertex(mVertices[i]);
                        transformedVerticesFlags[i] = true;
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
            const r = entity.radius();

            //update position
            auto dpos = vec3_t(0,0,0);
            bool moved = false;
            foreach(const ref p; polygons)
            {
                if(!p.isPortal)
                {
                    foreach(const ref pl; p.planes)
                    {
                        if(pl.checkCollision(e.pos,r))
                        {
                            const dist = pl.distance(e.pos) - r;
                            dpos -= dist * pl.normal;
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
                //debugOut(dist);
                if(dist < r)
                {
                    const oldDist = pl.distance(oldPos);
                    //debugOut("old");
                    //debugOut(oldDist);
                    if(oldDist > r && pl.checkPortal(newPos,r))
                    {
                        p.connection.addEntity(e.ent, newPos, e.dir, this);
                    }

                    if(dist < -r)
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
        loop1: foreach(j,ref p1; mPolygons[])
            {
                if(i == j) continue;
                int same = 0;
                foreach(const ref i0;p0.indices)
                {
                    const v0 = vertices[i0];
                    foreach(const ref i1;p1.indices)
                    {
                        const v1 = vertices[i1];
                        if(almost_equal(v0.pos, v1.pos))
                        {
                            if(2 == ++same)
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