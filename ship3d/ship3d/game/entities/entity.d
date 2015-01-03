module game.entities.entity;

import std.algorithm;

import game.units;
import game.topology.room;
import game.topology.entityref;

import game.world;

abstract class Entity
{
private:
    World        mWorld;
    bool         mIsAlive = true;
    pos_t        mRadius = 5;
    vec3_t       mRefPos = vec3_t(0,0,0);
    vec3_t       mPosDelta = vec3_t(0,0,0);
    quat_t       mRefDir = quat_t.identity;
    EntityRef*[] mConnections;
public:
//pure nothrow:

    this(World w)
    {
        mWorld = w;
    }

    void dispose() {}

    final @property world()   inout { return mWorld; }
    final @property radius()  const { return mRadius; }
    final @property pos()     const { return mRefPos; }
    final @property posDelta()const { return mPosDelta; }
    final @property dir()     const { return mRefDir; }
    final @property isAlive() const { return mIsAlive; }

    final @property connections() inout
    {
        assert(mConnections.length > 0, "Connection list is empty");
        return mConnections[];
    }

    void draw(T)(in auto ref T renderer) const
    {
    }

    void update() {}

    final void move(in vec3_t offset)
    {
        mPosDelta += offset;
    }

    void updatePos()
    {
        mRefPos += mPosDelta;
        const inv = mRefDir.inverse;
        foreach(ref c; mConnections[])
        {
            c.updatePos(mPosDelta * (c.dir * inv));
            c.room.invalidateEntities();
        }
        mPosDelta = vec3_t(0,0,0);
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
        debugOut("added ", cast(const(void)*)eref.room, " ", mConnections.length + 1);
        assert(!canFind(mConnections[], eref));
        mConnections ~= eref;
    }

    final void onRemovedFromRoom(EntityRef* eref)
    {
        foreach(i,c; mConnections[])
        {
            if(eref is c)
            {
                mConnections[i] = mConnections[$ - 1];
                mConnections.length--;
                debugOut("removed ",mConnections.length);
                return;
            }
        }
        assert(false, "onRemovedFromRoom invalid eref");
    }
}