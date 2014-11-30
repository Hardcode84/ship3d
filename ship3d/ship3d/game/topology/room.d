module game.topology.room;

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
        //EntityRef* r = {id: id, room: this, pos: epos, dir: edir, ent: e};
        auto r = world.erefAllocator.allocate();
        r.room = this;
        r.ent = e;
        r.pos = epos;
        r.dir = edir;

        mEntities ~= r;
        e.onAddedToRoom(r);
    }
}