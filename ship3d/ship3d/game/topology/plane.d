module game.topology.plane;

import game.units;

struct Plane
{
pure nothrow:
    pos_t distance(in vec3_t pos) const
    {
        return 0;
    }

    @property vec3_t normal() const
    {
        return vec3_t();
    }
}

