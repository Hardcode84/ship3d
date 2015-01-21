module game.entities.LightEntity;

import game.entities.entity;

import game.entities.lightref;

class LightEntity : Entity
{
public:
    this(World w)
    {
        super(w);
        mRadius = 20;
    }

    override void onAddedToRoom(EntityRef* eref)
    {
        super.onAddedToRoom(eref);
        updateLightRefs();
    }
    
    override void onRemovedFromRoom(EntityRef* eref)
    {
        super.onRemovedFromRoom(eref);
        updateLightRefs();
    }

private:
    void updateLightRefs()
    {
    }
}

