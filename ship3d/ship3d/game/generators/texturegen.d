module game.generators.texturegen;

import game.units;
import game.renderer.texture;

struct TextureDesc
{
    string name;
    int i;
}

struct TextureGen
{
private:
    texture_t[TextureDesc] mTextures;
    auto generateTexture(in ref TextureDesc desc) pure nothrow
    {
        auto ret = new texture_t(256, 256);
        fillChess(ret);
        return ret;
    }
public:
    this(uint seed) pure nothrow
    {
        // Constructor code
    }

    auto getTexture(in TextureDesc desc) pure nothrow
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

