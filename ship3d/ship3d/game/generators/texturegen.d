﻿module game.generators.texturegen;

import game.units;
import game.renderer.texture;
import game.renderer.palette;

struct TextureDesc
{
    ubyte i;
}

struct TextureGen
{
pure nothrow:
private:
    light_palette_t mLightPalette;
    palette_t mPalette;
    texture_t[TextureDesc] mTextures;

    void createLightPalette()
    {
        enum GradNum = 1 << LightBrightnessBits;
        const ColorT[] colors = [
            ColorWhite,
            ColorRed,
            ColorGreen,
            ColorBlue,
            ColorYellow,
            ColorCyan,
            ColorMagenta];
        ColorT[256] data = ColorBlack;
        foreach(i,c; colors[])
        {
            const startInd = i * GradNum;
            const endInd = startInd + GradNum;
            auto line = data[startInd..endInd];
            ColorT.interpolateLine!GradNum(line, ColorBlack, c);
        }
        mLightPalette = new light_palette_t(data[0..(1 << LightPaletteBits)]);
    }
    void createPalette()
    {
        //enum GradNum = 1 << PaletteBits;
        const ColorT[] colors = [
            ColorYellow,
            ColorCyan,
            ColorRed,
            ColorBlue,
            ColorGreen,
            ColorMagenta,
            ColorWhite];
        ColorT[256] data = ColorBlack;
        foreach(i,c; colors[])
        {
            data[i] = c;
            /*const startInd = i * GradNum;
            const endInd = startInd + GradNum;
            auto line = data[startInd..endInd];
            ColorT.interpolateLine!GradNum(line, c, ColorBlack);*/
        }
        mPalette = new palette_t(data[0..(1 << PaletteBits)], mLightPalette[]);
    }

    auto generateTexture(in ref TextureDesc desc)
    {
        auto ret = new texture_t(256, 256);
        ret.palette = mPalette;
        ret.fillChess(cast(ubyte)((1 << PaletteBits) - 1), cast(ubyte)(desc.i));
        //ret.fill(cast(ubyte)(desc.i));
        return ret;
    }
public:
    this(uint seed)
    {
        createLightPalette();
        createPalette();
    }

    @property lightPalette() inout { return mLightPalette; }

    auto getTexture(in TextureDesc desc)
    {
        auto p = (desc in mTextures);
        if(p is null)
        {
            auto t = generateTexture(desc);
            mTextures[desc] = t;
            return t;
        }
        return *p;
    }
}