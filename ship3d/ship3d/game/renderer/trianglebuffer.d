module game.renderer.trianglebuffer;

import std.typecons;

/*@nogc pure nothrow:*/
void pushTriangleToBuffer(alias Handler, HeaderT, ElemT)(void[] buffer, auto ref HeaderT header, auto ref ElemT elem)
{
    auto flushFunc = &createFlushFunc!(Handler,HeaderT,ElemT);
    alias FirstElemsType = Tuple!(CommonBufferHeader,HeaderT);
    assert(buffer.length >= (FirstElemsType.sizeof + ElemT.sizeof));
    auto oldHeader = &((*(cast(FirstElemsType*)buffer.ptr))[0]);
    assert(oldHeader is buffer.ptr);

    void flushBuffer() /*@nogc pure nothrow*/
    {
        if(oldHeader.flushFunc !is null)
        {
            oldHeader.flushFunc(buffer);
        }
        *(cast(FirstElemsType*)buffer.ptr) = tuple(CommonBufferHeader(flushFunc , 1), header);
        (buffer.ptr + FirstElemsType.sizeof)[0..ElemT.sizeof] = (cast(void*)&elem)[0..ElemT.sizeof];
    }

    if(oldHeader.flushFunc !is flushFunc)
    {
        flushBuffer();
        return;
    }

    assert(oldHeader.elemCount > 0);
    const reqSize = FirstElemsType.sizeof + (oldHeader.elemCount + 1) * ElemT.sizeof;
    if(reqSize > buffer.length)
    {
        flushBuffer();
        return;
    }
    (buffer.ptr + FirstElemsType.sizeof + oldHeader.elemCount * ElemT.sizeof)[0..ElemT.sizeof] = (cast(void*)&elem)[0..ElemT.sizeof];
    ++oldHeader.elemCount;
}

void flushTriangleBuffer(void[] buffer)
{
    assert(buffer.length > CommonBufferHeader.sizeof);
    auto oldHeader = cast(CommonBufferHeader*)buffer.ptr;
    if(oldHeader.flushFunc !is null)
    {
        oldHeader.flushFunc(buffer);
    }
    *oldHeader = CommonBufferHeader.init;
}

private:
struct CommonBufferHeader
{
    void function(void[]) /*@nogc pure nothrow*/ flushFunc = null;
    int elemCount = 0;
}

void createFlushFunc(alias Handler, HeaderT, ElemT)(void[] buff)
{
    alias FirstElemsType = Tuple!(CommonBufferHeader,HeaderT);
    assert(buff.length >= (FirstElemsType.sizeof + ElemT.sizeof));
    auto header = cast(FirstElemsType*)buff.ptr;
    assert((*header)[0].elemCount > 0);
    auto elems = (cast(ElemT*)(buff.ptr + FirstElemsType.sizeof))[0..(*header)[0].elemCount];
    Handler((*header)[1], elems);
}