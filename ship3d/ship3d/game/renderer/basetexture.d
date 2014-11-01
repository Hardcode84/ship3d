module game.renderer.basetexture;

import game.renderer.palette;

class BaseTextureRGB(ColT)
{
protected:
    alias ColorArrayType = ColT;
    final auto getColor(in ColT col) const pure nothrow
    {
        return col;
    }
}

class BaseTexturePaletted(ColT)
{
private:
    alias PalT = const(Palette!ColT);
    PalT mPalette;
protected:
    alias ColorArrayType = ubyte;
    final auto getColor(ubyte col) const pure nothrow
    {
        assert(mPalette !is null);
        return mPalette[col];
    }
public:
    @property auto palette() const pure nothrow { return mPalette; }
    @property void palette(in PalT p) pure nothrow { mPalette = p; }
}

