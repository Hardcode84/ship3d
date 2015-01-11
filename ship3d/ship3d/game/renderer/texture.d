module game.renderer.texture;

import std.traits;
import std.algorithm;

import gamelib.types;
import gamelib.math;
import gamelib.util;
import gamelib.fixedpoint;
import gamelib.graphics.surfaceview;

public import game.renderer.basetexture;

final class Texture(Base) : Base
{
private:
    alias DataT = Base.ColorArrayType;
    DataT[]       mData;
protected:
    override void setData(in DataT[] data) pure nothrow
    {
        mData[] = data[];
    }
public:
    alias ColT  = Base.ColorType;
    this(int w, int h)
    {
        super(w, h);
        mData.length = w * h;
        //import gamelib.types;
        //mData[] = ColorBlue;
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
            *dstPtr = getColor(context.colorProxy(mData[x + y * width],i));
            u += dux;
            v += dvx;
            ++dstPtr;
        }
    }
}

final class TextureTiled(Base) : Base
{
private:
    enum TileSize = 4;
    alias DataT = Base.ColorArrayType;
    alias ArrT  = DataT[];
    ArrT          mData;
protected:
    override void setData(in ColT[] data) pure nothrow
    {
        //debugOut("setData");
        //scope(exit) debugOut("setData done");
        const mtx = width  / TileSize;
        const mty = height / TileSize;
        enum TileDataSize = TileSize * TileSize;
        const pitch = TileDataSize * (width / TileSize);
        foreach(ty;0..mty)
        {
            foreach(tx;0..mtx)
            {
                const offset = TileDataSize * tx + pitch * ty;
                auto tileData = mData[offset..offset + TileDataSize];
                foreach(y;0..TileSize)
                {
                    const srcy = (ty * TileSize + y);
                    foreach(x;0..TileSize)
                    {
                        const srcx = (tx * TileSize + x);
                        //debugOut(x);
                        //debugOut(y);
                        tileData[x + y * TileSize] = data[srcx + width * srcy];
                    }
                }
            }
        }
    }
public:
    alias ColT  = Base.ColorType;
    this(int w, int h) pure nothrow
    {
        assert(w >= TileSize);
        assert(h >= TileSize);
        super(w, h);
        mData.length = w * h;
        import gamelib.types;
        mData[] = ColorBlue;
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

        enum TileDataSize = TileSize * TileSize;
        const tilePitch = TileDataSize * (width / TileSize);
        auto dstPtr = outLine.ptr;
        foreach(i;TupleRange!(0,W))
        {
            const x = cast(int)(u * w) & wmask;
            const y = cast(int)(v * h) & hmask;
            const tx = x / TileSize;
            const ty = y / TileSize;
            const offset = TileDataSize * tx + tilePitch * ty;
            const tile = mData[offset..offset + TileDataSize];
            const x1 = x - tx * TileSize;
            const y1 = y - ty * TileSize;
            *dstPtr = getColor(tile[x1 + y1 * TileSize]);
            u += dux;
            v += dvx;
            ++dstPtr;
        }
    }
}

void fillChess(T,C)(auto ref T surf, in C col1, in C col2)
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
                view[y][x] = col1;
            }
            else
            {
                view[y][x] = col2;
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