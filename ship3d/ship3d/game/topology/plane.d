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
        mD      = -(v0.x * mNormal.x + v0.y * mNormal.y + v0.z * mNormal.z);
    }

    pos_t distance(in vec3_t pos) const
    {
        return pos.x * mNormal.x + pos.y * mNormal.y + pos.z * mNormal.z + mD;
    }

    @property vec3_t normal() const
    {
        return mNormal;
    }

    bool opEquals(in Plane p) const
    {
        const eps = 0.001f;
        return almost_equal(mNormal.x, p.mNormal.x, eps) &&
               almost_equal(mNormal.y, p.mNormal.y, eps) &&
               almost_equal(mNormal.z, p.mNormal.z, eps) &&
               almost_equal(mD, p.mD, eps);
    }
}

