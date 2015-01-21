module game.world;

import std.algorithm;

import gamelib.graphics.surface;
import gamelib.graphics.graph;
import gamelib.graphics.memsurface;

import gamelib.containers.intrusivelist;

import game.controls;

import game.units;
import game.renderer.renderer;
import game.renderer.texture;
import game.renderer.basetexture;
import game.renderer.spanmask;
import game.renderer.light;

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

    Room[]   mRooms;
    //Entity[] mEntities;
    IntrusiveList!(Entity,"worldLink") mEntities;
    Player   mPlayer;

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
    alias RendererT = Renderer!(OutContext,17);
    RendererT mRenderer;
    LightController mLightController = null;

    alias InputListenerT = void delegate(in ref InputEvent);
    InputListenerT[] mInputListeners;
public:
//pure nothrow:
    @property allocator()       inout { return mAllocator; }
    @property erefAllocator()   inout { return mERefAlloc; }
    @property lightController() inout { return mLightController; }
    @property lightPalette(light_palette_t pal) { mLightController = new LightController(pal); }

    alias SurfT  = FFSurface!ColorT;
    this(in Size sz, uint seed)
    {
        mAllocator = new StackAlloc(0xFFFFFF);
        mERefAlloc = new EntityRefAllocator(0xFF);
        mSize = sz;
        mProjMat = mat4_t.perspective(sz.w,sz.h,90,0.1,1000);
        mRooms = generateWorld(this, seed);
        mPlayer = new Player(this);
        addEntity(mPlayer, mRooms[0], vec3_t(0,0,0), quat_t.identity);
    }

    void addEntity(Entity e, Room room, in vec3_t pos, in quat_t dir)
    {
        assert(e !is null);
        assert(room !is null);
        room.addEntity(e, pos, dir);
        mEntities.insertBack(e);
    }

    void addInputListener(in InputListenerT listener)
    {
        assert(!canFind(mInputListeners[], listener));
        mInputListeners ~= listener;
    }

    void removeInputListener(in InputListenerT listener)
    {
        foreach(i, l; mInputListeners[])
        {
            if(l == listener)
            {
                mInputListeners[i] = mInputListeners[$ - 1];
                --mInputListeners.length;
                return;
            }
        }
        assert(false, "removeInputListener error");
    }

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
        auto range = mEntities[];
        while(!range.empty)
        {
            Entity ent = range.front;
            ent.update();
            range.popFront();
            if(!ent.isAlive)
            {
                ent.dispose();
                ent.worldLink.unlink();
            }
        }

        enum MaxUpdates = 20;
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
        }
        foreach(e; mEntities[])
        {
            e.updatePos();
        }
        foreach(r; mRooms[])
        {
            r.updateLights();
        }
        return true;
    }

    void onInputEvent(in InputEvent evt)
    {
        foreach(l; mInputListeners[])
        {
            l(evt);
        }
    }

    void draw(SurfT surf)
    {
        auto allocState = mAllocator.state;
        scope(exit) mAllocator.restoreState(allocState);

        debug surf.fill(ColorBlue);
        surf.lock();
        scope(exit) surf.unlock();

        const clipRect = Rect(0, 0, surf.width, surf.height);
        const mat = mProjMat;
        OutContext octx = {mSize, surf, clipRect, mat, SpanMask(mSize, mAllocator)};
        mRenderer.getState() = octx;
        //debugOut("world.draw");
        drawPlayer(surf);
    }

    private void drawPlayer(SurfT surf)
    {
        const playerCon  = mPlayer.mainConnection;
        const playerRoom = playerCon.room;
        const playerPos  = playerCon.pos + playerCon.correction;
        const playerDir  = playerCon.dir;
        enum MaxDepth = 16;
        playerRoom.draw(mRenderer, allocator(), playerPos, playerDir, mPlayer, MaxDepth);
    }
}

