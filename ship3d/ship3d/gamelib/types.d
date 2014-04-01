module gamelib.types;

public import std.conv: to;
public import std.exception: enforce;

import derelict.sdl2.sdl;
import derelict.sdl2.image;

alias SDL_Point Point;
alias SDL_Rect Rect;

struct Size
{
    int w, h;
}

struct Color
{
    ubyte r = 255;
    ubyte g = 255;
    ubyte b = 255;
    ubyte a = SDL_ALPHA_OPAQUE;
    enum format = SDL_PIXELFORMAT_RGBA8888;
    enum Uint32 rmask = 0x000000ff;
    enum Uint32 gmask = 0x0000ff00;
    enum Uint32 bmask = 0x00ff0000;
    enum Uint32 amask = 0xff000000;
}

enum Color ColorWhite = {r:255,g:255,b:255};
enum Color ColorBlack = {r:0  ,g:0  ,b:0  };
enum Color ColorGreen = {r:0  ,g:255,b:0  };
enum Color ColorRed   = {r:255,g:0  ,b:0  };
enum Color ColorBlue  = {r:0  ,g:0  ,b:255};
enum Color ColorTransparentWhite = {r:255,g:255,b:255, a: 0};

template Tuple(E...)
{
    alias E Tuple;
}

mixin template SDL_CHECK(string S, string getErr = "SDL_GetError()")
{
    auto temp = enforce(0 == (mixin(S)), "\"" ~ S ~ "\" failed: " ~ to!string(mixin(getErr)).idup);
}

mixin template SDL_CHECK_NULL(string S, string getErr = "SDL_GetError()")
{
    auto temp = enforce(null != (mixin(S)), "\"" ~ S ~ "\" failed: " ~ to!string(mixin(getErr)).idup);
}

struct TemplateColor(int Size, uint rm = 0, uint gm = 0, uint bm = 0, uint am = 0)
{
    static assert(Size > 0);
    static if(1 == Size)      ubyte data;
    else static if(2 == Size) ushort data;
    else static if(4 == Size) uint data;
    else static assert(false, "Invalid color size: "~to!string(Size));
    enum Uint32 rmask = rm;
    enum Uint32 gmask = gm;
    enum Uint32 bmask = bm;
    enum Uint32 amask = am;
}

alias I8Color = TemplateColor!1;
alias RGBA8888Color = Color;

unittest
{
    static assert(0 == SDL_PIXELFORMAT_UNKNOWN);
}
