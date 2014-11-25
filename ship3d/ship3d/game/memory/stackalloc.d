module game.memory.stackalloc;

import std.traits;

import gamelib.types;
import gamelib.memory.utils;

final class StackAlloc
{
private:
    void[] mMemory;
    void*  mPtr;
public:
    this(size_t bytes) pure nothrow
    {
        mMemory.length = bytes;
        mPtr = mMemory.ptr;
    }

@nogc pure nothrow:

    alias State = void*;

    @property State state()
    {
        return mPtr;
    }

    void restoreState(State s)
    in
    {
        assert(s >= mMemory.ptr);
        assert(s <  mMemory.ptr + mMemory.length);
    }
    body
    {
        mPtr = s;
    }

    auto alloc(T)(int count)
    in
    {
        assert(count >= 0);
    }
    body
    {
        static assert(__traits(isPOD,T));
        enum size = T.sizeof;
        auto ptr = alignPointer!T(mPtr);
        auto ptrEnd = ptr + size * count;
        const memEnd = mMemory.ptr + mMemory.length;
        assert(ptr >= mMemory.ptr);
        assert(ptr < memEnd);
        assert(ptrEnd < memEnd);
        mPtr = ptrEnd;
        return (cast(T*)ptr)[0..count];
    }

    auto alloc(T)()
    {
        return alloc!T(1).ptr;
    }
}

