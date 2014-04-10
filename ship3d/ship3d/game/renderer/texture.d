module game.renderer.texture;

import gamelib.math;
import gamelib.graphics.surfaceview;

final class Texture(ColT)
{
private:
    ColT[] mData;
    immutable int mWidth;
    immutable int mHeight;
    immutable size_t mPitch;
public:
    this(int w, int h)
    {
        assert(w > 0);
        assert(h > 0);
        assert(ispow2(w));
        assert(ispow2(h));
        mWidth = w;
        mHeight = h;
        mPitch = w;
        mData.length = mPitch * mHeight;
    }

    @property auto   width()  const pure nothrow { return mWidth; }
    @property auto   height() const pure nothrow { return mHeight; }
    @property size_t pitch()  const pure nothrow { return mPitch * ColT.sizeof; }
    @property auto   data()   inout pure nothrow { return mData.ptr; }

    auto view() pure nothrow
    {
        return SurfaceView!ColT(this);
    }

    auto view() const pure nothrow
    {
        return SurfaceView!(const(ColT))(this);
    }
}

void fillChess(T)(auto ref T surf)
{
    import gamelib.types;
    auto view = surf.view();
    foreach(y;0..surf.height)
    {
        foreach(x;0..surf.width)
        {
            if((x / 25) % 2 == (y / 25) % 2)
            {
                view[y][x] = ColorBlack;
            }
            else
            {
                view[y][x] = ColorWhite;
            }
        }
    }
}

