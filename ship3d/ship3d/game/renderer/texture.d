module game.renderer.texture;

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

    auto get(T)(in T u, in T v) const pure nothrow
    {
        const tx = cast(int)(u * width)  & (width  - 1);
        const ty = cast(int)(v * height) & (height - 1);
        return getColor(mData[tx + ty * width]);
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