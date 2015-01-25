module game.renderer.light;

import std.range;

import game.units;

struct Light
{
@nogc:
pure nothrow:
private:
    vec3_t mPos;
    LightColorT mColorInd;
public:
    this(in vec3_t pos, LightColorT colorInd)
    {
        mPos = pos;
        mColorInd = colorInd;
    }

    @property pos()   const { return mPos; }
    @property color() const { return mColorInd; }
}

final class LightController
{
@nogc:
pure nothrow:
private:
    const light_palette_t mPalette;
    enum LightRadius = 100.0f;
    enum ConstantsAtt = 1.0f;
    enum LinearAtt = 2.0f / LightRadius;
    enum QuadraticAtt = 1.0f / (LightRadius ^^ 2);
    private static auto computeAttenuation(pos_t dist)
    {
        return 1.0f / (ConstantsAtt + LinearAtt * dist + QuadraticAtt * dist * dist);
    }
public:
    this(in light_palette_t palette)
    {
        mPalette = palette;
    }

    auto calcLight(LightRange)(in vec3_t pos, in vec3_t normal, in LightRange lights, LightColorT ambient) const if(isInputRange!LightRange)
    {
        LightColorT result = ambient;
        foreach(i,const ref l; lights[])
        {
            const dpos = l.pos - pos;
            const ndl = dot(normal,dpos);
            if(ndl <= 0) continue;
            const dist = dpos.magnitude;
            const ndl1 = ndl / dist;
            enum GradNum = 1 << LightBrightnessBits;
            enum Mask = GradNum - 1;
            const val = cast(int)(((l.color & Mask)) * ndl1 * computeAttenuation(dist));
            assert(val >= 0,debugConv(val));
            assert(val < GradNum,debugConv(val));
            const col = val | (l.color & ~Mask);
            result = mPalette.blend(result, col);
        }
        return result;
    }
}

