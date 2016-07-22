module game.renderer.rasterizertiled3.rasterizer;

import std.traits;
import std.algorithm;
import std.array;
import std.string;
import std.functional;
import std.range;

import gamelib.types;
import gamelib.util;
import gamelib.graphics.graph;
import gamelib.memory.utils;
import gamelib.memory.arrayview;

import game.units;
import game.utils;

import game.renderer.trianglebuffer;
import game.renderer.rasterizertiled3.types;
import game.renderer.rasterizertiled3.trianglesplitter;
import game.renderer.rasterizertiled3.tiles;


struct RasterizerTiled3(bool HasTextures, bool WriteMask, bool ReadMask, bool HasLight)
{
/*@nogc pure nothrow:*/
    version(LDC)
    {
        import ldc.attributes;
    @llvmAttr("unsafe-fp-math", "true"):
    }

    static void drawIndexedTriangle(AllocT,CtxT1,CtxT2,VertT,IndT)
        (auto ref AllocT alloc, auto ref CtxT1 outputContext, auto ref CtxT2 extContext, in VertT[] verts, in IndT[] indices) if(isIntegral!IndT)
    {
        assert(indices.length == 3);
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        enqueueTriangle(outputContext, extContext, pverts);
    }

private:
    struct VertsPack
    {
        vec3_t[3] verts = void;
        vec2_t[3] tcoords = void;

        this(VT)(in VT[] v)
        {
            assert(3 == v.length);
            verts = [v[0].pos.xyw,v[1].pos.xyw,v[2].pos.xyw];
            tcoords = [v[0].tpos,v[1].tpos,v[2].tpos];
        }
    }

    struct BuffElem(ExtContextT)
    {
        VertsPack vertspack;
        ExtContextT context;
    }

    static void enqueueTriangle(CtxT1,CtxT2,VertT)
        (auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
    {
        if(!isTrianglevValid(pverts[]))
        {
            return;
        }

        pushTriangleToBuffer!(flushHandler)(outContext.rasterizerCache,&outContext,BuffElem!(Unqual!(typeof(extContext)))(VertsPack(pverts), extContext));
    }

    static bool isTrianglevValid(VT)(in VT[] verts)
    {
        assert(3 == verts.length);
        const w1 = verts[0].pos.w;
        const w2 = verts[1].pos.w;
        const w3 = verts[2].pos.w;
        const x1 = verts[0].pos.x;
        const x2 = verts[1].pos.x;
        const x3 = verts[2].pos.x;
        const y1 = verts[0].pos.y;
        const y2 = verts[1].pos.y;
        const y3 = verts[2].pos.y;
        const mat = Matrix!(Unqual!(typeof(x1)),3,3)(
            x1, y1, w1,
            x2, y2, w2,
            x3, y3, w3);
        const d = mat.det;
        enum tol = 0.001f;
        if(d < tol || (w1 > tol && w2 > tol && w3 > tol))
        {
            return false;
        }
        return true;
    }

    public static void flushHandler(ContextT,ElemT)(auto ref ContextT context, in ElemT[] elements)
    {
        auto alloc = context.allocators[0];
        auto allocState1 = alloc.state;
        scope(exit) alloc.restoreState(allocState1);

        const size = context.size;
        const clipRect = context.clipRect;
        auto CalcTileSize(in Size tileSize)
        {
            assert(tileSize.w > 0);
            assert(tileSize.h > 0);
            return Size((clipRect.w + tileSize.w - 1) / tileSize.w, (clipRect.h + tileSize.h - 1) / tileSize.h);
        }
        Size[HighTileLevelCount + 1] tilesSizes = void;
        HighTile[][HighTileLevelCount] highTiles;
        tilesSizes[0] = CalcTileSize(TileSize);
        highTiles[0] = alloc.alloc(tilesSizes[0].w * tilesSizes[0].h, HighTile());
        foreach(i; TupleRange!(1,HighTileLevelCount + 1))
        {
            tilesSizes[i] = Size(tilesSizes[i - 1].w * 2, tilesSizes[i - 1].h * 2);
            static if(i < HighTileLevelCount)
            {
                highTiles[i] = alloc.alloc(tilesSizes[i].w * tilesSizes[i].h, HighTile());
            }
        }

        auto tiles = alloc.alloc(tilesSizes[HighTileLevelCount].w * tilesSizes[HighTileLevelCount].h,Tile());

        enum MaskW = LowTileSize.w;
        enum MaskH = LowTileSize.h;
        alias MaskT = TileMask!(MaskW, MaskH);
        auto masks = alloc.alloc!MaskT(tilesSizes[HighTileLevelCount].w * tilesSizes[HighTileLevelCount].h);
        auto ares = alloc.alloc!TriangleArea(elements.length);

        auto pool = context.myTaskPool;

        if(pool is null)
        {
            auto preparedTris = alloc.alloc(elements.length, PreparedTriangle());
            foreach_reverse(index,const ref elem; elements)
            {
                auto areas = alloc.alloc!TriangleArea(MaxAreasPerTriangle);
                int currentArea = 0;
                void areaHandler(const ref TriangleArea area) nothrow @nogc const
                {
                    updateTiles(context, clipRect, highTiles, tiles, masks, tilesSizes, area, elem.vertspack.verts[], cast(int)((index << AreaIndexShift) + currentArea));
                    areas[currentArea] = area;
                    ++currentArea;
                }
                splitTriangle!(areaHandler)(elem.vertspack.verts[], clipRect, context.size);
                preparedTris[index].areas = areas[0..currentArea];
            }

            drawTiles(context, clipRect, alloc, Rect(0,0,tilesSizes[0].w,tilesSizes[0].h), highTiles, tiles, tilesSizes, elements[], preparedTris);
        }
        else
        {
            auto allocState2 = saveAllocsStates(context.allocators);
            scope(exit) allocState2.restore();

            auto preparedTris = alloc.alloc(elements.length, PreparedTriangle());
            //foreach(index,const ref elem; elements)
            foreach(index;pool.parallel(iota(0,elements.length), 8))
            {
                const workerIndex = pool.workerIndex;
                auto threadAlloc = allocState2.allocs[workerIndex];
                auto areas = threadAlloc.alloc!TriangleArea(MaxAreasPerTriangle);
                int currentArea = 0;
                void areaHandler(const ref TriangleArea area) nothrow @nogc const
                {
                    areas[currentArea] = area;
                    ++currentArea;
                }
                splitTriangle!(areaHandler)(elements[index].vertspack.verts[], clipRect, context.size);
                preparedTris[index].areas = areas[0..currentArea];
            }

            enum Xstep = max(256 / TileSize.w, 1);
            enum Ystep = max(256 / TileSize.h, 1);
            auto xyrange = cartesianProduct(iota(0, tilesSizes[0].h, Xstep), iota(0, tilesSizes[0].w, Ystep));

            foreach(pos; pool.parallel(xyrange, 1))
            {
                const workerIndex = pool.workerIndex;
                auto threadAlloc = allocState2.allocs[workerIndex];

                const y = pos[0];
                const x = pos[1];
                const x0 = max(x * TileSize.w, clipRect.x);
                const x1 = min(x0 + TileSize.w * Xstep, clipRect.x + clipRect.w);
                assert(x1 > x0);
                const y0 = max(y * TileSize.h, clipRect.y);
                const y1 = min(y0 + TileSize.h * Ystep, clipRect.y + clipRect.h);
                assert(y1 > y0);
                const rect = Rect(x0, y0, x1 - x0, y1 - y0);

                foreach_reverse(i,const ref elem; preparedTris)
                {
                    foreach(index,const ref area; elem.areas[])
                    {
                        updateTiles(context, rect, highTiles, tiles, masks, tilesSizes, area, elements[i].vertspack.verts[], cast(int)((i << AreaIndexShift) + index));
                    }
                }

                const tx1 = x;
                const tx2 = min(tx1 + Xstep, tilesSizes[0].w);
                assert(tx2 > tx1);
                const ty1 = y;
                const ty2 = min(ty1 + Ystep, tilesSizes[0].h);
                assert(ty2 > ty1);
                drawTiles(context, clipRect, threadAlloc, Rect(tx1,ty1,tx2,ty2), highTiles, tiles, tilesSizes, elements[], preparedTris);
            }
        }
    }

}
