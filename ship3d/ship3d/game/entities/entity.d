﻿module game.entities.entity;

import std.algorithm;

import game.units;
import game.topology.room;
import game.topology.entityref;

class Entity
{
private:
    int mUpdateCounter = 0;
    int mDrawCounter   = 0;
    vec3_t      mRefPos = vec3_t(0,0,0);
    quat_t      mRefDir = quat_t.identity;
    EntityRef*[] mConnections;
public:
pure nothrow:
    final @property updateCounter() const    { return mUpdateCounter; }
    final @property drawCounter()   const    { return mDrawCounter; }
    final @property updateCounter(int value) { mUpdateCounter = value; }
    final @property drawCounter(int value)   { mDrawCounter   = value; }

    this()
    {
        // Constructor code
    }

    final @property connections() inout
    {
        assert(mConnections.length > 0);
        return mConnections[];
    }

    void draw(T)(in auto ref T renderer) const
    {
    }

    final void move(in ref vec3_t offset)
    {
        mRefPos += offset;
        foreach(ref c; mConnections[])
        {
        }
    }

    final void onAddedToRoom(EntityRef* eref)
    {
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
                return;
            }
        }
        assert(false, "onRemovedFromRoom invalid eref");
    }
}