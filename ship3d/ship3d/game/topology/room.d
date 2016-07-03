module game.topology.room;

import std.typecons;
import std.container;
import std.range;
import std.algorithm;

import gamelib.range;
import gamelib.containers.intrusivelist;

import game.units;
import game.utils;
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
    World           mWorld;
    Vertex[]        mVertices;
    Polygon[]       mPolygons;

    IntrusiveList!(EntityRef,"roomLink") mEntities;
    StaticEntityRef[] mStaticEntities;
    bool            mNeedUdateEntities = true;

    Light[]         mStaticLights;
    Light[]         mLights;
    IntrusiveList!(LightRef,"roomLink") mLightRefs;
    bool            mNeedUpdateLights = false;
public:
//pure nothrow:
    IntrusiveListLink   worldUpdateLightsLink;

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
        invalidateLights();
    }

    void invalidateEntities()                 { mNeedUdateEntities = true; }
    void invalidateLights()
    {
        if(!mNeedUpdateLights)
        {
            mWorld.updateLightslist.insertBack(this);
            mNeedUpdateLights = true;
        }
    }
    @property needUpdateEntities()      const { return mNeedUdateEntities; }
    @property vertices()                inout { return mVertices[]; }
    @property polygons()                inout { return mPolygons[]; }
    @property world()                   inout { return mWorld; }
    @property lightController()         inout { return mWorld.lightController(); }
    @property lights()                  inout { return mLights[]; }
    @property ref staticLights()        inout { return mStaticLights; }
    @property ref staticEntities()      inout { return mStaticEntities; };

    void draw(RT, AT)(auto ref RT renderer, auto ref AT alloc, in vec3_t pos, in quat_t dir, in Entity srce, int depth) const
    {
        //debugOut("draw");
        auto allocState = alloc.state;
        scope(exit) alloc.restoreState(allocState);

        const srcMat = renderer.state.matrix;
        const viewMat = dir.inverse.to_matrix!(4,4)() * mat4_t.translation(-pos.x,-pos.y,-pos.z);
        const mat = srcMat * viewMat;
        renderer.state.matrix = mat;

        auto transformedVertices      = alloc.alloc!TransformedVertex(mVertices.length);
        auto transformedVerticesFlags = alloc.alloc!bool(mVertices.length, false);

        void drawPolygons(bool DynLights)()
        {
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
                p.draw!DynLights(renderer, alloc, transformedVertices, pos, dir, srce, depth);
            }
        }

        /*if(!lights.empty)
        {
            drawPolygons!true();
        }
        else
        {
            drawPolygons!false();
        }*/

        foreach(const ref e; mEntities[])
        {
            auto entity = e.ent;
            renderer.state.matrix = mat * mat4_t.translation(e.pos.x,e.pos.y,e.pos.z) * e.dir.to_matrix!(4,4)();
            entity.draw(renderer, Entity.DrawParams(this, alloc));
        }

        foreach(const ref e; mStaticEntities[0..min($,900)])
        {
            auto entity = e.ent;
            renderer.state.matrix = mat * mat4_t.translation(e.pos.x,e.pos.y,e.pos.z) * e.dir.to_matrix!(4,4)();
            entity.draw(renderer, Entity.DrawParams(this, alloc));
        }
        renderer.flushContext();
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

    void addStaticEntity(Entity e, in vec3_t epos, in quat_t edir)
    {
        mStaticEntities ~= StaticEntityRef(e, epos, edir);
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
                        vec3_t norm = void;
                        if(p.plane.checkCollision(oldPos, newPos, r, norm))
                        {
                            //debugOut(norm);
                            newPos += norm;
                            dpos += norm;
                            moved = true;
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
                const pl = p.plane;

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
        enum eps = 0.001f;
        foreach(ref p0; mPolygons[])
        {
        loop1: foreach(ref p1; mPolygons[])
            {
                if(&p0 == &p1) continue;
                foreach(i0;p0.indices.cycle.adjacent.take(p0.indices.length))
                {
                    const v0 = tuple(vertices[i0[0]],vertices[i0[1]]);
                    foreach(i1;p1.indices.cycle.adjacent.take(p1.indices.length))
                    {
                        const v1 = tuple(vertices[i1[0]],vertices[i1[1]]);
                        if(almost_equal(v0[0].pos, v1[0].pos, eps) && almost_equal(v0[1].pos, v1[1].pos, eps))
                        {
                            p0.addAdjacent(&p1,i0[0],i0[1],i1[0],i1[1]);
                            continue loop1;
                        }
                        if(almost_equal(v0[0].pos, v1[1].pos, eps) && almost_equal(v0[1].pos, v1[0].pos, eps))
                        {
                            p0.addAdjacent(&p1,i0[0],i0[1],i1[1],i1[0]);
                            continue loop1;
                        }
                    }
                }
            }
        }
    }
}