module game.generators.texturegen;

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
    palette_t mPalette;
    texture_t[TextureDesc] mTextures;

    void createPalette()
    {
        const ColorT[] colors = [
            ColorYellow,
            ColorCyan,
            ColorRed,
            ColorBlue,
            ColorGreen,
            ColorMagenta,
            ColorWhite];
        enum GradNum = 8;
        ColorT[256] data = ColorBlack;
        foreach(i,c; colors[])
        {
            const startInd = i * GradNum;
            const endInd = startInd + GradNum;
            auto line = data[startInd..endInd];
            ColorT.interpolateLine!GradNum(line, c, ColorBlack);
        }
        mPalette = new palette_t(data[]);
    }

    auto generateTexture(in ref TextureDesc desc)
    {
        auto ret = new texture_t(256, 256);
        ret.palette = mPalette;
        fillChess(ret, cast(ubyte)255, cast(ubyte)desc.i);
        return ret;
    }
public:
    this(uint seed)
    {
        createPalette();
    }

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

