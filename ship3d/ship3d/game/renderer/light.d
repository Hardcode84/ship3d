module game.renderer.light;

import game.units;

struct Light
{
pure nothrow:
private:
    vec3_t mPos;
    int mColorInd;
public:
    this(in vec3_t pos, int colorInd)
    {
        mPos = pos;
        mColorInd = colorInd;
    }

    @property pos()   const { return mPos; }
    @property color() const { return mColorInd; }
}

final class LightController
{
pure nothrow:
private:
    light_palette_t mPalette;
public:
    this(light_palette_t palette)
    {
        mPalette = palette;
    }

    auto calcLight(in vec3_t pos, in vec3_t normal, in Light[] lights, int ambient) const
    {
        int result = ambient;
        foreach(i,const ref l; lights[])
        {
            const dpos = l.pos - pos;
            const ndl = dot(normal,dpos);
            if(ndl <= 0) continue;
            const dist = dpos.magnitude;
            const ndl1 = ndl / dist;
            enum GradNum = 1 << LightPaletteBits;
            enum Mask = GradNum - 1;
            const val = cast(int)(((l.color & Mask) >> ((cast(int)dist) / LightUnitDist)) * ndl1);
            const col = val | (l.color & ~Mask);
            result = mPalette.blend(result, col);
        }
        return result;
    }
}

