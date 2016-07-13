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
    bool         mVisisble = true;
protected:
    bool         mDrawn = false;
public:
    import game.world;
    alias RendererT = World.RendererT;

    IntrusiveListLink   worldLink;
//pure nothrow:
    this(World w, in pos_t radius = 5)
    {
        mWorld = w;
        mRadius = radius;
    }

    void kill() { mIsAlive = false; }

    void dispose() {}

    final @property
    {
        auto world()   inout { return mWorld; }
        auto radius()  const { return mRadius; }
        auto pos()     const { return mRefPos; }
        auto posDelta()const { return mPosDelta; }
        auto dir()     const { return mRefDir; }
        auto isAlive() const { return mIsAlive; }
        auto visible() const { return mVisisble; }
        auto visible(bool val ) { mVisisble = val; }
        auto drawn() const { return mDrawn; }
        auto drawn(bool val ) { mDrawn = val; }
    }

    final @property connections()
    {
        assert(!mConnections.empty, "Connection list is empty");
        return mConnections[];
    }

    final @property mainConnection()
    {
        assert(connections[].canFind!(a => a.inside));
        return connections[].find!(a => a.inside).front;
    }

    struct DrawParams
    {
        const(Room) room;
        StackAlloc alloc;
    }

    void draw(ref RendererT renderer, DrawParams params)
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