module game.controls;

import derelict.sdl2.sdl;

import gamelib.variant;
public import gamelib.variant: visit, tryVisit;

enum KeyActions
{
    FORWARD,
    BACKWARD,
    STRAFE_LEFT,
    STRAFE_RIGHT,
    ROLL_LEFT,
    ROLL_RIGHT
}

struct KeyEvent
{
    KeyActions action;
    bool pressed;
}

struct CursorEvent
{
    float x;
    float y;
    float dx;
    float dy;
}

alias InputEvent = Algebraic!(KeyEvent,CursorEvent);

struct ControlSettings
{
    KeyActions[int] keymap;
    float cursorSensX = 1.0f;
    float cursorSensY = 1.0f;

    this(this)
    {
        keymap = keymap.dup;
    }
}

final class Controls
{
private:
    immutable ControlSettings mSettings;

    alias ListenerT = void delegate(in InputEvent);
    ListenerT mListener;

public:
    this(in ControlSettings settings, ListenerT listener)
    {
        assert(listener !is null);
        mSettings = cast(immutable(ControlSettings))settings;
        mListener = listener;
    }

    void onSdlEvent(in ref SDL_Event e)
    {
        switch(e.type)
        {
            case SDL_KEYDOWN:
            case SDL_KEYUP:
            {
                auto pAction = (e.key.keysym.scancode in mSettings.keymap);
                if(pAction !is null)
                {
                    mListener(InputEvent(KeyEvent(*pAction, SDL_KEYDOWN == e.type)));
                }
            }
            break;
            case SDL_MOUSEMOTION:
            {

                CursorEvent event = {x:  e.motion.x * mSettings.cursorSensX,
                                           y:  e.motion.y * mSettings.cursorSensY,
                                           dx: e.motion.xrel * mSettings.cursorSensX,
                                           dy: e.motion.yrel * mSettings.cursorSensY};
                mListener(InputEvent(event));
            }
            break;
            default:
        }
    }
}

