module game.renderer.spanmask;

struct SpanMask
{
pure nothrow:
    int y0 = 0, y1 = 0;
    int x0 = 0, x1 = 0;
    struct Span
    {
        int x0, x1;
    }
    Span[] spans;

    this(ST,AT)(in ST size, auto ref AT alloc)
    {
        assert(size.h > 0);
        spans = alloc.alloc!Span(size.h);
        y0 = 0;
        y1 = size.h;
        x0 = 0;
        x1 = size.w;
        spans[] = Span(0,size.w);
    }

    void realloc(AT)(auto ref AT alloc)
    {
        auto oldSpans = spans;
        spans = alloc.alloc!Span(y1);
        spans[y0..y1] = oldSpans[y0..y1];
    }

    @property bool isEmpty() const
    {
        return y0 >= y1 || x0 >= x1;
    }

    void invalidate()
    {
        y0 = 0;
        y1 = 0;
        x0 = 0;
        x1 = 0;
    }
}

