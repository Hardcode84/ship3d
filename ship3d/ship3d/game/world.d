module game.world;

import gamelib.graphics.surface;
import gamelib.graphics.graph;
import gamelib.graphics.memsurface;

import game.units;
import game.renderer.rasterizer;
import game.renderer.rasterizerhp;
import game.renderer.rasterizerhp2;
import game.renderer.rasterizerhp3;
import game.renderer.texture;

final class World
{
private:
    bool mQuitReq = false;
    immutable mat4_t mProjMat;
    immutable Size mSize;
    pos_t mRot = 1;
    pos_t mYpos = 0;
    int mN = 0;
    Texture!ColorT mTexture;
    MemSurface!float mDepthBuff;
public:
    alias SurfT  = FFSurface!ColorT;
    this(in Size sz)
    {
        mSize = sz;
        mProjMat = mat4.perspective(sz.w,sz.h,90,0.1,1000);
        mTexture = new Texture!ColorT(256,256);
        mDepthBuff = new MemSurface!float(800,600);
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

    void processKey(int key) pure nothrow
    {
        const spd = 0.02;
        const asd = 0.02;
        if(SDL_SCANCODE_LEFT == key)
        {
            mRot += spd;
        }
        else if(SDL_SCANCODE_RIGHT == key)
        {
            mRot -= spd;
        }
        else if(SDL_SCANCODE_UP == key)
        {
            mYpos -= asd;
        }
        else if(SDL_SCANCODE_DOWN == key)
        {
            mYpos += asd;
        }
        else if(SDL_SCANCODE_SPACE == key)
        {
            ++mN;
        }
    }

    void draw(SurfT surf)
    {
        surf.fill(ColorBlack);
        surf.lock();
        scope(exit) surf.unlock();
        foreach(j;0..1)
        {
            Vertex[4] verts;

            verts[0].pos  = vec4_t(-1,-1,0,1);
            verts[0].tpos = vec2_t(0,0);
            verts[0].color = ColorRed;
            verts[1].pos  = vec4_t( 1,-1,0,1);
            verts[1].tpos = vec2_t(1,0);
            verts[1].color = ColorBlue;
            verts[2].pos  = vec4_t( 1, 1,0,1);
            verts[2].tpos = vec2_t(1,1);
            verts[2].color = ColorGreen;
            verts[3].pos  = vec4_t(-1, 1,0,1);
            verts[3].tpos = vec2_t(0,1);
            verts[3].color = ColorWhite;

            mat4_t t = mProjMat * mat4_t.translation(0,mYpos,-3) * mat4_t.yrotation(mRot);

            foreach(i;0..verts.length)
            {
                verts[i].pos = t * verts[i].pos;
                const w = verts[i].pos.w;
                verts[i].pos = verts[i].pos / w;
                verts[i].pos.w = w;
                verts[i].pos.x = verts[i].pos.x * mSize.w + mSize.w / 2;
                verts[i].pos.y = verts[i].pos.y * mSize.h + mSize.h / 2;
            }
            static int n = 0;
            if(0 != (mN % 2))
            {
                Rasterizer!(SurfT,typeof(mTexture)) rast = surf;
                rast.texture = mTexture;
                foreach(i;0..1)
                {
                    rast.drawIndexedTriangle(verts, [0,1,2]);
                    rast.drawIndexedTriangle(verts, [0,2,3]);
                }
            }
            else
            {
                RasterizerHP3!(SurfT,typeof(mTexture)) rast = surf;
                rast.texture = mTexture;
                foreach(i;0..1)
                {
                    rast.drawIndexedTriangle(verts, [0,1,2]);
                    rast.drawIndexedTriangle(verts, [0,2,3]);
                }
            }
        }
    }
}

