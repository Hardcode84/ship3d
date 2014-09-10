module game.world;

import gamelib.graphics.surface;
import gamelib.graphics.graph;

import game.units;
import game.renderer.rasterizer;
import game.renderer.rasterizerhp;
import game.renderer.texture;

final class World
{
private:
    bool mQuitReq = false;
    immutable mat4 mProjMat;
    immutable Size mSize;
    Texture!ColorT mTexture;
public:
    alias SurfT  = FFSurface!ColorT;
    this(in Size sz)
    {
        mSize = sz;
        mProjMat = mat4.perspective(sz.w,sz.h,90,0.1,1000);
        mTexture = new Texture!ColorT(256,256);
        fillChess(mTexture);
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
        surf.fill(ColorWhite);
        Vertex[4] verts;

        verts[0].pos  = vec4(-1,-1,0,1);
        verts[0].tpos = vec2(0,0);
        verts[0].color = ColorRed;
        verts[1].pos  = vec4( 1,-1,0,1);
        verts[1].tpos = vec2(1,0);
        verts[1].color = ColorBlue;
        verts[2].pos  = vec4( 1, 1,0,1);
        verts[2].tpos = vec2(1,1);
        verts[2].color = ColorGreen;
        verts[3].pos  = vec4(-1, 1,0,1);
        verts[3].tpos = vec2(0,1);
        verts[3].color = ColorWhite;

        static float si = 1;
        mat4 t = mProjMat * mat4.translation(0,0,-3) * mat4.yrotation(si);
        //si += 0.005;

        foreach(i;0..verts.length)
        {
            verts[i].pos = t * verts[i].pos;
            const w = verts[i].pos.w;
            verts[i].pos = verts[i].pos / w;
            verts[i].pos.w = w;
            verts[i].pos.x = verts[i].pos.x * mSize.w + mSize.w / 2;
            verts[i].pos.y = verts[i].pos.y * mSize.h + mSize.h / 2;
        }
        RasterizerHP!(SurfT,typeof(mTexture)) rast = surf;
        rast.texture = mTexture;
        foreach(i;0..1)
        {
            rast.drawIndexedTriangle(verts, [0,1,2]);
            rast.drawIndexedTriangle(verts, [0,2,3]);
        }
    }
}

