module game.world;

import gamelib.types;

import gamelib.graphics.surface;

final class World
{
private:
    bool mQuitReq = false;
public:
    alias ColorT = Color;
    this()
    {
        // Constructor code
    }

    void handleQuit() pure nothrow
    {
        mQuitReq = true;
    }

    bool update()
    {
        return !mQuitReq;
    }

    void draw(FFSurface!ColorT surf)
    {
    }
}

