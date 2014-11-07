module game.renderer.texture;

import std.traits;
import std.algorithm;

import gamelib.math;
import gamelib.util;
import gamelib.graphics.surfaceview;

final class Texture(Base) : Base
{
private:
    alias DataT = Base.ColorArrayType;
    DataT[]       mData;
protected:
    override void setData(in ColT[] data) pure nothrow
    {
        mData[] = data[];
    }
public:
    alias ColT  = Base.ColorType;
    this(int w, int h)
    {
        super(w, h);
        mData.length = w * h;
        import gamelib.types;
        mData[] = ColorBlue;
    }

    /*deprecated*/ auto get(T)(in T u, in T v) const pure nothrow
    {
        const tx = cast(int)(u * width)  & (width  - 1);
        const ty = cast(int)(v * height) & (height - 1);
        return getColor(mData[tx + ty * width]);
    }

    void getLine(int W, C, T)(in ref C context, T[] outLine) const pure nothrow
    {
        assert(outLine.length == W);
        static assert(W > 0);
        const w = width;
        const h = height;
        const wmask = w - 1;
        const hmask = h - 1;
        alias TextT = Unqual!(typeof(context.u));
        TextT u = context.u;
        TextT v = context.v;
        const TextT dux = context.dux;
        const TextT dvx = context.dvx;

        auto dstPtr = outLine.ptr;
        foreach(i;TupleRange!(0,W))
        {
            const x = cast(int)(u * w) & wmask;
            const y = cast(int)(v * h) & hmask;
            *dstPtr = getColor(mData[x + y * width]);
            u += dux;
            v += dvx;
            ++dstPtr;
        }
    }
}

final class TextureTiled(Base) : Base
{
private:
    enum TileSize = 16;
    alias DataT = Base.ColorArrayType;
    alias ArrT  = DataT[];
    ArrT          mData;
    ArrT[]        mLevels;
    immutable int mNumLevels;
    static auto calcLevelSize(int w, int h) pure nothrow
    {
        assert(w > 0);
        assert(h > 0);
        assert(ispow2(w));
        assert(ispow2(h));
        return max(w, TileSize) * max(h, TileSize) * 4;
    }
    auto getLevel(T)(in T du, in T dv) const pure nothrow
    {
        enum T MaxLine = TileSize / 2;
        const md = max(du, dv) * MaxLine;
        const levSize = MaxLine / md;
        return max(mNumLevels - log2(cast(int)levSize) - 1, 0);
    }
    auto getTile(T)(in T u, in T v, in T du, in T dv, int lev) const pure nothrow
    {
        const minU = min(u, u + du);
        const minV = min(v, v + dv);
        const w = max(width  >> lev, 1);
        const h = max(height >> lev, 1);
        const wmask = w - 1;
        const hmask = h - 1;
        const x = cast(int)(w * minU) & wmask;
        const y = cast(int)(h * minV) & hmask;
        const tx = x / (TileSize / 2);
        const ty = y / (TileSize / 2);
        enum TileDataSize = TileSize * TileSize;
        const pitch = TileDataSize * (w / (TileSize / 2));
        const offset = tx * TileDataSize + ty * pitch; 
        return mLevels[lev][offset..offset + TileDataSize];
    }
protected:
    override void setData(in ColT[] data) pure nothrow
    {
        void fillLevel(DataT[] level, in DataT[] source, int w, int h)
        {
            assert(w > 0);
            assert(h > 0);
            assert(ispow2(w));
            assert(ispow2(h));
            const wmask = w - 1;
            const hmask = h - 1;
            const mtx = max(w, TileSize) / (TileSize / 2);
            const mty = max(h, TileSize) / (TileSize / 2);
            enum TileDataSize = TileSize * TileSize;
            const pitch = TileDataSize * (w / (TileSize / 2));
            foreach(ty;0..mty)
            {
                foreach(tx;0..mtx)
                {
                    const offset = tx * TileDataSize + ty * pitch;
                    auto tileData = level[offset..offset + TileDataSize];
                    foreach(y;0..TileSize)
                    {
                        const srcy = (ty * TileSize + y) & hmask;
                        foreach(x;0..TileSize)
                        {
                            const srcx = (tx * TileSize + x) & wmask;
                            tileData[x + y * TileSize] = source[srcx + w * srcy];
                        }
                    }
                }
            }
        }

        void fillMip(DataT[] dest, in DataT[] source, int srcW, int srcH)
        {
            const dstW = max(srcW / 2, 1);
            const dstH = max(srcH / 2, 1);
            foreach(y;0..dstH)
            {
                foreach(x;0..dstW)
                {
                    const col00 = source[(x * 2 + 0) + (y * 2 + 0) * srcW];
                    const col01 = source[(x * 2 + 0) + (y * 2 + 1) * srcW];
                    const col10 = source[(x * 2 + 1) + (y * 2 + 0) * srcW];
                    const col11 = source[(x * 2 + 1) + (y * 2 + 1) * srcW];
                    dest[x + y * dstW] = avgColor(col00, col10, col01, col11);
                }
            }
        }
        DataT[] tempData1, tempData2;
        const tempSize = calcLevelSize(width / 2, height / 2);
        tempData1.length = tempSize;
        tempData2.length = tempSize;
        fillLevel(mLevels[0], data, width, height);
        fillMip(tempData1, data, width, height);
        foreach(i;1..mNumLevels)
        {
            fillLevel(mLevels[i], tempData1, width >> i, height >> i);
            fillMip(tempData2, tempData1, width >> i, height >> i);
            swap(tempData1, tempData2);
        }
    }
public:
    alias ColT  = Base.ColorType;
    this(int w, int h) pure nothrow
    {
        super(w, h);
        assert(w == h);
        mNumLevels = 1 + log2(max(w, h));
        mLevels.length = mNumLevels;
        size_t dataSize = 0;
        foreach(i;0..mNumLevels)
        {
            dataSize += calcLevelSize(max(w >> i, 1), max(h >> i, 1));
        }
        mData.length = dataSize;
        ptrdiff_t levelOffset = 0;
        foreach(i;0..mNumLevels)
        {
            const size = calcLevelSize(max(w >> i, 1), max(h >> i, 1));
            mLevels[i] = mData[levelOffset..levelOffset + size];
            levelOffset += size;
        }

        import gamelib.types;
        mData[] = ColorBlue;
    }

    void getLine(int W, C, T)(in ref C context, T[] outLine) const pure nothrow
    {
        enum HalfTile = TileSize / 2;
        assert(outLine.length == W);
        static assert(W > 0);
        static assert(W <= HalfTile);
        const level = getLevel(context.dux, context.dvx);
        const tile  = getTile(context.u, context.v, context.dux, context.dvx, level);
    }
}

void fillChess(T)(auto ref T surf)
{
    import gamelib.types;
    auto view = surf.lock();
    scope(exit) surf.unlock();
    foreach(y;0..surf.height)
    {
        foreach(x;0..surf.width)
        {
            if((x / 15) % 2 == (y / 15) % 2)
            {
                view[y][x] = ColorGreen;
            }
            else
            {
                view[y][x] = ColorRed;
            }
        }
    }
}

auto loadTextureFromFile(TexT)(in string filename)
{
    import gamelib.graphics.surface;
    alias ColT = TexT.ColT;
    auto surf = loadSurfaceFromFile!ColT(filename);
    scope(exit) surf.dispose();
    surf.lock();
    scope(exit) surf.unlock();
    auto ret = new TexT(surf.width,surf.height);
    auto srcView = surf[0];
    auto view = ret.lock();
    scope(exit) ret.unlock();
    foreach(y;0..surf.height)
    {
        foreach(x;0..surf.width)
        {
            view[y][x] = srcView[x];
        }
        ++srcView;
    }
    return ret;
}