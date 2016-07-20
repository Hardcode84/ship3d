﻿module game.renderer.rasterizertiled3.tiles;

import std.algorithm;
import std.range;

import game.units;

import game.renderer.rasterizertiled3.types;
import game.renderer.rasterizertiled3.draw;

@nogc pure nothrow:
void updateTiles(ContextT,HTileT,TileT,MaskT,AreaT,VertT)
    (auto ref ContextT context, in Rect clipRect, HTileT[][] htiles, TileT[] tiles, MaskT[] masks, in Size[] tilesSizes, auto ref AreaT area, in VertT[] verts, int index)
{
    assert(3 == verts.length);
    assert(index >= 0);

    const size = context.size;

    void updateLine(int y) pure nothrow @nogc
    {
        const firstTilesSize = tilesSizes[0];
        assert(y >= 0);
        assert(y < firstTilesSize.h);
        const ty0 = y * TileSize.h;
        const ty1 = ty0 + TileSize.h;
        assert(ty1 > ty0);

        const sy0 = max(area.y0, ty0, clipRect.y);
        const sy1 = min(area.y1, ty1, clipRect.y + clipRect.h);
        assert(sy1 > sy0);

        assert(sy0 >= ty0);
        assert(sy1 <= ty1);

        const bool yEdge = (ty1 > (clipRect.y + clipRect.h));
        const bool yFull = (TileSize.h == (sy1 - sy0));

        const areax0 = min(area.iter0(sy0).x, area.iter0(sy1).x);
        const areax1 = max(area.iter1(sy0).x, area.iter1(sy1).x);

        const areamx0 = max(area.iter0(sy0).x, area.iter0(sy1).x);
        const areamx1 = min(area.iter1(sy0).x, area.iter1(sy1).x);

        const tx1 =  (max(areax0, clipRect.x) / TileSize.w);
        const tx2 = ((min(areax1, clipRect.x + clipRect.w) + TileSize.w - 1) / TileSize.w);

        const tmx1 = (areamx0 / TileSize.w);
        const tmx2 = (areamx1 / TileSize.w);

        auto htiles0Local = htiles[0].ptr + y * firstTilesSize.w;
        foreach(x; tx1..tx2)
        {
            assert(x >= 0);
            assert(x < firstTilesSize.w);

            auto tile = &htiles0Local[x];
            assert(tile is &htiles[0][x + y * firstTilesSize.w]);
            if(tile.used || tile.childrenFull)
            {
                continue;
            }

            const covered = yFull && (x > tmx1) && (x < tmx2);
            if(covered && !tile.hasChildren)
            {
                tile.set(index);
            }
            else
            {
                HighTile.type_t checkTile(Size TSize, int Level, bool Full, bool Covered)(int tx, int ty)
                {
                    static assert(TSize.w > 0 && TSize.h > 0);
                    static assert(Level >= 0);

                    const areaLocal = area;

                    const tilesSize = tilesSizes[Level];
                    const initialTileOffset = tx + ty * tilesSize.w;
                    enum gamelib.types.Point[4] offsetPoints = [
                        gamelib.types.Point(0,0),
                        gamelib.types.Point(1,0),
                        gamelib.types.Point(0,1),
                        gamelib.types.Point(1,1)
                    ];

                    static if(Level < HighTileLevelCount)
                    {
                        auto htilesLocal = htiles[Level].ptr + initialTileOffset;
                        HighTile.type_t childrenFullMask = 0;
                        foreach(i;0..4)
                        {
                            const offsetPointLocal = offsetPoints[i];
                            const tileOffset = offsetPointLocal.x + offsetPointLocal.y * tilesSize.w;

                            const currPt = gamelib.types.Point(tx + (i & 1), ty + ((i >> 1) & 1));
                            debug
                            {
                                assert(currPt.x >= 0);
                                assert(currPt.x < tilesSize.w);
                                assert(currPt.y >= 0);
                                assert(currPt.y < tilesSize.h);
                                assert((initialTileOffset + tileOffset) == (currPt.x + currPt.y * tilesSize.w));
                            }

                            assert((initialTileOffset + tileOffset) < htiles[Level].length);
                            auto tile = &htilesLocal[tileOffset];
                            if(tile.used || tile.childrenFull)
                            {
                                if(!Covered)
                                {
                                    childrenFullMask |= (1 << i);
                                }
                                continue;
                            }

                            static if(Covered)
                            {
                                if(!tile.hasChildren)
                                {
                                    tile.set(index);
                                }
                                else
                                {
                                    tile.setChildren();
                                    const ubyte[4] dummy = void;
                                    checkTile!(Size(TSize.w >> 1, TSize.h >> 1), Level + 1,Full,true)(currPt.x * 2, currPt.y * 2, dummy);
                                }
                            }
                            else
                            {
                                const valLocal = vals[i];
                                if(all(valLocal))
                                {
                                    if(!tile.hasChildren)
                                    {
                                        childrenFullMask |= (1 << i);
                                        tile.set(index);
                                    }
                                    else
                                    {
                                        const ubyte[4] dummy = void;
                                        checkTile!(Size(TSize.w >> 1, TSize.h >> 1), Level + 1,Full,true)(currPt.x * 2, currPt.y * 2, dummy);
                                        tile.SetChildrenFullMask(0xf);
                                        childrenFullMask |= (1 << i);
                                    }
                                }
                                else if(!none(valLocal))
                                {
                                    tile.setChildren();
                                    const U temp = {oldval: valLocal };
                                    const childrenMask = checkTile!(Size(TSize.w >> 1, TSize.h >> 1), Level + 1,Full,false)(currPt.x * 2, currPt.y * 2, temp.vals);
                                    tile.SetChildrenFullMask(childrenMask);
                                    if(0xf == childrenMask)
                                    {
                                        childrenFullMask |= (1 << i);
                                    }
                                }
                            }
                        }
                        return childrenFullMask;
                    }
                    else static if(Level == HighTileLevelCount)
                    {
                        auto tilesLocal = tiles.ptr + initialTileOffset;
                        auto masksLocal = masks.ptr + initialTileOffset;
                        HighTile.type_t childrenFullMask = 0;
                        const areax0 = areaLocal.x0;
                        const areax1 = areaLocal.x1;
                        foreach(i;0..4)
                        {
                            const offsetPointLocal = offsetPoints[i];
                            const tileOffset = offsetPointLocal.x + offsetPointLocal.y * tilesSize.w;

                            assert((initialTileOffset + tileOffset) < tiles.length);
                            assert((initialTileOffset + tileOffset) < masks.length);
                            auto tile = &tilesLocal[tileOffset];
                            if(tile.full)
                            {
                                static if(!Covered)
                                {
                                    childrenFullMask |= (1 << i);
                                }
                                continue;
                            }

                            debug
                            {
                                const currPt = gamelib.types.Point(tx + (i & 1), ty + ((i >> 1) & 1));
                                assert(currPt.x >= 0);
                                assert(currPt.x < tilesSize.w);
                                assert(currPt.y >= 0);
                                assert(currPt.y < tilesSize.h);
                                assert((initialTileOffset + tileOffset) == (currPt.x + currPt.y * tilesSize.w));
                            }

                            static if(Covered)
                            {
                                tile.addTriangle(index, true, 0, TSize.h);
                            }
                            else
                            {

                                static if(Full)
                                {
                                    const int x0 = (tx + offsetPointLocal.x) * TSize.w;
                                    const int x1 = x0 + TSize.w;

                                    const int y0 = (ty + offsetPointLocal.y) * TSize.h;
                                    const int y1 = y0 + TSize.h;
                                }
                                else
                                {
                                    const int x0 = (tx + offsetPointLocal.x) * TSize.w;
                                    const int x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);

                                    const int y0 = (ty + offsetPointLocal.y) * TSize.h;
                                    const int y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);

                                    if(x0 >= x1)
                                    {
                                        continue;
                                    }

                                    if(y0 >= y1)
                                    {
                                        break;
                                    }
                                }

                                assert(x1 > x0);
                                assert(y1 > y0);

                                if(areax1 <= x0 || areax0 >= x1 || areaLocal.y0 >= y1)
                                {
                                    continue;
                                }

                                if(areaLocal.y1 <= y0)
                                {
                                    break;
                                }

                                const int[2] currLim0 = [areaLocal.iter0(max(y0,areaLocal.y0)).x,areaLocal.iter1(max(y0,areaLocal.y0)).x];
                                const int[2] currLim1 = [areaLocal.iter0(min(y1,areaLocal.y1)).x,areaLocal.iter1(min(y1,areaLocal.y1)).x];

                                if(x1 <= min(currLim0[0], currLim1[0]) ||
                                   x0 >= max(currLim0[1], currLim1[1]))
                                {
                                    continue;
                                }

                                void checkTile(bool CheckLeft, bool CheckRight)()
                                {
                                    if(y0 >= areaLocal.y0 &&
                                       y1 <= areaLocal.y1 &&
                                       x0 >= max(currLim0[0],currLim1[0]) &&
                                       x1 <= min(currLim0[1],currLim1[1]))
                                    {
                                        tile.addTriangle(index, true, 0, TSize.h);
                                        childrenFullMask |= (1 << i);
                                    }
                                    else
                                    {
                                        auto mask = &masksLocal[tileOffset];
                                        assert(mask.data.length == TSize.h);
                                        if(tile.empty)
                                        {
                                            const sy0 = max(areaLocal.y0, y0);
                                            const sy1 = min(areaLocal.y1, y1);
                                            assert(sy1 > sy0);
                                            enum FullMask = mask.FullMask;
                                            const dy0 = sy0 - y0;
                                            assert(dy0 >= 0);
                                            mask.data[0..dy0] = 0;
                                            mask.fmask_t fmask = 0;

                                            static if(CheckLeft)
                                            {
                                                auto iter0 = areaLocal.iter0(sy0);
                                            }

                                            static if(CheckRight)
                                            {
                                                auto iter1 = areaLocal.iter1(sy0);
                                            }
                                            auto maskData = mask.data.ptr;

                                            int minY = TSize.h;
                                            int maxY = 0;

                                            foreach(my; sy0..sy1)
                                            {
                                                static if(CheckLeft)
                                                {
                                                    const sx0 = max(iter0.x, x0);
                                                }
                                                else
                                                {
                                                    alias sx0 = x0;
                                                }

                                                static if(CheckRight)
                                                {
                                                    const sx1 = min(iter1.x, x1);
                                                }
                                                else
                                                {
                                                    alias sx1 = x1;
                                                }
                                                const myr = my - y0;
                                                mask.type_t maskVal = 0;
                                                if(sx1 > sx0 || (!CheckLeft && !CheckRight))
                                                {
                                                    minY = min(minY, myr);
                                                    maxY = max(maxY, myr + 1);
                                                    assert(sx1 > sx0);
                                                    const sh0 = (sx0 - x0);
                                                    const sh1 = (x0 + TSize.w - sx1);
                                                    const val = (FullMask >> sh0) & (FullMask << sh1);
                                                    assert(0 != val);
                                                    maskVal = val;
                                                    fmask |= ((cast(mask.fmask_t)(FullMask == val)) << myr);
                                                }
                                                maskData[myr] = maskVal;
                                                static if(CheckLeft)
                                                {
                                                    iter0.incY();
                                                }
                                                static if(CheckRight)
                                                {
                                                    iter1.incY();
                                                }
                                            }

                                            const bool full = (FullMask == fmask);
                                            if(maxY > minY)
                                            {
                                                tile.addTriangle(index, full, minY, maxY);
                                                if(full)
                                                {
                                                    childrenFullMask |= (1 << i);
                                                }
                                            }

                                            const dy1 = (y0 + mask.height) - sy1;
                                            assert(dy1 >= 0);
                                            mask.data[$ - dy1..$] = 0;
                                            mask.fmask = fmask;
                                            assert(full == mask.full);

                                        }
                                        else //tile.empty
                                        {
                                            enum FullMask = mask.FullMask;
                                            mask.fmask_t fmask = mask.fmask;
                                            assert(fmask != FullMask);
                                            import core.bitop;
                                            const sy0 = max(areaLocal.y0, y0 + bsf(~fmask));
                                            const sy1 = min(areaLocal.y1, y0 + bsr(~fmask) + 1, y1);
                                            if(sy0 >= sy1)
                                            {
                                                return;
                                            }

                                            assert(sy1 > sy0);
                                            assert(!mask.full);

                                            mask.type_t visible = 0;
                                            const dy0 = sy0 - y0;
                                            assert(dy0 >= 0);


                                            static if(CheckLeft)
                                            {
                                                auto iter0 = areaLocal.iter0(sy0);
                                            }

                                            static if(CheckRight)
                                            {
                                                auto iter1 = areaLocal.iter1(sy0);
                                            }
                                            auto maskData = mask.data.ptr;


                                            int minY = TSize.h;
                                            int maxY = 0;

                                            foreach(my; sy0..sy1)
                                            {
                                                static if(CheckLeft)
                                                {
                                                    const sx0 = max(iter0.x, x0);
                                                }
                                                else
                                                {
                                                    alias sx0 = x0;
                                                }

                                                static if(CheckRight)
                                                {
                                                    const sx1 = min(iter1.x, x1);
                                                }
                                                else
                                                {
                                                    alias sx1 = x1;
                                                }
                                                const myr = my - y0;
                                                if(sx1 > sx0 || (!CheckLeft && !CheckRight))
                                                {
                                                    assert(sx1 > sx0);
                                                    const sh0 = (sx0 - x0);
                                                    const sh1 = (x0 + TSize.w - sx1);
                                                    const val = (FullMask >> sh0) & (FullMask << sh1);
                                                    assert(0 != val);
                                                    const oldMaskVal = maskData[myr];
                                                    const newVis = (val & ~oldMaskVal);

                                                    if(0 != newVis)
                                                    {
                                                        minY = min(minY, myr);
                                                        maxY = max(maxY, myr + 1);

                                                        visible |= newVis;
                                                        const newMaskVal = oldMaskVal | newVis;
                                                        maskData[myr] = newMaskVal;
                                                        fmask |= ((cast(mask.fmask_t)(FullMask == newMaskVal)) << myr);
                                                    }

                                                }
                                                static if(CheckLeft)
                                                {
                                                    iter0.incY();
                                                }
                                                static if(CheckRight)
                                                {
                                                    iter1.incY();
                                                }
                                            }

                                            if(0 != visible)
                                            {
                                                const bool full = (FullMask == fmask);
                                                tile.addTriangle(index, full, minY, maxY);
                                                if(full)
                                                {
                                                    childrenFullMask |= (1 << i);
                                                }
                                            }
                                            const dy1 = (y0 + mask.height) - sy1;
                                            assert(dy1 >= 0);
                                            mask.fmask = fmask;
                                            assert((FullMask == fmask) == mask.full);
                                        }
                                    }
                                }
                                //check

                                const checkLeft  = (max(areaLocal.edge0.x0, areaLocal.edge0.x1) > x0);
                                const checkRight = (min(areaLocal.edge1.x0, areaLocal.edge1.x1) < x1);
                                if(checkLeft && checkRight)
                                {
                                    checkTile!(true,true);
                                }
                                else if(checkLeft)
                                {
                                    checkTile!(true,false);
                                }
                                else if(checkRight)
                                {
                                    checkTile!(false,true);
                                }
                                else
                                {
                                    checkTile!(false,false);
                                }
                            }
                        }
                        return childrenFullMask;
                    }
                    else static assert(false);
                }

                tile.setChildren();
                if(yEdge ||
                    ((x * TileSize.w + TileSize.w) > (clipRect.x + clipRect.w)) ||
                    ((x * TileSize.w) < clipRect.x))
                {
                    //tile.SetChildrenFullMask(checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1,false)(x * 2, y * 2, u.vals));
                    if(covered)
                    {
                        checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1,false,true)(x * 2, y * 2);
                        tile.SetChildrenFullMask(0xf);
                    }
                    else
                    {
                        tile.SetChildrenFullMask(checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1,false,false)(x * 2, y * 2));
                    }
                }
                else
                {
                    //tile.SetChildrenFullMask(checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1,true)(x * 2, y * 2, u.vals));
                    if(covered)
                    {
                        checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1,true,true)(x * 2, y * 2);
                        tile.SetChildrenFullMask(0xf);
                    }
                    else
                    {
                        tile.SetChildrenFullMask(checkTile!(Size(TileSize.w >> 1, TileSize.h >> 1), 1,true,false)(x * 2, y * 2));
                    }
                }
            }
        }
    }

    auto yrange = iota(
        (max(area.y0, clipRect.y) / TileSize.h),
        ((min(area.y1, clipRect.y + clipRect.h) + TileSize.h - 1) / TileSize.h));

    foreach(y; yrange)
    {
        updateLine(y);
    }
}

void drawTiles(ContextT,AllocT,HTileT,TileT,CacheT,PrepT)
    (auto ref ContextT context, auto ref AllocT alloc, in Rect tilesDim, HTileT[][] htiles, TileT[] tiles, in Size[] tilesSizes, CacheT[] cache, PrepT[] prepared)
{
    const clipRect = context.clipRect;
    void drawTile(Size TSize, int Level, bool Full, AllocT)(int tx, int ty, auto ref AllocT alloc)
    {
        static assert(TSize.w > 0 && TSize.h > 0);
        static assert(Level >= 0);
        enum FullDrawWidth = TSize.w;

        assert(tx >= 0);
        assert(tx < tilesSizes[Level].w);
        assert(ty >= 0);
        assert(ty < tilesSizes[Level].h);

        const x0 = tx * TSize.w;
        assert(x0 >= clipRect.x);
        if(!Full && x0 >= (clipRect.x + clipRect.w))
        {
            return;
        }
        const y0 = ty * TSize.h;
        assert(y0 >= clipRect.y);
        if(!Full && y0 >= (clipRect.y + clipRect.h))
        {
            return;
        }

        static if(Level < HighTileLevelCount)
        {
            auto tile = &htiles[Level][tx + ty * tilesSizes[Level].w];

            if(tile.hasChildren)
            {
                foreach(i;0..4)
                {
                    drawTile!(Size(TSize.w >> 1, TSize.h >> 1), Level + 1, Full)(tx * 2 + (i & 1), ty * 2 + ((i >> 1) & 1), alloc);
                }
            }
            else if(tile.used)
            {
                static if(Full)
                {
                    const x1 = x0 + TSize.w;
                    const y1 = y0 + TSize.h;
                }
                else
                {
                    const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                    const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                }
                assert(x1 > x0);
                assert(y1 > y0);
                assert(x0 >= clipRect.x);
                assert(y0 >= clipRect.y);
                assert(x1 <= clipRect.x + clipRect.w);
                assert(y1 <= clipRect.y + clipRect.h);
                const rect = Rect(x0, y0, x1 - x0, y1 - y0);

                const index = tile.index;
                const triIndex = index >> AreaIndexShift;
                if(rect.w == TSize.w)
                {
                    drawPreparedTriangle!(FullDrawWidth, false)(alloc, rect, context, cache[triIndex], prepared[triIndex], index, y0, y0 + TSize.h);
                }
                else
                {
                    drawPreparedTriangle!(0,false)(alloc, rect, context, cache[triIndex], prepared[triIndex], index, y0, y0 + TSize.h);
                }
            }
            else static if(FillBackground)
            {
                static if(Full)
                {
                    const x1 = x0 + TSize.w;
                    const y1 = y0 + TSize.h;
                }
                else
                {
                    const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                    const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                }
                assert(x1 > x0);
                assert(y1 > y0);
                assert(x0 >= clipRect.x);
                assert(y0 >= clipRect.y);
                assert(x1 <= clipRect.x + clipRect.w);
                assert(y1 <= clipRect.y + clipRect.h);
                const rect = Rect(x0, y0, x1 - x0, y1 - y0);

                fillBackground(rect, context);
            }
        }
        else static if(Level == HighTileLevelCount)
        {
            auto tile = &tiles[tx + ty * tilesSizes[Level].w];
            if(tile.empty)
            {
                static if(FillBackground)
                {
                    static if(Full)
                    {
                        const x1 = x0 + TSize.w;
                        const y1 = y0 + TSize.h;
                    }
                    else
                    {
                        const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                        const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
                    }
                    assert(x1 > x0);
                    assert(y1 > y0);
                    assert(x0 >= clipRect.x);
                    assert(y0 >= clipRect.y);
                    assert(x1 <= clipRect.x + clipRect.w);
                    assert(y1 <= clipRect.y + clipRect.h);
                    const rect = Rect(x0, y0, x1 - x0, y1 - y0);
                    fillBackground(rect, context);
                }
                return;
            }

            static if(Full)
            {
                const x1 = x0 + TSize.w;
                const y1 = y0 + TSize.h;
            }
            else
            {
                const x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
                const y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
            }
            assert(x1 > x0);
            assert(y1 > y0);
            assert(x0 >= clipRect.x);
            assert(y0 >= clipRect.y);
            assert(x1 <= clipRect.x + clipRect.w);
            assert(y1 <= clipRect.y + clipRect.h);
            const rect = Rect(x0, y0, x1 - x0, y1 - y0);

            auto buff = tile.buffer[0..tile.length];
            assert(buff.length > 0);

            if(tile.covered && (Full || (rect.w == FullDrawWidth)))
            {
                const index = buff.back.index;
                const triIndex = index >> AreaIndexShift;
                assert(triIndex >= 0);
                assert(triIndex < cache.length);
                drawPreparedTriangle!(FullDrawWidth,false)(alloc, rect, context, cache[triIndex], prepared[triIndex], index, y0 + buff.back.minY, y0 + buff.back.maxY);
                buff.popBack;
            }
            else static if(FillBackground)
            {
                const index = buff.back.index;
                const triIndex = index >> AreaIndexShift;
                assert(triIndex >= 0);
                assert(triIndex < cache.length);
                drawPreparedTriangle!(0,true)(alloc, rect, context, cache[triIndex], prepared[triIndex], index, y0 + buff.back.minY, y0 + buff.back.maxY);
                buff.popBack;
            }

            foreach(const elem; buff.retro)
            {
                const index = elem.index;
                const triIndex = index >> AreaIndexShift;
                assert(triIndex >= 0);
                assert(triIndex < cache.length);
                drawPreparedTriangle!(0,false)(alloc, rect, context, cache[triIndex], prepared[triIndex], index, y0 + elem.minY, y0 + elem.maxY);
            }
        }
        else static assert(false);
    }

    void drawTileDispatch(AllocT)(int x, int y, auto ref AllocT alloc)
    {
        if(((x * TileSize.w + TileSize.w) < (clipRect.x + clipRect.w)) &&
            ((y * TileSize.h + TileSize.h) < (clipRect.y + clipRect.h)))
        {
            drawTile!(TileSize,0,true)(x,y,alloc);
        }
        else
        {
            drawTile!(TileSize,0,false)(x,y,alloc);
        }
    }

    foreach(y;tilesDim.y..tilesDim.h)
    {
        foreach(x;tilesDim.x..tilesDim.w)
        {
            drawTileDispatch(x,y,alloc);
        }
    }
}
