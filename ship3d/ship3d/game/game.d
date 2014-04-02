module game.game;

import std.algorithm;
import std.conv;

import gamelib.types;
import gamelib.autodispose;
import gamelib.core;
import gamelib.graphics.window;
import gamelib.graphics.surface;

import derelict.sdl2.sdl;

import game.units;
import game.world;

scope final class Game
{
private:
    enum UpdateInterval = 50;
    enum MaxUpdates = 100;

    @auto_dispose Core mCore;
    @auto_dispose Window mWindow;
    @auto_dispose FFSurface!ColorT mSurface;

    World mWorld;

    uint mLastTicks;
    /*static immutable Actions[int] KeyMap;
    static this()
    {
        KeyMap = [SDL_SCANCODE_UP:     Actions.UP,
                  SDL_SCANCODE_DOWN:   Actions.DOWN,
                  SDL_SCANCODE_LEFT:   Actions.LEFT,
                  SDL_SCANCODE_RIGHT:  Actions.RIGHT,
                  SDL_SCANCODE_ESCAPE: Actions.ESC,
                  SDL_SCANCODE_Z:      Actions.ATTACK,
                  SDL_SCANCODE_LSHIFT: Actions.BOOST];
    }*/

    uint mFPSCounter = 0;
    uint mLastFPSTicks = 0;
    uint mUpdateCounter = 0;

    float mFPS = 0.0f;

    bool mShowOverlay = false;

public:

    this(string[] args)
    {
        scope(failure) dispose();
        setup(args);
    }

    ~this()
    {
        dispose();
    }

    void run()
    {
        SDL_Event e;
        bool quit = false;
        mLastTicks = SDL_GetTicks();
        mLastFPSTicks = mLastTicks;
        mainloop: while(!quit)
        {
            while(SDL_PollEvent(&e))
            {
                switch(e.type)
                {
                    case SDL_KEYDOWN:
                    case SDL_KEYUP:
                        processKeyEvent(e.key);
                        break;
                    case SDL_QUIT:
                        handleQuit();
                        break;
                    default:
                }
            }
            auto newTicks = SDL_GetTicks();
            auto updateCount = (newTicks - mLastTicks) / UpdateInterval;
            foreach(i;0..updateCount)
            {
                if(!update())
                {
                    quit = true;
                    break mainloop;
                }
                ++mUpdateCounter;
            }
            mLastTicks += UpdateInterval * updateCount;
            draw();
            ++mFPSCounter;
            if((newTicks - mLastFPSTicks) > 2000)
            {
                mFPS = cast(float)mFPSCounter / (cast(float)(newTicks - mLastFPSTicks) / 1000.0f);
                mLastFPSTicks = newTicks;
                mFPSCounter = 0;
            }
            present();
        }
    }

private:
    void setup(string[] args)
    {
        import std.getopt;
        bool fullscreen = false;
        bool fullscreenDesktop = false;
        int width  = 800;
        int height = 600;
        getopt(args,
               "fullscreen|f",         &fullscreen,
               "fullscreenDesktop|fd", &fullscreenDesktop,
               "width|w",              &width,
               "height|h",             &height);
        enforce(width > 0 && height > 0, "Invalid resolution");
        mCore = new Core(true);
        Uint32 windowFlags = 0;
        if(fullscreenDesktop)
        {
            windowFlags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
        }
        else if(fullscreen)
        {
            windowFlags |= SDL_WINDOW_FULLSCREEN;
        }
        mWindow = new Window("game",width,height, windowFlags);
        import std.stdio;
        writeln(mWindow.formatString);
        try
        {
            mSurface = mWindow.surface!ColorT;
        }
        catch(ColorFormatException e)
        {
            const s = mWindow.size;
            mSurface = new FFSurface!ColorT(s.x, s.y);
        }
        mWorld = new World(Size(width,height));
    }

    void handleQuit() pure nothrow
    {
        mWorld.handleQuit();
    }

    void processKeyEvent(in SDL_KeyboardEvent event) pure
    {
        if(event.repeat != 0)
        {
            return;
        }
        /*

        //debug
        {
            if(event.keysym.scancode == SDL_SCANCODE_F12 && event.type == SDL_KEYDOWN)
            {
                mShowOverlay = !mShowOverlay;
            }
        }

        auto ac = KeyMap.get(event.keysym.scancode, Actions.INVALID);
        if(Actions.INVALID != ac)
        {
            mWorld.processAction(ac, event.type == SDL_KEYDOWN);
        }
        */
    }

    bool update()
    {
        return mWorld.update();
    }

    void draw()
    {
        mWorld.draw(mSurface);
    }

    void present()
    {
        /*
        if(mShowOverlay)
        {
            import std.string: format;
            auto totalSeconds = mUpdateCounter * UpdateInterval / 1000.0f;
            auto f = mFontManager.font!"font1";
            auto sz = mWindow.size;
            Rect rc = {x: 10, y: 10, w: sz.x - 20, h: sz.y - 20};
            f.outText(mRenderer, rc, format("%s\n%s\n%s", mFPS, totalSeconds, mUpdateCounter));
        }
        mRenderer.present();
        */
        mWindow.updateSurface(mSurface);
    }

    mixin GenerateAutoDispose;
}

