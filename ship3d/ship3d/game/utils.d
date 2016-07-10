module game.utils;

import std.traits;
import std.range;
import std.algorithm;

import game.units;

@nogc TransformedVertex transformVertex(in Vertex v, in mat4_t mat) pure nothrow @safe
{
    TransformedVertex ret = void;
    ret.refPos = v.pos;
    ret.pos    = mat * vec4_t(v.pos, 1);
    ret.tpos   = v.tpos;
    return ret;
}

auto transformVertices(VertRange, IndRange, Alloc)(auto ref VertRange vertices, auto ref IndRange indices, auto ref Alloc alloc, in mat4_t mat)
{
    auto transformedVertices = alloc.alloc!TransformedVertex(vertices.length);

    auto allocState = alloc.state;
    scope(exit) alloc.restoreState(allocState);

    auto transformedVerticesFlags = alloc.alloc!bool(vertices.length, false);

    foreach(ind; indices)
    {
        if(!transformedVerticesFlags[ind])
        {
            transformedVertices[ind] = transformVertex(vertices[ind], mat);
            transformedVerticesFlags[ind] = true;
        }
    }
    return transformedVertices;
}

auto fastCast(Dst,Src)(Src src) if(is(Src == class) && is(Dst == class))
{
    return cast(Dst)(cast(void*)src);
}

pure nothrow @nogc:
version(LDC)
{
    pragma(LDC_inline_ir)
        R inlineIR(string s, R, P...)(P);
}

struct NtsRange(T)
{
    pure nothrow @nogc:
    T[] dstRange;

    void opIndexAssign(in T val, size_t ind)
    {
        static assert(T.sizeof == 4);
        dstRange[ind] = val;
        //inlineIR!(`store i32 %0, i32* %1, align 4, !nontemporal !0`, void)(*(cast(int*)&val), cast(int*)dstRange.ptr + ind);
    }

    auto length() const { return dstRange.length; }
}

auto ntsRange(T)(T[] range)
{
    return NtsRange!T(range);
}

auto numericCast(DstT,SrcT)(in SrcT src)
{
    return cast(DstT)src;
}

auto reinterpret(DstT,SrcT)(in SrcT src) pure nothrow @nogc
{
    union U
    {
        DstT dst = void;
        SrcT src = void;
    }
    U u = {src: src};
    return u.dst;
}

auto floatSign(in float src) pure nothrow @nogc
{
    const val = reinterpret!uint(src);
    return (val & (1 << 31));
}

auto floatInvSign(in float src) pure nothrow @nogc
{
    return floatSign(src) ^ (1 << 31);
}

version(LDC)
{
    pragma(LDC_intrinsic, "llvm.assume")
        void assume(bool);
}

struct AllocatorsState(AllocT)
{
    AllocT[] mAllocs;
    alias AllocState = Unqual!(typeof(AllocT.state));
    AllocState[] mStates;

    this(AllocT[] allocs)
    {
        assert(allocs.length > 0);
        auto alloc = allocs[0];
        auto firstState = alloc.state;
        mStates = alloc.alloc!AllocState(allocs.length);
        mStates[0] = firstState;
        foreach(i; 1..allocs.length)
        {
            mStates[i] = allocs[i].state();
        }
        mAllocs = allocs;
        assert(mAllocs.length == mStates.length);
    }

    auto allocs() inout
    {
        return mAllocs;
    }

    auto restore()
    {
        assert(mAllocs.length == mStates.length);
        foreach_reverse(i;0..mAllocs.length)
        {
            mAllocs[i].restoreState(mStates[i]);
        }
        mAllocs = mAllocs.init;
        mStates = mStates.init;
    }
}

auto saveAllocsStates(AllocT)(AllocT[] allocs)
{
    return AllocatorsState!AllocT(allocs);
}