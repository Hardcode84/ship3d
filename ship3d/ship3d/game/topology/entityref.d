module game.topology.entityref;

import game.units;

import game.topology.room;
import game.entities.entity;

struct EntityRef
{
    union
    {
        Room room;
        package EntityRef* prev; //for allocator
    }
    Entity ent;
    vec3_t pos = vec3_t(0,0,0);
    quat_t dir = quat_t.identity;
    bool inside = true;
    vec3_t correction = vec3_t(0,0,0); //TODO
    bool remove = false;

    void updatePos(in vec3_t dpos) /*pure nothrow*/
    {
        assert(room !is null);
        //assert(!remove);
        room.updateEntityPos(&this, dpos);
    }
}

final class EntityRefAllocator
{
pure nothrow:
private:
    EntityRef* mLast = null;
public:
    this(size_t initialSize)
    {
        if(initialSize > 0)
        {
            EntityRef[] refs;
            refs.length = initialSize;
            refs[0].prev = null;
            foreach(i;1..initialSize)
            {
                refs[i].prev = &refs[i - 1];
            }
            mLast = &refs[$ - 1];
        }
    }
    EntityRef* allocate()
    {
        if(mLast is null)
        {
            return new EntityRef;
        }
        auto temp = mLast;
        mLast = temp.prev;
        *temp = EntityRef.init;
        return temp;
    }

    void free(EntityRef* ptr)
    {
        assert(ptr !is null);
        ptr.prev = mLast;
        mLast = ptr;
    }
}