module game.topology.plane;

import game.units;

struct Plane
{
private:
    immutable vec3_t mNormal;
    immutable pos_t  mD;
public:
pure nothrow:
    this(V)(in V v0, in V v1, in V v2)
    {
        mNormal = cross((v1.xyz - v0.xyz),(v2.xyz - v0.xyz)).normalized;
    }

    pos_t distance(in vec3_t pos) const
    {
        return 0;
    }

    @property vec3_t normal() const
    {
        return mNormal;
    }
}

