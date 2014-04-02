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
        mProjMat = mat4.perspective(sz.w,sz.h,90,0.1,1000);
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
        surf.fill(ColorBlack);
        Vertex[3] verts;

        verts[0].pos = vec4(-1,-1,0,1);
        verts[1].pos = vec4( 1,-1,0,1);
        verts[2].pos = vec4( 1, 1,0,1);

        static float si = 0;
        mat4 t = mProjMat * mat4.translation(0.0,0.0,10) * mat4.yrotation(si);
        si += 0.01;

        foreach(i;0..verts.length)
        {
            verts[i].pos = t * verts[i].pos;
            verts[i].pos = verts[i].pos / verts[i].pos.w;
            verts[i].pos.x = verts[i].pos.x * mSize.w + mSize.w / 2;
            verts[i].pos.y = verts[i].pos.y * mSize.h + mSize.h / 2;
        }
        Rasterizer!SurfT rast = surf;
        rast.drawTriangle(verts);
    }
}

