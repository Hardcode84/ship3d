module game.renderer.palette;

import gamelib.types;

@nogc:
final class Palette(ColT)
{
private:
    enum Count = 256;
    immutable ColT[Count] mEntries;
public:
    this(T)(in T[] ent) pure nothrow
    {
        mEntries[] = ent;
    }

    auto opIndex(int i) const pure nothrow
    in
    {
        assert(i >= 0);
        assert(i < Count);
    }
    body
    {
        return mEntries;
    }
}

