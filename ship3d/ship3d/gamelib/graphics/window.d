module gamelib.graphics.window;

import std.typetuple;
import std.string;
import std.conv;
import std.exception;
import derelict.sdl2.sdl;

import gamelib.types;
import gamelib.graphics.surface;

class ColorFormatException : Exception
{
    @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}

final class Window
{
package:
    SDL_Window* mWindow = null;
    Surface mCachedSurf = null;
public:
    this(in string title, in int width, in int height, Uint32 flags = 0)
    {
        mixin SDL_CHECK_NULL!(`mWindow = SDL_CreateWindow(toStringz(title),
                                   SDL_WINDOWPOS_UNDEFINED,
                                   SDL_WINDOWPOS_UNDEFINED,
                                   width,
                                   height,
                                   flags)`);
    }

    ~this() const pure nothrow
    {
        assert(!mWindow);
    }

    @property string title()
    {
        assert(mWindow);
        return to!string(SDL_GetWindowTitle(mWindow)).idup;
    }

    @property void title(in string t) nothrow
    {
        assert(mWindow);
        SDL_SetWindowTitle(mWindow, toStringz(t));
    }

    void dispose() nothrow
    {
        if(mWindow)
        {
            SDL_DestroyWindow(mWindow);
            mWindow = null;
            if(mCachedSurf)
            {
                mCachedSurf.dispose();
                mCachedSurf = null;
            }
        }
    }

    @property auto size() nothrow
    {
        assert(mWindow);
        Point ret;
        SDL_GetWindowSize(mWindow, &ret.x, &ret.y);
        return ret;
    }

    //do not dispose returned surface
    @property auto surface()
    {
        assert(mWindow);
        if(mCachedSurf is null)
        {
            SDL_Surface* surf = null;
            mixin SDL_CHECK_NULL!(`surf = SDL_GetWindowSurface(mWindow)`);
            const fmt = surf.format;
            //try to create typed surface
            if(1 == fmt.BytesPerPixel)
            {
                mCachedSurf = new FFSurface!ubyte(surf);
            }
            else
            {
                alias Types32 = TypeTuple!(RGBA8888Color); //TODO: more formats
                foreach(f;Types32)
                {
                    if((mCachedSurf is null) &&
                       (f.sizeof == fmt.BytesPerPixel) &&
                       (f.rmask == fmt.Rmask) &&
                       (f.gmask == fmt.Gmask) &&
                       (f.bmask == fmt.Bmask) &&
                       (f.amask == fmt.Amask))
                    {
                        mCachedSurf = new FFSurface!f(surf);
                    }
                }
            }

            if(mCachedSurf is null)
            {
                //unknown format, fallback to untyped
                mCachedSurf =  new Surface(surf);
            }
        }
        return mCachedSurf;
    }

    @property auto surface(T)()
    {
        return enforce(cast(FFSurface!T)surface(), new ColorFormatException("Invalid pixel format: "~T.stringof));
    }

    void updateSurface(Surface surf = null)
    {
        assert(mWindow);
        if(surf !is null && surf !is mCachedSurf)
        {
            surface.blit(surf);
        }
        mixin SDL_CHECK!(`SDL_UpdateWindowSurface(mWindow)`);
    }

    @property auto formatString()
    {
        assert(mWindow);
        return text(SDL_GetPixelFormatName(SDL_GetWindowPixelFormat(mWindow))).idup;
    }
}