module game.renderer.palette;

import std.algorithm;
import std.range;

import gamelib.types;
import gamelib.graphics.color;

@nogc:
final class Palette(ColT,int Bits, bool BlendTable, string BlendOp = "*")
{
//pure nothrow:
private:
    static assert(Bits > 0);
    enum Count = (1 << Bits);
    immutable ColT[Count] mEntries;
    static if(BlendTable)
    {
        enum BlendCount = Count*Count;
        immutable ubyte[BlendCount] mBlendTable;
    }
public:
    this(T)(in T[] ent)
    in
    {
        assert(ent.length == Count);
    }
    body
    {
        mEntries[] = ent[];
        static if(BlendTable)
        {
            ubyte[BlendCount] tempTable;
            foreach(i,srcCol;mEntries[])
            {
                foreach(j,dstCol;mEntries[])
                {
                    mixin("const testCol = srcCol "~BlendOp~" dstCol;");
                    auto best = reduce!((a,b) =>
                        (testCol.distanceSquared(mEntries[a]) < testCol.distanceSquared(mEntries[b]) ? a : b))(0,iota(0,Count));
                    assert(best >= 0 && best <= ubyte.max, debugConv(best));
                    tempTable[i + Count * j] = cast(ubyte)best;
                }
            }
            mBlendTable[] = tempTable[];
        }
    }

    auto opIndex(int i) const
    in
    {
        assert(i >= 0);
        assert(i < Count);
    }
    body
    {
        return mEntries[i];
    }

    auto opSlice(int i1, int i2) const
    in
    {
        assert(i1 >= 0);
        assert(i1 < Count);
        assert(i2 >= 0);
        assert(i2 < Count);
    }
    body
    {
        return mEntries[i1..i2];
    }

    auto opSlice() const
    {
        return mEntries[];
    }

    static if(BlendTable)
    {
        auto blend(int col1, int col2) const
        in
        {
            assert(col1 >= 0,    debugConv(col1," ",Count));
            assert(col1 < Count, debugConv(col1," ",Count));
            assert(col2 >= 0,    debugConv(col2," ",Count));
            assert(col2 < Count, debugConv(col2," ",Count));
        }
        body
        {
            return mBlendTable[col1 + Count * col2];
        }
    }
}

final class LightPalette(ColT,int ColorBits, int LightBits)
{
pure nothrow:
private:
    static assert(LightBits > 0);
    enum PlaneSize   = (1 << ColorBits);
    enum PlanesCount = (1 << LightBits);
    enum Count = PlaneSize * PlanesCount;
    ColT[Count] mEntries;
public:
    this(T)(in T[] ent, in T[] colorEnt)
    in
    {
        assert(ent.length      == PlaneSize,   debugConv(ent.length));
        assert(colorEnt.length == PlanesCount, debugConv(colorEnt.length));
    }
    body
    {
        //mEntries[0..PlaneSize] = ent[];
        foreach(i;0..PlanesCount)
        {
            auto plane = mEntries[i * PlaneSize..(i + 1) * PlaneSize];
            foreach(j, ref c; plane[])
            {
                c = ent[j] * colorEnt[i];
            }
        }
    }

    auto opIndex(int i) const
    in
    {
        assert(i >= 0,debugConv(i," ",Count));
        assert(i < Count,debugConv(i," ",Count));
    }
    body
    {
        return mEntries[i];
    }
}

