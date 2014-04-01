module gamelib.graphics.renderer2d.renderer;

import std.string;
import gamelib.types;
import gamelib.graphics.window;
import gamelib.graphics.renderer2d.texture;
import derelict.sdl2.sdl;

struct RendererProps
{
    int index = -1;
    bool hardware = true;
    bool vsync = true;
    bool renderTargetSupport = false;
}

final class Renderer
{
package:
    SDL_Renderer* mRenderer = null;
public:
    this(Window wnd, in RendererProps props = RendererProps())
    {
        assert(wnd);
        assert(wnd.mWindow);
        Uint32 flags = (props.hardware ? SDL_RENDERER_ACCELERATED : SDL_RENDERER_SOFTWARE);
        if(props.vsync)
        {
            flags |= SDL_RENDERER_PRESENTVSYNC;
        }
        if(props.renderTargetSupport)
        {
            flags |= SDL_RENDERER_TARGETTEXTURE;
        }
        mixin SDL_CHECK_NULL!(`mRenderer = SDL_CreateRenderer(wnd.mWindow, props.index, flags)`);
    }

    ~this() const pure nothrow
    {
        assert(!mRenderer);
    }

    void dispose() nothrow
    {
        if(mRenderer)
        {
            SDL_DestroyRenderer(mRenderer);
            mRenderer = null;
        }
    }

    void clear()
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_RenderClear(mRenderer)`);
    }

    void draw(Texture tex, in Rect* srcRect, in Rect* dstRect)
    {
        assert(mRenderer);
        assert(tex);
        assert(tex.mTexture);
        mixin SDL_CHECK!(`SDL_RenderCopy(mRenderer,tex.mTexture,srcRect,dstRect)`);
    }
    void draw(Texture tex, 
              in Rect* srcRect, 
              in Rect* dstRect,
              in double angle,
              in Point* center = null,
              in SDL_RendererFlip flip = SDL_FLIP_NONE)
    {
        assert(mRenderer);
        assert(tex);
        assert(tex.mTexture);
        mixin SDL_CHECK!(`SDL_RenderCopyEx(mRenderer,tex.mTexture,srcRect,dstRect,angle,center,flip)`);
    }

    @property void drawColor(in Color col)
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_SetRenderDrawColor(mRenderer,col.r,col.g,col.b,col.a)`);
    }

    void drawLines(in Point[] points)
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_RenderDrawLines(mRenderer,points.ptr,points.length)`);
    }

    void drawPoints(in Point[] points)
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_RenderDrawPoints(mRenderer,points.ptr,points.length)`);
    }

    void drawRects(in Rect[] rects)
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_RenderDrawRects(mRenderer,rects.ptr,rects.length)`);
    }

    void drawFilledRects(in Rect[] rects)
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_RenderFillRects(mRenderer,rects.ptr,rects.length)`);
    }

    void present()
    {
        assert(mRenderer);
        SDL_RenderPresent(mRenderer);
    }

    void setScale(in float scaleX, in float scaleY)
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_RenderSetScale(mRenderer,scaleX,scaleY)`);
    }

    @property auto viewport(in Rect rc)
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_RenderSetViewport(mRenderer,&rc)`);
    }

    @property auto clipRect(in Rect rc)
    {
        assert(mRenderer);
        mixin SDL_CHECK!(`SDL_RenderSetClipRect(mRenderer,&rc)`);
    }
}

