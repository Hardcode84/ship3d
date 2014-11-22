module game.topology.room;

import std.container;
import std.range;

import game.units;
import game.world;
import game.entities.entity;
import game.topology.polygon;

struct EntityRef
{
    int id = 0;
    Room room;
    Entity ent;
    vec3_t pos;
    quat_t dir;
}

final class Room
{
private:
    World       mWorld;
    Vertex[]    mVertices;
    Polygon[]   mPolygons;

    //Array!EntityRef mEntities;
    EntityRef[]     mEntities;
public:
    @property world() inout pure nothrow { return mWorld; }
    this(World w, Vertex[] vertices, Polygon[] polygons) pure nothrow
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

    @property auto vertices() inout pure nothrow { return mVertices[]; }
    @property auto polygons() inout pure nothrow { return mPolygons[]; }

    void draw(T)(auto ref T renderer, in vec3_t pos, in quat_t dir) pure nothrow
    {
        const srcMat = renderer.getState().matrix;
        renderer.getState().matrix = srcMat * mat4_t.translation(pos.x,pos.y,pos.z) * dir.to_matrix!(4,4)();
        const mat = renderer.getState().matrix;
        foreach(const ref p; mPolygons)
        {
            p.draw(renderer, pos, dir);
        }
        //sort entities
        const worldDrawCounter = world.drawCounter;
        foreach(ref e; mEntities)
        {
            auto entity = e.ent;
            if(entity.drawCounter != worldDrawCounter)
            {
                renderer.getState().matrix = mat * mat4_t.translation(e.pos.x,e.pos.y,e.pos.z) * e.dir.to_matrix!(4,4)();
                entity.draw(renderer);
                entity.drawCounter = worldDrawCounter;
            }
        }
    }

    void update()
    {
        const worldUpdateCounter = world.updateCounter;
        foreach(ref e; mEntities)
        {
            if(e.ent.updateCounter != worldUpdateCounter)
            {
                e.ent.updateCounter = worldUpdateCounter;
            }
        }
    }

    void addEntity(Entity e, in vec3_t pos, in quat_t dir) pure nothrow
    {
        assert(e !is null);
        const id = world.generateId();
        EntityRef r = {id: id, room: this, pos: pos, dir: dir, ent: e};
        mEntities.put(r);
        e.onAddedToRoom(r);
    }
}

