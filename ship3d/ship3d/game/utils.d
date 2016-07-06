module game.utils;

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


version(LDC)
{
    pragma(LDC_intrinsic, "llvm.assume")
        void assume(bool);
}