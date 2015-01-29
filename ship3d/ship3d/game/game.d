module game.game;

import std.random;
import std.algorithm;
import std.conv;

import gamelib.types;
import gamelib.autodispose;
import gamelib.core;
import gamelib.graphics.window;
import gamelib.graphics.surface;

import derelict.sdl2.sdl;

import game.controls;

import game.units;
import game.world;

scope final class Game
{
private:
    enum UpdateInterval = 15;
    enum MaxUpdates = 100;

    @auto_dispose Core mCore;
    @auto_dispose Window mWindow;
    @auto_dispose FFSurface!ColorT mSurface;

    World mWorld;

    uint mLastTicks;
    int mWidth = 0;
    int mHeight = 0;

    uint mFPSCounter = 0;
    uint mLastFPSTicks = 0;
    uint mUpdateCounter = 0;

    float mFPS = 0.0f;

    bool mShowOverlay = false;

    Controls mControls;
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
                mControls.onSdlEvent(e);
                switch(e.type)
                {
                    case SDL_WINDOWEVENT:
                        processWindowEvent(e.window);
                        break;
                    case SDL_KEYDOWN:
                        if(SDL_SCANCODE_ESCAPE == e.key.keysym.scancode)
                        {
                            handleQuit();
                        }
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
            if(!mWindow.hidden)
            {
                draw();
                ++mFPSCounter;
                if((newTicks - mLastFPSTicks) > 2000)
                {
                    mFPS = cast(float)mFPSCounter / (cast(float)(newTicks - mLastFPSTicks) / 1000.0f);
                    mLastFPSTicks = newTicks;
                    mFPSCounter = 0;

                    auto totalSeconds = mUpdateCounter * UpdateInterval / 1000.0f;
                    import std.string: format;
                    auto str = format("%s %s %s", mFPS, totalSeconds, mUpdateCounter);
                    mWindow.title = str;
                    import std.stdio;
                    debug {}
                    else writeln(str);
                }
                present();
            }
        }
    }

private:
//pure nothrow:
    void setup(string[] args)
    {
        ControlSettings cSettings = {keymap: [SDL_SCANCODE_W:KeyActions.FORWARD,
                                              SDL_SCANCODE_S:KeyActions.BACKWARD,
                                              SDL_SCANCODE_A:KeyActions.STRAFE_LEFT,
                                              SDL_SCANCODE_D:KeyActions.STRAFE_RIGHT,
                                              SDL_SCANCODE_Q:KeyActions.ROLL_LEFT,
                                              SDL_SCANCODE_E:KeyActions.ROLL_RIGHT]};

        import std.getopt;
        uint seed = unpredictableSeed;
        import std.stdio;
        scope(exit) writeln("seed=",seed);
        bool fullscreen = false;
        bool fullscreenDesktop = false;
        mWidth  = 800;
        mHeight = 600;
        getopt(args,
               "seed",                 &seed,
               "fullscreen|f",         &fullscreen,
               "fullscreenDesktop|fd", &fullscreenDesktop,
               "width|w",              &mWidth,
               "height|h",             &mHeight,
               "sensx",                &cSettings.cursorSensX,
               "sensy",                &cSettings.cursorSensY);
        enforce(mWidth > 0 && mHeight > 0 && 0 == mWidth % 8 && 0 == mHeight % 8, "Invalid resolution");
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
        mWorld = new World(Size(mWidth,mHeight),seed);
        mWindow = new Window("game", mWidth, mHeight, windowFlags);
        initWindowSurface();
        mControls = new Controls(cSettings, &mWorld.onInputEvent);
        mixin SDL_CHECK!(`SDL_SetRelativeMouseMode(true)`);
    }

    void initWindowSurface()
    {
        assert(mWindow !is null);
        mWindow.setSize(mWidth,mHeight);
        if(mSurface !is null)
        {
            mSurface.dispose();
            mSurface = null;
        }
        import std.stdio;
        writeln(mWindow.formatString);
        try
        {
            mSurface = mWindow.surface!ColorT;
        }
        catch(ColorFormatException e)
        {
            import std.stdio;
            writeln(e.msg);
            const s = mWindow.size;
            mSurface = new FFSurface!ColorT(s.x, s.y);
        }
    }

    void handleQuit()
    {
        mWorld.handleQuit();
    }

    void processWindowEvent(in ref SDL_WindowEvent event)
    {
        assert(mWindow !is null);
        if(event.windowID == mWindow.winId)
        {
            //debugOut(event.event);
            switch(event.event)
            {
                case SDL_WINDOWEVENT_MINIMIZED:
                case SDL_WINDOWEVENT_HIDDEN:
                    break;
                case SDL_WINDOWEVENT_SHOWN:
                case SDL_WINDOWEVENT_RESTORED:
                    initWindowSurface();
                    break;
                default: break;
            }
        }
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

