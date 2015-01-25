module game.entities.entity;

import std.algorithm;

import gamelib.containers.intrusivelist;

public import game.units;
public import game.topology.room;
public import game.topology.entityref;

public import game.world;

abstract class Entity
{
private:
    enum NormalizeCounterMax = 50;
    int mRotateNormalizeCounter = NormalizeCounterMax;

    World        mWorld;
    bool         mIsAlive = true;
    immutable pos_t mRadius;
    vec3_t       mRefPos = vec3_t(0,0,0);
    vec3_t       mPosDelta = vec3_t(0,0,0);
    quat_t       mRefDir = quat_t.identity;
    IntrusiveList!(EntityRef,"entityLink") mConnections;
public:
    IntrusiveListLink   worldLink;
//pure nothrow:
    this(World w, in pos_t radius = 5)
    {
        mWorld = w;
        mRadius = radius;
    }

    void kill() { mIsAlive = false; }

    void dispose() {}

    final @property world()   inout { return mWorld; }
    final @property radius()  const { return mRadius; }
    final @property pos()     const { return mRefPos; }
    final @property posDelta()const { return mPosDelta; }
    final @property dir()     const { return mRefDir; }
    final @property isAlive() const { return mIsAlive; }

    final @property connections()
    {
        assert(!mConnections.empty, "Connection list is empty");
        pragma(msg,typeof(mConnections[]));
        return mConnections[];
    }

    final @property mainConnection()
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
        if(0 == --mRotateNormalizeCounter)
        {
            mRotateNormalizeCounter = NormalizeCounterMax;
            mRefDir *= rot;
            mRefDir.normalize;
            foreach(ref c; mConnections[])
            {
                c.dir *= rot;
                c.dir.normalize;
            }
        }
        else
        {
            mRefDir *= rot;
            foreach(ref c; mConnections[])
            {
                c.dir *= rot;
            }
        }
    }

    void onAddedToWorld(Room room, in vec3_t pos, in quat_t dir) {}

    void onAddedToRoom(EntityRef* eref)
    {
        assert(!canFind(mConnections[], eref));
        assert(!eref.entityLink.isLinked);
        mConnections.insertFront(eref);
        debugOut("added ", mConnections[].count!(a => true), " ", cast(const(void)*)eref.room);
        assert(eref.entityLink.isLinked);
    }

    void onRemovedFromRoom(EntityRef* eref)
    {
        assert(canFind(mConnections[], eref));
        assert(eref.entityLink.isLinked);
        eref.entityLink.unlink();
        debugOut("removed ", mConnections[].count!(a => true));
    }
}