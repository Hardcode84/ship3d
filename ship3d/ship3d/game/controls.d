module game.controls;

enum Actions
{
    NONE = 0,
    FORWARD,
    BACKWARD,
    STRAFE_LEFT,
    STRAFE_RIGHT,
    ROLL_LEFT,
    ROLL_RIGHT
}

class Controls
{
private:
    immutable Actions[int] mActionsMap;
public:
    this(in Actions[int] m)
    {
        import std.exception: assumeUnique;
        auto temp = m.dup;
        mActionsMap = assumeUnique(temp);
    }
@nogc:
pure nothrow:
    Actions map(int key)
    {
        auto p = (key in mActionsMap);
        if(p !is null)
        {
            return *p;
        }
        return Actions.NONE;
        //return mActionsMap.get(key, Actions.NONE);
    }
}

