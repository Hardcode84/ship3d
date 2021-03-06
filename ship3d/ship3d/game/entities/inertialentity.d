﻿module game.entities.inertialentity;

public import game.entities.entity;

import game.units;
import game.world;

class InertialEntity : Entity
{
protected:
    vec3_t mSpeed = vec3_t(0,0,0);
public:
    this(World w)
    {
        super(w);
    }

    final @property speed() const { return mSpeed; }

    override void update()
    {
        move(mSpeed);
        super.update();
        mSpeed *= 0.95f;
        assert(mSpeed.magnitude_squared <= radius^^2, debugConv(mSpeed.magnitude_squared));
    }

    override void updatePos()
    {
        //mSpeed = posDelta * 0.95f;
        super.updatePos();
    }

final:
    void accelerate(in vec3_t accel)
    {
        mSpeed += accel;
    }
}

