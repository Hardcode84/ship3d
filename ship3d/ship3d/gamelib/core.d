module gamelib.core;

import std.exception : enforce;
import std.conv;

import derelict.sdl2.sdl;
import derelict.sdl2.image;
import gamelib.types;

class Core
{
    this(bool video = true, bool sound = true)
    {
        scope(failure) dispose();
        DerelictSDL2.load();

        Uint32 sdlFlags = 0;
        if(video) sdlFlags |= SDL_INIT_VIDEO;
        if(sound) sdlFlags |= SDL_INIT_AUDIO;

        mixin SDL_CHECK!(`SDL_Init(sdlFlags)`);
        version(UseSdlImage)
        {
            DerelictSDL2Image.load();
            auto imgFormats = IMG_INIT_PNG;
            enforce(imgFormats & IMG_Init(imgFormats), "IMG_Init failed: " ~ to!string(IMG_GetError()).idup);
        }
    }

    void dispose()
    {
        version(UseSdlImage)
        {
            if(DerelictSDL2Image.isLoaded)
            {
                IMG_Quit();
                DerelictSDL2Image.unload();
            }
        }

        if(DerelictSDL2.isLoaded)
        {
            SDL_Quit();
            DerelictSDL2.unload();
        }
    }
}