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

    IntrusiveList!(Room,"worldUpdateLightsLink") mUpdateLightsList;

    struct OutContext
    {
        Size size;
        SurfT surface;
        Rect clipRect;
        mat4_t matrix;
        SpanMask mask;
        SpanMask dstMask;
        TaskPool myTaskPool;
        ColorT backColor;

        void[] rasterizerCache;
        uint rasterizerCacheUsed = 0;
        void function(void[]) flushFunc = null;

        StackAlloc[] allocators;
        debug
        {
            ulong pixelsDrawn = 0;
        }
    }

    LightController mLightController = null;
    immutable uint mTaskPoolThreads = 0;
    bool mMultithreadedRendering = false;

    alias InputListenerT = void delegate(in ref InputEvent);
    InputListenerT[] mInputListeners;

    uint mUpdateCounter = 0;
    vec3_t mLastPos = vec3_t(0,0,0);
    vec3_t mLastDir = vec3_t(0,0,0);
    bool mWasDraw = false;
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
        mTaskPoolThreads = max(1, numThreads - 1);
        mAllocators.length = (mTaskPoolThreads + 1);
        foreach(ref alloc; mAllocators[])
        {
            alloc = new StackAlloc(0xFFFFFF);
        }
        mRefAlloc =  new RefAllocator(0xFF);
        mSize = sz;
        mProjMat = mat4_t.perspective(sz.w,sz.h,155,0.1,1000);
        mRooms = generateWorld(this, seed);
        mPlayer = createEntity!Player(mRooms[0], vec3_t(0,0,/*-50.8*/-50.77), quat_t.identity);
        generateCubes(seed);
        import core.memory;
        GC.disable();
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

        foreach(room; mUpdateLightsList)
        {
            room.updateLights();
        }
        mUpdateLightsList.clear();
        sortEntities();

        ++mUpdateCounter;
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
        debug
        {
            const ColorT[1] colors = [
                ColorGreen/*,
                ColorBlue,
                ColorRed*/
            ];
            import std.random;
            surf.fill(colors[uniform(0,colors.length)]);
        }
        surf.lock();
        scope(exit) surf.unlock();

        auto allocator = mAllocators[0];
        auto allocState = allocator.state;
        scope(exit) allocator.restoreState(allocState);
        const clipRect = Rect(0, 0, surf.width, surf.height);
        const mat = mProjMat;
        OutContext octx = {mSize, surf, clipRect, mat, SpanMask(mSize, allocator)};
        octx.backColor = ColorBlue;
        octx.allocators = mAllocators;
        if(mMultithreadedRendering)
        {
            octx.myTaskPool = worldTaskPool();
        }
        octx.rasterizerCache = allocator.alloc!void(1024 * 500);
        RendererT renderer;
        renderer.state = octx;
        drawPlayer(renderer, allocator, surf);
        mWasDraw = true;
        debugOut("present");
    }

private:
    void drawPlayer(ref RendererT renderer, StackAlloc allocator, SurfT surf)
    {
        auto playerCon  = mPlayer.mainConnection;
        auto playerRoom = playerCon.room;
        const playerPos  = playerCon.pos + playerCon.correction;
        const playerDir  = playerCon.dir;
        enum MaxDepth = 16;
        playerRoom.draw(renderer, allocator, playerPos, playerDir, mPlayer, MaxDepth);
    }

    void generateCubes(uint seed)
    {
        const ColorT[] colors2 = [
            ColorSilver,
            ColorGray,
            ColorYellow,
            ColorCyan,
            ColorRed,
            ColorBlue,
            ColorGreen,
            ColorMagenta,
            ColorWhite];

        import game.renderer.texture;
        texture_t[] textures;
        textures.length = 10;

        foreach(i,ref tex; textures)
        {
            tex = new texture_t(16,16);
            //tex.fillChess(cast(ubyte)((1 << PaletteBits) - 1), cast(ubyte)(i), 1, 1);
            //tex.fillChess(ColorBlack, colors2[i], 1, 1);
            import game.texture;
            const size = 16 * 16 * 3;
            const offset = size * i;
            const data = cast(immutable(ubyte[3])[])image.pixel_data[offset..offset + size];
            const multCol = colors2[i % colors2.length];
            auto view = tex.lock();
            scope(exit) tex.unlock();
            foreach(y;0..tex.height)
            {
                foreach(x;0..tex.width)
                {
                    ColorT col;
                    const dat = data[x + y * tex.width];
                    col.r = dat[0];
                    col.g = dat[1];
                    col.b = dat[2];
                    view[y][x] = col * multCol;
                }
            }
        }
        import std.algorithm;
        import std.array;
        enum Scale = 10.0f;
        enum CubeScale = 2.5f;
        enum Dim = 10;

        enum texCorrect = 0.015f;
        import game.topology.mesh;
        Mesh mesh;
        mesh.addTriangles([
                Vertex(vec3_t(-1,-1, 1),vec2_t(0 + texCorrect, 0 + texCorrect)),
                Vertex(vec3_t( 1,-1, 1),vec2_t(1 - texCorrect, 0 + texCorrect)),
                Vertex(vec3_t(-1, 1, 1),vec2_t(0 + texCorrect, 1 - texCorrect)),
                Vertex(vec3_t( 1, 1, 1),vec2_t(1 - texCorrect, 1 - texCorrect))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
            [[0,1,2],[2,1,3]]);

        mesh.addTriangles([ //front
                Vertex(vec3_t(-1,-1, -1),vec2_t(0 + texCorrect, 0 + texCorrect)),
                Vertex(vec3_t( 1,-1, -1),vec2_t(1 - texCorrect, 0 + texCorrect)),
                Vertex(vec3_t(-1, 1, -1),vec2_t(0 + texCorrect, 1 - texCorrect)),
                Vertex(vec3_t( 1, 1, -1),vec2_t(1 - texCorrect, 1 - texCorrect))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
            [[2,1,0],[3,1,2]]);

        mesh.addTriangles([
                Vertex(vec3_t(-1,-1,-1),vec2_t(0 + texCorrect, 0 + texCorrect)),
                Vertex(vec3_t( 1,-1,-1),vec2_t(1 - texCorrect, 0 + texCorrect)),
                Vertex(vec3_t(-1,-1, 1),vec2_t(0 + texCorrect, 1 - texCorrect)),
                Vertex(vec3_t( 1,-1, 1),vec2_t(1 - texCorrect, 1 - texCorrect))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
            [[0,1,2],[2,1,3]]);

        mesh.addTriangles([
                Vertex(vec3_t(-1, 1,-1),vec2_t(0 + texCorrect, 0 + texCorrect)),
                Vertex(vec3_t( 1, 1,-1),vec2_t(1 - texCorrect, 0 + texCorrect)),
                Vertex(vec3_t(-1, 1, 1),vec2_t(0 + texCorrect, 1 - texCorrect)),
                Vertex(vec3_t( 1, 1, 1),vec2_t(1 - texCorrect, 1 - texCorrect))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
            [[2,1,0],[3,1,2]]);

        mesh.addTriangles([
                Vertex(vec3_t( 1,-1,-1),vec2_t(0 + texCorrect, 0 + texCorrect)),
                Vertex(vec3_t( 1, 1,-1),vec2_t(1 - texCorrect, 0 + texCorrect)),
                Vertex(vec3_t( 1,-1, 1),vec2_t(0 + texCorrect, 1 - texCorrect)),
                Vertex(vec3_t( 1, 1, 1),vec2_t(1 - texCorrect, 1 - texCorrect))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
            [[0,1,2],[2,1,3]]);

        mesh.addTriangles([
                Vertex(vec3_t(-1,-1,-1),vec2_t(0 + texCorrect, 0 + texCorrect)),
                Vertex(vec3_t(-1, 1,-1),vec2_t(1 - texCorrect, 0 + texCorrect)),
                Vertex(vec3_t(-1,-1, 1),vec2_t(0 + texCorrect, 1 - texCorrect)),
                Vertex(vec3_t(-1, 1, 1),vec2_t(1 - texCorrect, 1 - texCorrect))].map!(a => Vertex(a.pos * CubeScale, a.tpos)).array,
            [[2,1,0],[3,1,2]]);

        foreach(z; 0..Dim)
        {
            foreach(y; 0..Dim)
            {
                foreach(x; 0..Dim)
                {
                    import std.random;
                    mesh.texture = textures[uniform(0,textures.length)];
                    auto ent = new StaticMesh(this, mesh);

                    enum offset = Dim / 2 - 0.5f;

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
        const playerCon  = mPlayer.mainConnection;
        const playerPos  = playerCon.pos + playerCon.correction;
        const playerDir  = playerCon.dir * vec3_t(0,0,1);
        //if(((playerDir - mLastDir).length_squared > 0.001f || (playerPos - mLastPos).length_squared > 0.001f) && (0 == mUpdateCounter % 4))
        //{
            mLastPos = playerPos;
            mLastDir = playerDir;
            const v = mRooms[0].staticEntities[0].pos;

            foreach(ent; mRooms[0].staticEntities[])
            {
                const vec = ent.pos;
                const d = dot((vec - playerPos).normalized, playerDir);
                auto val = cast(int)((
                        (vec.x - playerPos.x) * (vec.x - playerPos.x) + 
                        (vec.y - playerPos.y) * (vec.y - playerPos.y) +
                        (vec.z - playerPos.z) * (vec.z - playerPos.z)) * 10.0f);
                ent.ent.visible = true;
                ent.ent.drawn = false;
                if(d < -0.5f && val > 500)
                {
                    ent.ent.visible = false;
                }
            }

            auto distSquared(in vec3_t vec)
            {
                auto val = cast(int)((
                    (vec.x - playerPos.x) * (vec.x - playerPos.x) + 
                    (vec.y - playerPos.y) * (vec.y - playerPos.y) +
                    (vec.z - playerPos.z) * (vec.z - playerPos.z)) * 10.0f);
                return val;
            }

            bool myComp(in StaticEntityRef a, in StaticEntityRef b)
            {
                const res     = distSquared(a.pos) > distSquared(b.pos);
                const antires = distSquared(b.pos) > distSquared(a.pos);
                return antires;
            }

            mRooms[0].staticEntities.sort!(myComp,SwapStrategy.stable)();
            mWasDraw = false;
        /*}
        else if(mWasDraw)
        {
            int count = 0;
            foreach(ent; mRooms[0].staticEntities[])
            {
                //debugOut(ent.ent.drawn);
                if(ent.ent.visible && !ent.ent.drawn)
                {
                    ent.ent.visible = false;
                }

                if(ent.ent.visible)
                {
                    ++count;
                }
            }
            debugOut(count);
        }*/
    }

    auto worldTaskPool()
    {
        if(mTaskPool is null)
        {
            mTaskPool = new TaskPool(mTaskPoolThreads);
            mTaskPool.isDaemon = true;
        }
        return mTaskPool;
    }
}

