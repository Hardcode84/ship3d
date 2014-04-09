module gamelib.graphics.surface;

import gamelib.types;

import derelict.sdl2.sdl;

class Surface
{
package:
    SDL_Surface* mSurface = null;
    bool mOwned = true;
    int mLockCount = 0;
    immutable int mWidth;
    immutable int mHeight;
    this(SDL_Surface* surf)
    {
        assert(surf);
        mWidth   = surf.w;
        mHeight  = surf.h;
        mSurface = surf;
        mOwned = false;
    }
public:
final:
    this(int width,
         int height,
         int depth,
         Uint32 Rmask = 0x000000ff,
         Uint32 Gmask = 0x0000ff00,
         Uint32 Bmask = 0x00ff0000,
         Uint32 Amask = 0xff000000,
         void* pixels = null,
         int pitch = 0)
    {
        if(pixels is null)
        {
            mixin SDL_CHECK_NULL!(`mSurface = SDL_CreateRGBSurface(0,width,height,depth,Rmask,Gmask,Bmask,Amask)`);
        }
        else
        {
            mixin SDL_CHECK_NULL!(`mSurface = SDL_CreateRGBSurfaceFrom(pixels,width,height,depth,pitch,Rmask,Gmask,Bmask,Amask)`);
        }
        mWidth = width;
        mHeight = height;
    }
    ~this() const pure nothrow
    {
        assert(!mSurface);
    }

    void dispose() nothrow
    {
        if(mSurface)
        {
            assert(0 == mLockCount);
            if(mOwned)
            {
                SDL_FreeSurface(mSurface);
            }
            mSurface = null;
        }
    }

    @property auto width()  const pure nothrow { return mWidth; }
    @property auto height() const pure nothrow { return mHeight; }
    @property auto data()   inout pure nothrow 
    {
        assert(mSurface);
        assert(isLocked);
        return mSurface.pixels;
    }
    @property auto pitch() const pure nothrow
    {
        assert(mSurface);
        assert(isLocked);
        return mSurface.pitch;
    }

    void lock()
    {
        assert(mSurface);
        if(0 == mLockCount)
        {
            mixin SDL_CHECK!(`SDL_LockSurface(mSurface)`);
        }
        ++mLockCount;
    }
    void unlock() nothrow
    {
        assert(mSurface);
        assert(mLockCount > 0);
        if(1 == mLockCount)
        {
            SDL_UnlockSurface(mSurface);
        }
        --mLockCount;
    }
    @property bool isLocked() const pure nothrow
    {
        assert(mSurface);
        assert(mLockCount >= 0);
        return mLockCount > 0;
    }

    void blit(Surface src)
    {
        assert(mSurface);
        assert(src.mSurface);
        mixin SDL_CHECK!(`SDL_BlitSurface(src.mSurface,null,mSurface,null)`);
    }
}

//Fixed format surface
final class FFSurface(ColorT) : Surface
{
package:
    static assert(ColorT.sizeof <= 4);
    this(SDL_Surface* surf)
    {
        super(surf);
    }
public:
    this(int width,
         int height,
         void* pixels = null,
         int pitch = 0)
    {
        enum depth = ColorT.sizeof * 8;
        static if(depth > 8)
        {
            Uint32 Rmask = ColorT.rmask;
            Uint32 Gmask = ColorT.gmask;
            Uint32 Bmask = ColorT.bmask;
            Uint32 Amask = ColorT.amask;
            super(width, height, depth, Rmask, Gmask, Bmask, Amask, pixels, pitch);
        }
        else
        {
            super(width, height, depth, 0, 0, 0, 0, pixels, pitch);
        }
    }

    final auto opIndex(int y) pure nothrow
    {
        assert(isLocked);
        import gamelib.graphics.surfaceview;
        SurfaceView!ColorT view = this;
        return view[y];
    }

    void fill(in ColorT col)
    {
        assert(mSurface);
        union tempunion_t
        {
            ColorT c;
            Uint32 i;
        }
        tempunion_t u;
        u.i = 0;
        u.c = col;
        mixin SDL_CHECK!(`SDL_FillRect(mSurface, null, u.i)`);
    }
}