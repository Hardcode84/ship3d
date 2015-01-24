module game.entities.lightentity;

import game.entities.entity;

class LightEntity : Entity
{
public:
    this(World w)
    {
        super(w, 20);
    }

    @property LightColorT color() const { return mColor; }

    override void onAddedToRoom(EntityRef* eref)
    {
        super.onAddedToRoom(eref);
        eref.room.addLight(eref);
        eref.lightEnt = this;
    }
    
    override void onRemovedFromRoom(EntityRef* eref)
    {
        super.onRemovedFromRoom(eref);
        eref.roomLightLink.unlink();
        eref.lightEnt = null;
    }

private:
    LightColorT mColor = 7;
}

