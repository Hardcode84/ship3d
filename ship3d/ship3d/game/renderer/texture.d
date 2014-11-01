module game.renderer.texture;

import gamelib.math;
import gamelib.util;
import gamelib.graphics.surfaceview;

final class Texture(Base) : Base
{
private:
    alias DataT = Base.ColorArrayType;
    DataT[]        mData;
    immutable int mWidth;
    immutable int mHeight;
    immutable int mPitch;
    DataT[]        mLockBuffer;
    int           mLockCount = 0;
public:
    this(int w, int h)
    {
        assert(w > 0);
        assert(h > 0);
        assert(ispow2(w));
        assert(ispow2(h));
        mWidth  = w;
        mHeight = h;
        mPitch  = w;
        mData.length = mPitch * mHeight;
        import gamelib.types;
        mData[] = ColorBlue;
    }

    @property auto   width()  const pure nothrow { return mWidth; }
    @property auto   height() const pure nothrow { return mHeight; }
    @property size_t pitch()  const pure nothrow { return mPitch * DataT.sizeof; }
    @property auto   data()   inout pure nothrow { return mData.ptr; }

    auto lock() pure nothrow
    {
        assert(mLockCount >= 0);
        if(mLockCount == 0)
        {
            mLockBuffer.length = width * height;
        }
        ++mLockCount;
        return SurfaceView!(DataT)(width,height,width * DataT.sizeof, mLockBuffer.ptr);
    }

    void unlock() pure nothrow
    {
        assert(mLockCount > 0);
        if(0 == --mLockCount)
        {
            mData[0..$] = mLockBuffer[0..$];
            mLockBuffer.length = 0;
        }
    }

    auto get(T)(in T u, in T v) const pure nothrow
    {
        const tx = cast(int)(u * mWidth)  & (mWidth  - 1);
        const ty = cast(int)(v * mHeight) & (mHeight - 1);
        return getColor(mData[tx + ty * mPitch]);
    }
}

void fillChess(T)(auto ref T surf)
{
    import gamelib.types;
    auto view = surf.lock();
    scope(exit) surf.unlock();
    foreach(y;0..surf.height)
    {
        foreach(x;0..surf.width)
        {
            if((x / 15) % 2 == (y / 15) % 2)
            {
                view[y][x] = ColorGreen;
            }
            else
            {
                view[y][x] = ColorRed;
            }
        }
    }
}

