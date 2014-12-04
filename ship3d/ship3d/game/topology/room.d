﻿module game.topology.room;

import std.container;
import std.range;

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
            p.mRoom = this;
        }
    }

    @property auto vertices() inout { return mVertices[]; }
    @property auto polygons() inout { return mPolygons[]; }

    void draw(RT, AT)(auto ref RT renderer, auto ref AT alloc, in vec3_t pos, in quat_t dir, int depth) const
    {
        //debugOut("Room.draw");
        auto allocState = alloc.state;
        scope(exit) alloc.restoreState(allocState);

        const srcMat = renderer.getState().matrix;
        renderer.getState().matrix = srcMat * dir.to_matrix!(4,4)() * mat4_t.translation(pos.x,pos.y,pos.z);
        const mat = renderer.getState().matrix;

        auto transformedVertices      = alloc.alloc!(Vertex)(mVertices.length);
        auto transformedVerticesFlags = alloc.alloc!(bool)(mVertices.length);
        transformedVerticesFlags[] = false;
        foreach(ind,ref p; mPolygons[])
        {
            //if(1 != ind)
            //if(p.checkNormals(dir))
            {
                foreach(i; p.indices[])
                {
                    if(!transformedVerticesFlags[i])
                    {
                        transformedVertices[i] = renderer.transformVertex(mVertices[i]);
                        transformedVerticesFlags[i] = true;
                    }
                }
                p.draw(renderer, alloc, transformedVertices, pos, dir, depth);
            }
        }

        //sort entities
        foreach(ref e; mEntities)
        {
            auto entity = e.ent;
            renderer.getState().matrix = mat * mat4_t.translation(e.pos.x,e.pos.y,e.pos.z) * e.dir.to_matrix!(4,4)();
            entity.draw(renderer);
        }
    }

    void addEntity(Entity e, in vec3_t epos, in quat_t edir)
    {
        assert(e !is null);
        const id = world.generateId();
        auto r = world.erefAllocator.allocate();
        r.room = this;
        r.ent = e;
        r.pos = epos;
        r.dir = edir;

        mEntities ~= r;
        e.onAddedToRoom(r);
    }

    void updateEntities()
    {
        scope(exit) mNeedUdateEntities = false;
        if(mEntities.empty) return;
        for(int i = cast(int)mEntities.length - 1; i >= 0; --i)
        {
            auto e = mEntities[i];
            bool remove = false;

            const r = e.ent.radius();

            //update position
            auto dpos = vec3_t(0,0,0);
            bool moved = false;
            foreach(ref p; mPolygons[])
            {
                if(!p.isPortal)
                {
                    foreach(const ref pl; p.planes())
                    {
                        const dist = pl.distance(e.pos) - r;
                        if(dist < 0)
                        {
                            dpos -= dist * pl.normal;
                        }
                    }
                }
            }
            if(moved)
            {
                e.ent.move(dpos);
            }

            foreach(ref p; mPolygons[])
            {
                if(p.isPortal)
                {
                    assert(1 == p.planes().length);
                    const pl = p.planes()[0];
                    const dist = pl.distance(e.pos) - r;
                    if(dist < 0)
                    {
                        //dpos -= dist * pl.normal;
                    }
                }
            }

            if(remove)
            {
                mEntities[i] = mEntities[$ - 1];
                --mEntities.length;
            }
        }
    }
}