module game.world;

import gamelib.graphics.surface;
import gamelib.graphics.graph;

import game.units;
import game.rasterizer;

final class World
{
private:
    bool mQuitReq = false;
public:
    alias SurfT  = FFSurface!ColorT;
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

    void draw(SurfT surf)
    {
        //surf.lock();
        //scope(exit) surf.unlock();
        /*vec4[3] verts;
        verts[0] = vec4(10,10,0,0);
        verts[1] = vec4(100,10,0,0);
        verts[2] = vec4(100,100,0,0);*/
        Vertex[3] verts;
        verts[0].pos = vec4(10,10,0,0);
        verts[1].pos = vec4(100,50,0,0);
        verts[2].pos = vec4(10,100,0,0);
        Rasterizer!SurfT rast = surf;
        rast.drawTriangle(verts);
    }
}

