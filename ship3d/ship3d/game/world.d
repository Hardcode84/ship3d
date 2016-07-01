module game.world;

import std.algorithm;
import std.parallelism;

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
import game.topology.refalloc;
import game.entities.player;
import game.entities.staticmesh;
import game.generators.worldgen;

import gamelib.memory.stackalloc;

final class World
{
private:
    bool mQuitReq = false;
    immutable mat4_t mProjMat;
    immutable Size mSize;

    Room[]   mRooms;
    IntrusiveList!(Entity,"worldLink") mEntities;
    Player   mPlayer;
    StaticMesh[] mCubes;

    TaskPool mTaskPool;
    StackAlloc[] mAllocators;
    RefAllocator mRefAlloc;

    enum ThreadTileSize = Size(320,240);
    Rect[] mThreadTiles;

    IntrusiveList!(Room,"worldUpdateLightsLink") mUpdateLightsList;

    struct OutContext
    {
        Size size;
        SurfT surface;
        Rect clipRect;
        mat4_t matrix;
        SpanMask mask;
        SpanMask dstMask;
    }

    LightController mLightController = null;
    bool mMultithreadedRendering = false;

    alias InputListenerT = void delegate(in ref InputEvent);
    InputListenerT[] mInputListeners;
public:
    alias RendererT = Renderer!(OutContext,17);
//pure nothrow:
    @property auto refAllocator()    inout { return mRefAlloc; }
    @property auto lightController() inout { return mLightController; }
    @property auto lightPalette(light_palette_t pal) { mLightController = new LightController(pal); }
    @property auto ref updateLightslist() inout { return mUpdateLightsList; }

    alias SurfT  = FFSurface!ColorT;
    this(in Size sz, uint seed, uint numThreads)
    {
        assert(numThreads > 0);
        mTaskPool = new TaskPool(max(1, numThreads - 1));
        mTaskPool.isDaemon = true;
        mAllocators.length = mTaskPool.size + 1;
        foreach(ref alloc; mAllocators[])
        {
            alloc = new StackAlloc(0xFFFFFF);
        }
        createThreadTiles(sz);
        mRefAlloc =  new RefAllocator(0xFF);
        mSize = sz;
        mProjMat = mat4_t.perspective(sz.w,sz.h,155,0.1,1000);
        mRooms = generateWorld(this, seed);
        mPlayer = createEntity!Player(mRooms[0], vec3_t(0,0,-50.8), quat_t.identity);
        generateCubes(seed);
    }

    auto createEntity(E)(Room room, in vec3_t pos, in quat_t dir)
    {
        E ent = new E(this);
        addEntity(ent, room, pos, dir);
        return ent;
    }

    void addEntity(Entity e, Room room, in vec3_t pos, in quat_t dir)
    {
        assert(e !is null);
        assert(room !is null);
        room.addEntity(e, pos, dir);
        mEntities.insertBack(e);
        e.onAddedToWorld(room, pos, dir);
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
        return true;
    }

    void onInputEvent(in InputEvent evt)
    {
        if(auto e = evt.peek!KeyEvent())
        {
            if(e.action == KeyActions.SWITCH_RENDERER && e.pressed)
            {
                mMultithreadedRendering = !mMultithreadedRendering;
                import std.stdio;
                writefln("Multithreaded rendering: %s", mMultithreadedRendering);
            }
        }

        foreach(l; mInputListeners[])
        {
            l(evt);
        }
    }

    void draw(SurfT surf)
    {
        foreach(room; mUpdateLightsList)
        {
            room.updateLights();
        }
        mUpdateLightsList.clear();

        sortEntities();

        /*debug*/ surf.fill(ColorBlue);
        surf.lock();
        scope(exit) surf.unlock();

        if(mMultithreadedRendering)
        {
            foreach(Rect tile; mTaskPool.parallel(mThreadTiles[], 1))
            {
                const workerIndex = mTaskPool.workerIndex;
                assert(workerIndex >= 0);
                assert(workerIndex < mAllocators.length);
                auto allocator = mAllocators[workerIndex];
                auto allocState = allocator.state;
                scope(exit) allocator.restoreState(allocState);
                const clipRect = tile;
                const mat = mProjMat;
                OutContext octx = {mSize, surf, clipRect, mat, SpanMask(mSize, allocator)};
                RendererT renderer;
                renderer.state = octx;
                drawPlayer(renderer, allocator, surf);
            }
        }
        else
        {
            auto allocator = mAllocators[0];
            auto allocState = allocator.state;
            scope(exit) allocator.restoreState(allocState);
            const clipRect = Rect(0, 0, surf.width, surf.height);
            const mat = mProjMat;
            OutContext octx = {mSize, surf, clipRect, mat, SpanMask(mSize, allocator)};
            RendererT renderer;
            renderer.state = octx;
            drawPlayer(renderer, allocator, surf);
        }
        //debugOut("present");
    }

private:
    void drawPlayer(ref RendererT renderer, StackAlloc allocator, SurfT surf)
    {
        auto playerCon  = mPlayer.mainConnection;
        auto playerRoom = playerCon.room;
        auto playerPos  = playerCon.pos + playerCon.correction;
        auto playerDir  = playerCon.dir;
        enum MaxDepth = 16;
        playerRoom.draw(renderer, allocator, playerPos, playerDir, mPlayer, MaxDepth);
    }

    void createThreadTiles(in Size screenSize)
    {
        const w = (screenSize.w + ThreadTileSize.w - 1) / ThreadTileSize.w;
        const h = (screenSize.h + ThreadTileSize.h - 1) / ThreadTileSize.h;
        mThreadTiles.length = w * h;
        foreach(y; 0..h)
        {
            foreach(x; 0..w)
            {
                const startx = x * ThreadTileSize.w;
                const starty = y * ThreadTileSize.h;
                const endx = min(startx + ThreadTileSize.w, screenSize.w);
                const endy = min(starty + ThreadTileSize.h, screenSize.h);
                assert(endx > startx);
                assert(endy > starty);
                mThreadTiles[x + y * w] = Rect(startx, starty, endx - startx, endy - starty);
            }
        }
    }

    void generateCubes(uint seed)
    {
        enum GradNum = 1 << LightBrightnessBits;
        const ColorT[] colors1 = [
            ColorWhite,
            ColorRed,
            ColorGreen,
            ColorBlue,
            ColorYellow,
            ColorCyan,
            ColorMagenta];
        ColorT[256] data1= ColorBlack;
        foreach(i,c; colors1[])
        {
            const startInd = i * GradNum;
            const endInd = startInd + GradNum;
            auto line = data1[startInd..endInd];
            ColorT.interpolateLine!GradNum(line, ColorWhite, c);
        }
        auto lpalette = new light_palette_t(data1[0..(1 << LightPaletteBits)]);

        const ColorT[] colors2 = [
            ColorYellow,
            ColorCyan,
            ColorRed,
            ColorBlue,
            ColorGreen,
            ColorMagenta,
            ColorWhite];
        ColorT[256] data2 = ColorBlack;
        foreach(i,c; colors2[])
        {
            data2[i] = c;
        }
        import game.renderer.texture;
        texture_t[] textures;
        textures.length = colors2.length;

        foreach(i,ref tex; textures)
        {
            tex = new texture_t(16,16);
            tex.palette = new palette_t(data2[0..(1 << PaletteBits)], lpalette[]);
            tex.fillChess(cast(ubyte)((1 << PaletteBits) - 1), cast(ubyte)(i), 1, 1);
        }
        import std.algorithm;
        import std.array;
        enum Scale = 10.0f;
        enum CubeScale = 2.5f;
        foreach(z; 0..10)
        {
            foreach(y; 0..10)
            {
                foreach(x; 0..10)
                {
                    import game.topology.mesh;
                    Mesh mesh;
                    import std.random;
                    mesh.texture = textures[uniform(0,textures.length)];
                    mesh.addTriangles([
                            Vertex(vec3_t(-1,-1, 1),vec2_t(0,0)),
                            Vertex(vec3_t( 1,-1, 1),vec2_t(1,0)),
                            Vertex(vec3_t(-1, 1, 1),vec2_t(0,1)),
                            Vertex(vec3_t( 1, 1, 1),vec2_t(1,1))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
                        [[0,1,2],[2,1,3]]);

                    mesh.addTriangles([
                            Vertex(vec3_t(-1,-1, -1),vec2_t(0,0)),
                            Vertex(vec3_t( 1,-1, -1),vec2_t(1,0)),
                            Vertex(vec3_t(-1, 1, -1),vec2_t(0,1)),
                            Vertex(vec3_t( 1, 1, -1),vec2_t(1,1))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
                        [[2,1,0],[3,1,2]]);

                    mesh.addTriangles([
                            Vertex(vec3_t(-1,-1,-1),vec2_t(0,0)),
                            Vertex(vec3_t( 1,-1,-1),vec2_t(1,0)),
                            Vertex(vec3_t(-1,-1, 1),vec2_t(0,1)),
                            Vertex(vec3_t( 1,-1, 1),vec2_t(1,1))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
                        [[0,1,2],[2,1,3]]);

                    mesh.addTriangles([
                            Vertex(vec3_t(-1, 1,-1),vec2_t(0,0)),
                            Vertex(vec3_t( 1, 1,-1),vec2_t(1,0)),
                            Vertex(vec3_t(-1, 1, 1),vec2_t(0,1)),
                            Vertex(vec3_t( 1, 1, 1),vec2_t(1,1))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
                        [[2,1,0],[3,1,2]]);

                    mesh.addTriangles([
                            Vertex(vec3_t( 1,-1,-1),vec2_t(0,0)),
                            Vertex(vec3_t( 1, 1,-1),vec2_t(1,0)),
                            Vertex(vec3_t( 1,-1, 1),vec2_t(0,1)),
                            Vertex(vec3_t( 1, 1, 1),vec2_t(1,1))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
                        [[0,1,2],[2,1,3]]);

                    mesh.addTriangles([
                            Vertex(vec3_t(-1,-1,-1),vec2_t(0,0)),
                            Vertex(vec3_t(-1, 1,-1),vec2_t(1,0)),
                            Vertex(vec3_t(-1,-1, 1),vec2_t(0,1)),
                            Vertex(vec3_t(-1, 1, 1),vec2_t(1,1))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
                        [[2,1,0],[3,1,2]]);

                    auto ent = new StaticMesh(this, mesh);

                    enum offset = 4.5f;
                    //addEntity(ent, mRooms[0], vec3_t((x - offset) * Scale, (y - offset) * Scale, (z - offset) * Scale), quat_t.identity);

                    //if(z == 9)
                    {
                        mRooms[0].addStaticEntity(ent, vec3_t((x - offset) * Scale, (y - offset) * Scale, (z - offset) * Scale), quat_t.identity);
                    }
                }
            }
        }
    }

    void sortEntities()
    {
        auto playerCon  = mPlayer.mainConnection;
        auto playerPos  = playerCon.pos + playerCon.correction;
        
        auto distSquared(in vec3_t vec)
        {
            return 
                (vec.x - playerPos.x) * (vec.x - playerPos.x) + 
                    (vec.y - playerPos.y) * (vec.y - playerPos.y) +
                    (vec.z - playerPos.z) * (vec.z - playerPos.z);
        }
        
        bool myComp(in StaticEntityRef a, in StaticEntityRef b)
        {
            return distSquared(a.pos) > distSquared(b.pos);
        }
        
        mRooms[0].staticEntities.sort!(myComp)();
    }
}

