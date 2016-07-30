module game.renderer.rasterizertiled4.tiles;

import std.algorithm;
import std.range;

import gamelib.types;

import game.units;

import game.renderer.rasterizertiled4.types;

@nogc pure nothrow:
void updateTiles(ContextT,TileT,AreaT)
    (auto ref ContextT context, in Rect clipRect, TileT[] tiles, in Size tilesSize, in auto ref AreaT area, int index)
{
    assert(index >= 0);

    const size = context.size;

    void checkTile(Size TSize, bool Full, bool Covered, TileT)(int tx, int ty, auto ref TileT tile)
    {
        static assert(TSize.w > 0 && TSize.h > 0);

        assert(tx >= 0);
        assert(tx < tilesSize.w);
        assert(ty >= 0);
        assert(ty < tilesSize.h);

        const int x0 = tx * TSize.w;
        const int y0 = ty * TSize.h;

        static if(Full)
        {
            const int x1 = x0 + TSize.w;
            const int y1 = y0 + TSize.h;
        }
        else
        {
            const int x1 = min(x0 + TSize.w, clipRect.x + clipRect.w);
            const int y1 = min(y0 + TSize.h, clipRect.y + clipRect.h);
        }

        assert(x1 > x0);
        assert(y1 > y0);
        assert(area.x1 > x0);
        assert(area.x0 < x1);
        assert(area.y1 > y0);
        assert(area.y0 < y1);

        const areaLocal = area;

        void checkTileLine(LineT)(auto ref LineT line)
        {
        }

        void checkTile(bool CheckLeft, bool CheckRight)()
        {
            static if(Covered)
            {
                alias sy0 = y0;
                alias sy1 = y1;
            }
            else
            {
                const sy0 = max(areaLocal.y0, y0);
                const sy1 = min(areaLocal.y1, y1);
            }
            assert(sy1 > sy0);
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
                    checkTileLine(tile.spanBuff.lines[myr]);
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


        }

        static if(Covered && Full)
        {
            checkTile!(false,false);
        }
        else
        {
            const areay0 = max(y0,areaLocal.y0);
            const areay1 = min(y1,areaLocal.y1);
            assert(areay1 > areay0);
            const int[2] currLim0 = [areaLocal.iter0(areay0).x,areaLocal.iter1(areay0).x];
            const int[2] currLim1 = [areaLocal.iter0(areay1).x,areaLocal.iter1(areay1).x];

            if(x1 <= min(currLim0[0], currLim1[0]) ||
               x0 >= max(currLim0[1], currLim1[1]))
            {
                assert(false);
            }
            const checkLeft  = (max(currLim0[0], currLim1[0]) > x0);
            const checkRight = (min(currLim0[1], currLim1[1]) < x1);
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

    void updateLine(int y) pure nothrow @nogc
    {
        assert(y >= 0);
        assert(y < tilesSize.h);
        assert((y * TileSize.h) < area.y1);
        assert((y * TileSize.h) > (area.y0 - TileSize.h));

        const ty0 = y * TileSize.h;
        const ty1 = ty0 + TileSize.h;
        assert(ty1 > ty0);

        const sy0 = max(area.y0, ty0, clipRect.y);
        const sy1 = min(area.y1, ty1, clipRect.y + clipRect.h);
        assert(sy1 > sy0);

        assert(sy0 >= ty0);
        assert(sy1 <= ty1);

        if(sy0 >= (clipRect.y + clipRect.h))
        {
            return;
        }

        const bool yEdge = (ty1 > (clipRect.y + clipRect.h));
        const bool yFull = (TileSize.h == (sy1 - sy0));

        const areax0 = min(area.iter0(sy0).x, area.iter0(sy1).x);
        const areax1 = max(area.iter1(sy0).x, area.iter1(sy1).x);
        //assert(areax0 >= area.x0);
        //assert(areax1 <= area.x1);
        if(areax0 >= (clipRect.x + clipRect.w))
        {
            return;
        }

        const tx0 =  (max(areax0, clipRect.x) / TileSize.w);
        const tx1 = ((min(areax1, clipRect.x + clipRect.w) + TileSize.w - 1) / TileSize.w);
        if(tx0 >= tx1)
        {
            return;
        }
        assert((tx0 * TileSize.w + TileSize.w) > area.x0);
        assert((tx1 * TileSize.w - TileSize.w) < area.x1);

        auto tilesLocal = tiles.ptr + y * tilesSize.w;

        void UpdateTile(bool Covered)(int x)
        {
            assert(x >= 0);
            assert(x < tilesSize.w);
            assert((x * TileSize.w) < area.x1);
            assert((x * TileSize.w) > (area.x0 - TileSize.w));

            auto tile = &tilesLocal[x];
            assert(tile is &tiles[x + y * tilesSize.w]);

            if(tile.full)
            {
                return;
            }

            if(yEdge ||
                ((x * TileSize.w + TileSize.w) > (clipRect.x + clipRect.w)) ||
                ((x * TileSize.w) < clipRect.x))
            {
                static if(Covered)
                {
                    checkTile!(TileSize,false,true)(x, y, tile);
                }
                else
                {
                    checkTile!(TileSize,false,false)(x, y, tile);
                }
            }
            else
            {
                static if(Covered)
                {
                    checkTile!(TileSize,true,true)(x, y, tile);
                }
                else
                {
                    checkTile!(TileSize,true,false)(x, y, tile);
                }
            }
        }

        if(yFull)
        {
            const areamx0 = max(area.iter0(sy0).x, area.iter0(sy1).x);
            const areamx1 = min(area.iter1(sy0).x, area.iter1(sy1).x);

            const tmx0 = max((areamx0 + TileSize.w - 1) / TileSize.w, tx0);
            const tmx1 = min((areamx1 - TileSize.w + 1) / TileSize.w, tx1);
            assert(tmx0 >= tx0);
            assert(tmx1 <= tx1);

            if(tmx1 > tmx0)
            {
                foreach(x; tx0..tmx0)
                {
                    UpdateTile!false(x);
                }
                foreach(x; tmx0..tmx1)
                {
                    UpdateTile!true(x);
                }
                foreach(x; tmx1..tx1)
                {
                    UpdateTile!false(x);
                }
            }
            else
            {
                foreach(x; tx0..tx1)
                {
                    UpdateTile!false(x);
                }
            }
        }
        else
        {
            foreach(x; tx0..tx1)
            {
                UpdateTile!false(x);
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

void drawTiles(ContextT,AllocT,TileT,CacheT,PrepT)
    (auto ref ContextT context, in Rect clipRect, auto ref AllocT alloc, in Rect tilesDim, in TileT[] tiles, in CacheT[] cache, in PrepT[] prepared)
{
    assert(tiles.length > 0);
}
