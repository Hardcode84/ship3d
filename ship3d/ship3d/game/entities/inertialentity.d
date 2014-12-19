module game.entities.inertialentity;

public import game.entities.entity;

import game.units;
import game.world;

class InertialEntity : Entity
{
private:
    vec3_t mSpeed = vec3_t(0,0,0);
public:
    this(World w)
    {
        super(w);
    }

    override void update()
    {
        super.update();
        move(mSpeed);
        mSpeed *= 0.90f;
    }

final:
    void accelerate(in vec3_t accel)
    {
        mSpeed += accel;
    }
}

