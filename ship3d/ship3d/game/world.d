module game.world;

import gamelib.graphics.surface;
import gamelib.graphics.graph;
import gamelib.graphics.memsurface;

import game.units;
import game.renderer.renderer;
import game.renderer.rasterizer;
import game.renderer.rasterizer2;
import game.renderer.rasterizerhp;
import game.renderer.rasterizerhp2;
import game.renderer.rasterizerhp3;
import game.renderer.rasterizerhp4;
import game.renderer.rasterizerhp5;
import game.renderer.rasterizerhp6;
import game.renderer.rasterizerhybrid;
import game.renderer.texture;
import game.renderer.basetexture;
import game.renderer.spanmask;

import game.topology.room;
import game.topology.entityref;
import game.entities.player;
import game.generators.worldgen;

import game.memory.stackalloc;

final class World
{
private:
    bool mQuitReq = false;
    immutable mat4_t mProjMat;
    immutable Size mSize;
    pos_t mRot = 1;
    pos_t mYpos = 0;
    pos_t mDist = -3;
    int mN = 0;
    alias TextureT = Texture!(BaseTextureRGB!ColorT);
    TextureT mTexture;
    //alias TiledTextureT = TextureTiled!(BaseTextureRGB!ColorT);
    //TiledTextureT mTiledTexture;

    Room[] mRooms;
    Player mPlayer;

    int mCurrentId = 0;

    StackAlloc mAllocator;
    EntityRefAllocator mERefAlloc;

    struct OutContext
    {
        Size size;
        SurfT surface;
        Rect clipRect;
        mat4_t matrix;
        SpanMask mask;
        SpanMask dstMask;
    }
    alias RendererT = Renderer!(OutContext,16);
    RendererT mRenderer;
public:
//pure nothrow:
    @property allocator()     inout pure nothrow { return mAllocator; }
    @property erefAllocator() inout pure nothrow { return mERefAlloc; }

    alias SurfT  = FFSurface!ColorT;
    this(in Size sz)
    {
        mAllocator = new StackAlloc(0xFFFFFF);
        mERefAlloc = new EntityRefAllocator(0xFF);
        mSize = sz;
        mProjMat = mat4_t.perspective(sz.w,sz.h,90,0.1,1000);
        //mTexture = new TextureT(256,256);
        mTexture      = loadTextureFromFile!TextureT("12022011060.bmp");
        //mTiledTexture = loadTextureFromFile!TiledTextureT("12022011060.bmp");
        //fillChess(mTexture);
        mRooms = generateWorld(this, 1);
        mPlayer = new Player;
        mRooms[0].addEntity(mPlayer, vec3_t(0,0,0), quat_t.identity);
    }

    auto generateId() { return ++mCurrentId; }

    void handleQuit()
    {
        mQuitReq = true;
    }

    bool update()
    {
        if(mQuitReq)
        {
            return false;
        }
        /*enum MaxUpdates = 20;
        foreach(i; 0..MaxUpdates)
        {
            bool haveUpdates = false;
            foreach(r; mRooms[])
            {
                if(r.needUpdateEntities)
                {
                    haveUpdates = true;
                    r.updateEntities();
                }
            }
            if(!haveUpdates)
            {
                break;
            }
        }*/
        return true;
    }

    void processKey(int key)
    {
        const spd = 0.02;
        const asd = 0.02;
        if(SDL_SCANCODE_LEFT == key)
        {
            mRot += spd;
            mPlayer.rotate(quat_t.yrotation(0.03));
        }
        else if(SDL_SCANCODE_RIGHT == key)
        {
            mRot -= spd;
            mPlayer.rotate(quat_t.yrotation(-0.03));
        }
        else if(SDL_SCANCODE_UP == key)
        {
            mYpos -= asd;
            mPlayer.rotate(quat_t.xrotation(0.03));
        }
        else if(SDL_SCANCODE_DOWN == key)
        {
            mYpos += asd;
            mPlayer.rotate(quat_t.xrotation(-0.03));
        }
        else if(SDL_SCANCODE_SPACE == key)
        {
            ++mN;
        }
        else if(SDL_SCANCODE_KP_PLUS == key)
        {
            mDist += 0.1f;
            mPlayer.move(vec3_t(0,0,1.0));
        }
        else if(SDL_SCANCODE_KP_MINUS == key)
        {
            mDist -= 0.1f;
            mPlayer.move(vec3_t(0,0,-1.0));
        }
    }

    void draw(SurfT surf)
    {
        auto allocState = mAllocator.state;
        scope(exit) mAllocator.restoreState(allocState);

        surf.fill(ColorBlack);
        surf.lock();
        scope(exit) surf.unlock();

        const clipRect = Rect(0, 0, surf.width, surf.height);
        const mat = mProjMat;
        OutContext octx = {mSize, surf, clipRect, mat, SpanMask(mSize, mAllocator)};
        //renderer.viewport = mSize;
        mRenderer.getState() = octx;
        auto playerCon  = mPlayer.connections[0];
        auto playerRoom = playerCon.room;
        const playerPos = playerCon.pos;
        const playerDir = playerCon.dir;
        enum MaxDepth = 15;
        //debugOut("world.draw");
        playerRoom.draw(mRenderer, allocator(), playerPos, playerDir, MaxDepth);

        /*foreach(j;0..1)
        {
            Vertex[4] verts;

            verts[0].pos  = vec4_t(-1,-1,0,1);
            verts[0].tpos = vec2_t(0,0);
            //verts[0].color = ColorRed;
            verts[1].pos  = vec4_t( 1,-1,0,1);
            verts[1].tpos = vec2_t(1,0);
            //verts[1].color = ColorBlue;
            verts[2].pos  = vec4_t( 1, 1,0,1);
            verts[2].tpos = vec2_t(1,1);
            //verts[2].color = ColorGreen;
            verts[3].pos  = vec4_t(-1, 1,0,1);
            verts[3].tpos = vec2_t(0,1);
            //verts[3].color = ColorWhite;

            mat4_t t = mProjMat * mat4_t.translation(0,mYpos,mDist) * mat4_t.yrotation(mRot);
            enum HasColor = false;
            enum HasTexture = !HasColor;

            foreach(i;0..verts.length)
            {
                verts[i].pos = t * verts[i].pos;
                /+const w = verts[i].pos.w;
                verts[i].pos = verts[i].pos / w;
                verts[i].pos.w = w;
                verts[i].pos.x = verts[i].pos.x * mSize.w + mSize.w / 2;
                verts[i].pos.y = verts[i].pos.y * mSize.h+ mSize.h / 2;+/
            }
            static int n = 0;
            static immutable int[3] ind1 = [0,1,2];
            static immutable int[3] ind2 = [0,2,3];
            const clipRect = Rect(0, 0, surf.width, surf.height);
            RasterizerHybrid!(true,false,false) rast1;
            Rasterizer2 rast2;
            struct OutContext
            {
                SurfT surface;
                Rect clipRect;
                Size size;
            }
            OutContext octx = {surf, clipRect, mSize};
            if(0 != (mN % 2))
            {
                struct Context1
                {
                    TextureT texture;
                }
                Context1 ctx = {mTexture};
                foreach(i;0..1)
                {
                    rast2.drawIndexedTriangle!(HasTexture)(octx,ctx, verts, ind1);
                    rast2.drawIndexedTriangle!(HasTexture)(octx,ctx, verts, ind2);
                }
            }
            else
            {
                struct Context2
                {
                    TextureT texture;
                }
                Context2 ctx = {mTexture};
                foreach(i;0..1)
                {
                    rast1.drawIndexedTriangle(octx,ctx, verts, ind1);
                    rast1.drawIndexedTriangle(octx,ctx, verts, ind2);
                }
            }
        }*/


    }
}

