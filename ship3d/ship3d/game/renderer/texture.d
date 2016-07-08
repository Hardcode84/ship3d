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
    version(LDC)
    {
        import ldc.attributes;
    @llvmAttr("unsafe-fp-math", "true"):
    }

    alias ColT  = Base.ColorType;
    this(int w, int h)
    {
        super(w, h);
        mData.length = w * h;
    }

    void getLine(int W, C, Range)(in ref C context, Range outLine) const pure nothrow
    {
        static assert(W >= 0);
        static if(W > 0)
        {
            assert(outLine.length == W);
            enum len = W;
        }
        else
        {
            const len = outLine.length;
        }
        assert(len > 0);
        const w = width;
        const h = height;
        assert(ispow2(w));
        assert(ispow2(h));
        const wmask = w - 1;
        const hmask = (h * w - 1) & ~wmask;
        alias TextT = Unqual!(typeof(context.u));
        //alias TextT = FixedPoint!(16,16,int);

        const startx = context.x;
        debug
        {
            const data = mData[];
        }
        else
        {
            const data = mData.ptr;
        }
        auto outPtr = outLine.ptr;

        enum Dither = false;
        static if(Dither)
        {
        immutable TextT[2][4] dithTable = [
            [0.25f,0.00f], [0.50f,0.75f],
            [0.75f,0.50f], [0.00f,0.25f]];
        }

        const TextT dux = cast(TextT)context.dux;
        const TextT dvx = cast(TextT)context.dvx;
        const TextT dux2 = cast(TextT)(dux * (w * 2));
        const TextT dvx2 = cast(TextT)(dvx * (h * w * 2));
        TextT u1 = cast(TextT)(context.u * w);
        TextT v1 = cast(TextT)(context.v * (h * w));
        TextT u2 = cast(TextT)((context.u + dux) * w);
        TextT v2 = cast(TextT)((context.v + dvx) * (h * w));

        static if(Dither)
        {
            const xoff = (startx & 1);
            const yoff = (context.y & 1) << 1;
            const dith1 = dithTable[xoff + yoff];
            const dith2 = dithTable[xoff ^ 1 + yoff];
            u1 += dith1[0];
            v1 += dith1[1] * h;
            u2 += dith2[0];
            v2 += dith2[1] * h;
        }

        foreach(i;0..(len >> 1))
        {
            const x1 = cast(int)(u1) & wmask;
            const y1 = cast(int)(v1) & hmask;
            const x2 = cast(int)(u2) & wmask;
            const y2 = cast(int)(v2) & hmask;
            outPtr[0] = getColor(context.colorProxy(data[x1 + y1],startx + i * 2 + 0));
            outPtr[1] = getColor(context.colorProxy(data[x2 + y2],startx + i * 2 + 1));
            u1 += dux2;
            v1 += dvx2;
            u2 += dux2;
            v2 += dvx2;
            outPtr += 2;
        }
        if(0 != (len & 1))
        {
            const x1 = cast(int)(u1) & wmask;
            const y1 = cast(int)(v1) & hmask;
            *outPtr = getColor(context.colorProxy(data[x1 + y1],startx + len - 1));
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
    override void setData(in DataT[] data) pure nothrow
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
    }

    void getLine(int W, C, Range)(in ref C context, Range outLine) const pure nothrow
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
        //foreach(i;TupleRange!(0,W))
        foreach(i;0..W)
        {
            const x = cast(int)(u * w) & wmask;
            const y = cast(int)(v * h) & hmask;
            const tx = x / TileSize;
            const ty = y / TileSize;
            const offset = TileDataSize * tx + tilePitch * ty;
            const tile = mData[offset..offset + TileDataSize];
            const x1 = x - tx * TileSize;
            const y1 = y - ty * TileSize;
            outLine[i] = getColor(tile[x1 + y1 * TileSize]);
            u += dux;
            v += dvx;
        }
    }
}

void fillChess(T,C)(auto ref T surf, in C col1, in C col2, uint wcell = 15, uint hcell = 15)
{
    import gamelib.types;
    auto view = surf.lock();
    scope(exit) surf.unlock();
    foreach(y;0..surf.height)
    {
        foreach(x;0..surf.width)
        {
            if((x / wcell) % 2 == (y / hcell) % 2)
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

void fill(T,C)(auto ref T surf, in C col)
{
    import gamelib.types;
    auto view = surf.lock();
    scope(exit) surf.unlock();
    foreach(y;0..surf.height)
    {
        foreach(x;0..surf.width)
        {
            view[y][x] = col;
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