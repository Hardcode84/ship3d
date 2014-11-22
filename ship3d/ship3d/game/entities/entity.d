module game.entities.entity;

import std.range;

import game.units;
import game.topology.room;

class Entity
{
private:
    int mUpdateCounter = 0;
    int mDrawCounter   = 0;
    EntityRef[] mConnections;
public:
    final @property updateCounter() const pure nothrow { return mUpdateCounter; }
    final @property drawCounter()   const pure nothrow { return mDrawCounter; }
    final @property updateCounter(int value) pure nothrow { mUpdateCounter = value; }
    final @property drawCounter(int value)   pure nothrow { mDrawCounter   = value; }

    this()
    {
        // Constructor code
    }

    @property connections() inout pure nothrow 
    {
        assert(mConnections.length > 0);
        return mConnections[];
    }

    void draw(T)(in auto ref T renderer) const pure nothrow
    {
    }

    final void onAddedToRoom(ref EntityRef eref) pure nothrow
    {
        mConnections.put(eref);
    }

    final void onRemovedFromRoom(in ref EntityRef eref) pure nothrow
    {
        foreach(i,const ref c; mConnections[])
        {
            if(eref.id == c.id)
            {
                mConnections[i] = mConnections[$ - 1];
                return;
            }
        }
        assert(false, "onRemovedFromRoom invalid eref");
    }
}