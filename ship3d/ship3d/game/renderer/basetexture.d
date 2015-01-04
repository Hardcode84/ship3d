module game.renderer.basetexture;

import game.renderer.palette;

import gamelib.math;
import gamelib.util;
import gamelib.graphics.surfaceview;

class BaseTexture(ColT)
{
private:
    immutable int mWidth;
    immutable int mHeight;
    ColT[]        mLockBuffer;
    int           mLockCount = 0;
protected:
    abstract void setData(in ColT[] data) pure nothrow;
public:
    this(int w, int h)
    {
        assert(w > 0);
        assert(h > 0);
        assert(ispow2(w));
        assert(ispow2(h));
        assert(w == h);
        mWidth  = w;
        mHeight = h;
    }

final:
    @property auto width()  const pure nothrow { return mWidth; }
    @property auto height() const pure nothrow { return mHeight; }

    auto lock() pure nothrow
    {
        assert(mLockCount >= 0);
        if(mLockCount == 0)
        {
            mLockBuffer.length = width * height;
        }
        ++mLockCount;
        return SurfaceView!(ColT)(width,height,width * ColT.sizeof, mLockBuffer.ptr);
    }

    void unlock() pure nothrow
    {
        assert(mLockCount > 0);
        if(0 == --mLockCount)
        {
            setData(mLockBuffer);
            mLockBuffer.length = 0;
        }
    }
}

abstract class BaseTextureRGB(ColT) : BaseTexture!ColT
{
protected:
    alias ColorType = ColT;
    alias ColorArrayType = ColT;
    static auto getColor(in ColT col) pure nothrow
    {
        return col;
    }
    static auto avgColor(in ColT col00, in ColT col10, in ColT col01, in ColT col11) pure nothrow
    {
        return ColT.average(ColT.average(col00,col10),ColT.average(col01,col11));
    }
public:
    this(int w, int h)
    {
        super(w, h);
    }
}

abstract class BaseTexturePaletted(ColT) : BaseTexture!ubyte
{
private:
    alias PalT = Palette!ColT;
    PalT mPalette;
protected:
    alias ColorType = ColT;
    alias ColorArrayType = ubyte;
    final auto getColor(ubyte col) const pure nothrow
    {
        assert(mPalette !is null);
        return mPalette[col];
    }
public:
    this(int w, int h)
    {
        super(w, h);
    }

    @property auto palette() const pure nothrow { return mPalette; }
    @property void palette(PalT p) pure nothrow { mPalette = p; }
}
