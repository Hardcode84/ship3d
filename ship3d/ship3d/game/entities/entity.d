module game.entities.entity;

import std.algorithm;

import gamelib.containers.intrusivelist;

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
    IntrusiveList!(EntityRef,"entityLink") mConnections;
public:
    IntrusiveListLink   worldLink;
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
        assert(!mConnections.empty, "Connection list is empty");
        return mConnections[];
    }

    final @property mainConnection() inout
    {
        assert(connections[].canFind!(a => a.inside));
        return connections[].find!(a => a.inside).front;
    }

    void draw(T)(in auto ref T renderer) const {}

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

    void onAddedToRoom(EntityRef* eref)
    {
        assert(!canFind(mConnections[], eref));
        assert(!eref.entityLink.isLinked);
        mConnections.insertBack(eref);
        debugOut("added ", cast(const(void)*)eref.room, " ", mConnections[].count!(a => true));
        assert(eref.entityLink.isLinked);
    }

    void onRemovedFromRoom(EntityRef* eref)
    {
        assert(canFind(mConnections[], eref));
        assert(eref.entityLink.isLinked);
        eref.entityLink.unlink();
        debugOut("removed ",mConnections[].count!(a => true));
    }
}