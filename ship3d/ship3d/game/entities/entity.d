module game.entities.entity;

import std.algorithm;

import game.units;
import game.topology.room;
import game.topology.entityref;

class Entity
{
private:
    pos_t       mRadius = 1;
    vec3_t      mRefPos = vec3_t(0,0,0);
    quat_t      mRefDir = quat_t.identity;
    EntityRef*[] mConnections;
public:
//pure nothrow:

    this()
    {
        // Constructor code
    }

    final @property radius() const { return mRadius; }

    final @property connections() inout
    {
        assert(mConnections.length > 0);
        return mConnections[];
    }

    void draw(T)(in auto ref T renderer) const
    {
    }

    final void move(in vec3_t offset)
    {
        mRefPos += offset;
        foreach(ref c; mConnections[])
        {
            c.updatePos(offset);
            c.room.invalidateEntities();
        }
    }

    final void rotate(in quat_t rot)
    {
        mRefDir *= rot;
        foreach(ref c; mConnections[])
        {
            c.dir *= rot;
        }
    }

    final void onAddedToRoom(EntityRef* eref)
    {
        debugOut("added");
        assert(!canFind(mConnections[], eref));
        mConnections ~= eref;
    }

    final void onRemovedFromRoom(EntityRef* eref)
    {
        debugOut("removed");
        foreach(i,c; mConnections[])
        {
            if(eref is c)
            {
                mConnections[i] = mConnections[$ - 1];
                mConnections.length--;
                return;
            }
        }
        assert(false, "onRemovedFromRoom invalid eref");
    }
}