module game.renderer.texture;

import gamelib.math;
import gamelib.util;
import gamelib.graphics.surfaceview;

final class Texture(ColT)
{
private:
    ColT[]        mData;
    immutable int mWidth;
    immutable int mHeight;
    immutable int mPitch;
    ColT[]        mLockBuffer;
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
    @property size_t pitch()  const pure nothrow { return mPitch * ColT.sizeof; }
    @property auto   data()   inout pure nothrow { return mData.ptr; }

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
            mData[0..$] = mLockBuffer[0..$];
            mLockBuffer.length = 0;
        }
    }

    auto get(T)(in T u, in T v) const pure nothrow
    {
        const tx = cast(int)(u * mWidth)  & (mWidth  - 1);
        const ty = cast(int)(v * mHeight) & (mHeight - 1);
        return mData[tx + ty * mPitch];
    }
    /*void getLine(int W,T)(in T u, in T v, in T du, in T dv, ColT[] ret) const pure nothrow
    {
        static assert(W > 0);
        static assert(W <= Border);
        import gamelib.fixedpoint;
        enum Frac = 10;
        alias Fix = FixedPoint!(32 - Frac,Frac,int);
        const wmask = (mWidth  << Frac) - 1;
        const hmask = (mHeight << Frac) - 1;

        const fw     = cast(Fix)mWidth;
        const fh     = cast(Fix)mHeight;
        const tu     = (cast(Fix)u * fw) & wmask;
        const tv     = (cast(Fix)v * fh) & hmask;
        const dtu    = cast(Fix)du * fw;
        const dtv    = cast(Fix)dv * fh;
        auto  offset = tu  + mPitch * tv;
        const inc    = dtu + mPitch * dtv;
        const ptr    = mData.ptr;
        foreach(i;TupleRange!(0,W))
        {
            ret[i] = ptr + cast(size_t)offset;
            offset += inc;
        }
    }*/
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

