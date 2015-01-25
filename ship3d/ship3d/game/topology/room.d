﻿module game.topology.room;

import std.container;
import std.range;
import std.algorithm;

import gamelib.containers.intrusivelist;

import game.units;
import game.world;

import game.entities.entity;

import game.topology.polygon;
import game.topology.entityref;
import game.topology.lightref;
import game.topology.refalloc;
import game.renderer.light;

final class Room
{
private:
    World       mWorld;
    Vertex[]    mVertices;
    Polygon[]   mPolygons;

    IntrusiveList!(EntityRef,"roomLink") mEntities;
    bool            mNeedUdateEntities = true;

    Light[]         mLights;
    IntrusiveList!(LightRef,"roomLink") mLightRefs;
    bool            mNeedUpdateLights = true;
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
        //mLights = [Light(vec3_t(29,0,0),7)];
    }

    void invalidateEntities()                 { mNeedUdateEntities = true; }
    void invalidateLights()                   { mNeedUpdateLights = true; }
    @property bool needUpdateEntities() const { return mNeedUdateEntities; }
    @property auto vertices()           inout { return mVertices[]; }
    @property auto polygons()           inout { return mPolygons[]; }
    @property world()                   inout { return mWorld; }
    @property lightController()         inout { return mWorld.lightController(); }
    @property lights()                  inout { return mLights[]; }

    void draw(RT, AT)(auto ref RT renderer, auto ref AT alloc, in vec3_t pos, in quat_t dir, in Entity srce, int depth)
    {
        updateLights();//fuck const
        auto allocState = alloc.state;
        scope(exit) alloc.restoreState(allocState);

        const srcMat = renderer.getState().matrix;
        renderer.getState().matrix = srcMat * dir.inverse.to_matrix!(4,4)() * mat4_t.translation(-pos.x,-pos.y,-pos.z);
        const mat = renderer.getState().matrix;

        auto transformedVertices      = alloc.alloc!TransformedVertex(mVertices.length);
        auto transformedVerticesFlags = alloc.alloc!bool(mVertices.length);
        transformedVerticesFlags[] = false;
        foreach(ref p; mPolygons[])
        {
            foreach(ind; p.indices[])
            {
                if(!transformedVerticesFlags[ind])
                {
                    transformedVertices[ind] = transformVertex(mVertices[ind], mat);
                    transformedVerticesFlags[ind] = true;
                }
            }
            p.draw(renderer, alloc, transformedVertices, pos, dir, srce, depth);
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
        auto r = world.refAllocator.allocate!EntityRef();
        r.room = this;
        r.ent = e;
        r.pos = epos;
        r.dir = edir;

        mEntities.insertBack(r);
        e.onAddedToRoom(r);
        mNeedUdateEntities = true;
    }

    void updateEntities()
    {
        scope(exit) mNeedUdateEntities = false;
        if(mEntities.empty) return;
        auto range = mEntities[];
        while(!range.empty)
        {
            auto e = range.front;
            auto entity = e.ent;
            if(entity.isAlive)
            {
                const r = entity.radius();
                const oldPos = e.pos;
                const dir = (e.dir * entity.dir.inverse);
                auto newPos = oldPos + entity.posDelta * dir;

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
                                //debugOut(norm);
                                newPos += norm;
                                dpos += norm;
                                moved = true;
                            }
                        }
                    }
                }
                if(moved)
                {
                    entity.move(dpos * dir.inverse);
                }
            }

            range.popFront();
            if(e.remove || !entity.isAlive)
            {
                e.ent.onRemovedFromRoom(e);
                world.refAllocator.free(e);
            }
        }
    }

    auto addLight(in Light light)
    {
        auto lref = world.refAllocator.allocate!LightRef();
        lref.light = light;
        lref.room = this;
        mLightRefs.insertFront(lref);
        invalidateLights();
        return lref;
    }
    void removeLight(LightRef* lref)
    in
    {
        assert(lref !is null);
    }
    body
    {
        world.refAllocator.free(lref);
        invalidateLights();
    }

    void updateLights()
    {
        if(mNeedUpdateLights)
        {
            mLights.length = 0;
            foreach(r;mLightRefs[])
            {
                mLights ~= r.light;
            }
            mNeedUpdateLights = false;
        }
    }

    package void updateEntityPos(EntityRef* e, in vec3_t dpos)
    {
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