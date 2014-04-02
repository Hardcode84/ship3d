module game.world;

import gamelib.graphics.surface;
import gamelib.graphics.graph;

import game.units;
import game.renderer.rasterizer;

final class World
{
private:
    bool mQuitReq = false;
    mat4 mProjMat;
    immutable Size mSize;
public:
    alias SurfT  = FFSurface!ColorT;
    this(in Size sz)
    {
        mSize = sz;
        mProjMat = mat4.perspective(sz.w,sz.h,90,1,10);
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
        /*verts[0].pos = vec4(10,10,0,0);
        verts[1].pos = vec4(100,50,0,0);
        verts[2].pos = vec4(10,100,0,0);*/

        verts[0].pos = vec4(-1,-1,7,0);
        verts[1].pos = vec4(1,-1,7,0);
        verts[2].pos = vec4(1,1,7,0);

        foreach(i,v;verts)
        {
            verts[i].pos = mProjMat * v.pos;
            verts[i].pos = verts[i].pos / verts[i].pos.w;
            verts[i].pos.x = verts[i].pos.x * mSize.w + mSize.w / 2;
            verts[i].pos.y = verts[i].pos.y * mSize.h + mSize.h / 2;
        }
        Rasterizer!SurfT rast = surf;
        rast.drawTriangle(verts);
    }
}

