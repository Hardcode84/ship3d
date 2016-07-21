module game.renderer.rasterizertiled3.draw;

import std.algorithm;
import std.range;

import game.units;

import game.renderer.rasterizertiled3.types;

@nogc pure nothrow:
void drawPreparedTriangle(size_t TWidth, bool FillBack, AllocT,CtxT1,CtxT2,PrepT)
    (auto ref AllocT alloc, in Rect clipRect, auto ref CtxT1 outContext, auto ref CtxT2 extContext, auto ref PrepT prepared, int index, int minY, int maxY)
{
    //debugOut("draw");
    enum Full = (TWidth > 0);
    static assert(!(Full && FillBack));
    static assert(!Full || (TWidth >= AffineLength && 0 == (TWidth % AffineLength)));
    assert(maxY > minY);
    assert(minY >= clipRect.y);

    const size = outContext.size;

    if(prepared.needSetup)
    {
        prepared.setup(extContext.vertspack.verts, extContext.vertspack.tcoords, size);
    }

    void drawSpan(uint AffLen, bool UseDither, S, L)(
        int y,
        int x1, int x2,
        in auto ref S span,
        auto ref L line)
    {
        enum FixedLen = (AffLen > 0);
        //assert((x2 - x1) <= AffLen);
        assert(x2 > x1);
        struct Transform
        {
        @nogc pure nothrow:
            static auto opCall(T)(in T val,int) { return val; }
        }
        alias TexT = Unqual!(typeof(span.u));
        struct Context
        {
            Transform colorProxy;
            int x;
            const int y;
            TexT u;
            TexT v;
            const TexT dux;
            const TexT dvx;
            enum dither = UseDither;
        }
        Context ctx = {x: x1, y: y, u: span.u, v: span.v, dux: span.dux, dvx: span.dvx};

        static if(FixedLen)
        {
            static if(Full)
            {
                assert(0 == (cast(size_t)line.ptr & (64 - 1)));
                //assume(0 == (cast(size_t)line.ptr & (64 - 1)));
            }
            assert(x2 == (x1 + AffLen));
            extContext.context.texture.getLine!AffLen(ctx,line[x1..x1 + AffLen]);
            //extContext.context.texture.getLine!AffLen(ctx,ntsRange(line[x1..x2]));
        }
        else
        {
            extContext.context.texture.getLine!0(ctx,line[x1..x2]);
        }
        //line[x1..x2] = (UseDither ? ColorRed : ColorGreen);
    }

    const clipSize = Size(clipRect.w,clipRect.h);
    void outerLoop(bool Affine)()
    {
        static if(Full)
        {
            const sy = clipRect.y;
            const sx = clipRect.x;
            const ey = clipRect.y + clipRect.h;
            const x0 = sx;
            const x1 = x0 + TWidth;
        }
        else
        {
            const area = prepared.areas[index & AreaIndexMask];
            const sy = max(minY, area.y0);

            auto iter0 = area.iter0(sy);
            auto iter1 = area.iter1(sy);

            const sx = max(clipRect.x, iter0.x);
            const ey = min(clipRect.y + clipRect.h, area.y1, maxY);
            const minX = clipRect.x;
            const maxX = clipRect.x + clipRect.w;
        }

        static if(FillBack)
        {
            const backColor = outContext.backColor;
            const beginLine = clipRect.x;
            const endLine   = clipRect.x + clipRect.w;
            auto line = outContext.surface[clipRect.y];
            foreach(y;clipRect.y..sy)
            {
                line[beginLine..endLine] = backColor;
                ++line;
            }
        }
        else
        {
            auto line = outContext.surface[sy];
        }

        alias SpanT = Span!(float, Affine);

        auto span = SpanT(prepared, sx, sy, clipSize);
        void innerLoop(uint AffLen, bool UseDither)()
        {
            static if(!Full)
            {
                auto tempIter0 = iter0;
                auto tempIter1 = iter1;
            }

            foreach(y;sy..ey)
            {
                static if(!Full)
                {
                    const x0 = max(minX, tempIter0.x);
                    const x1 = min(maxX, tempIter1.x);
                    tempIter0.incY();
                    tempIter1.incY();
                    if(y == sy)
                    {
                        assert(x0 == sx);
                        span.initX();
                    }
                    else
                    {
                        const dx = x0 - sx;
                        span.incXY(dx);
                    }

                    assert(x1 >= x0);
                    const validLine = (x1 > x0); //FIXME
                }
                else
                {
                    if(y == sy)
                    {
                        span.initX();
                    }
                    else
                    {
                        span.incXY();
                    }
                    enum validLine = true;
                }

                if(validLine)
                {
                    static if(FillBack)
                    {
                        line[beginLine..x0] = backColor;
                    }

                    int x = x0;

                    static if(!Affine)
                    {
                        static if(!Full)
                        {
                            /*const nx = (x + ((AffLen - 1)) & ~(AffLen - 1));
                                assert(x >= clipRect.x);
                                if(nx > x && nx < x1)
                                {
                                    assert(nx <= (clipRect.x + clipRect.w));
                                    static if(HasLight) lightProx.incX();
                                    span.incX(nx - x - 1);
                                    drawSpan!(0,UseDither)(y, x, nx, span, line);
                                    x = nx;
                                }
                                const affParts = ((x1-x) / AffLen);*/
                            const affParts = ((x1-x0) / AffLen);
                        }
                        else
                        {
                            //Full
                            enum affParts = TWidth / AffLen;
                        }

                        foreach(i;0..affParts)
                        {
                            assert(x >= clipRect.x);
                            assert((x + AffLen) <= (clipRect.x + clipRect.w));
                            span.incX(AffLen);
                            drawSpan!(AffLen,UseDither)(y, x, x + AffLen, span, line);
                            x += AffLen;
                        }

                        static if(!Full)
                        {
                            assert(x <= (clipRect.x + clipRect.w));
                            const rem = (x1 - x);
                            assert(rem >= 0);
                            if(rem > 0)
                            {
                                span.incX(rem);
                                drawSpan!(0,UseDither)(y, x, x1, span, line);
                            }
                        }
                    }
                    else
                    {
                        static if(Full)
                        {
                            span.incX(TWidth);
                            drawSpan!(TWidth,UseDither)(y, x, x + TWidth, span, line);
                        }
                        else
                        {
                            span.incX(x1 - x0);
                            drawSpan!(0,UseDither)(y, x0, x1, span, line);
                        }
                    }

                    static if(FillBack)
                    {
                        line[x1..endLine] = backColor;
                    }
                    //line[x0..x1] = (Affine ? ColorRed : ColorGreen);
                }
                else static if(FillBack)
                {
                    line[beginLine..endLine] = backColor;
                }

                debug
                {
                    static if(FillBack)
                    {
                        outContext.pixelsDrawn += (endLine - beginLine);
                    }
                    else
                    {
                        outContext.pixelsDrawn += (x1 - x0);
                    }
                }

                ++line;
            }

            static if(FillBack)
            {
                foreach(y;ey..(clipRect.y + clipRect.h))
                {
                    line[beginLine..endLine] = backColor;
                    ++line;
                }
            }
        }

        static if(UseDithering)
        {
            const maxD = span.calcMaxD(3.0f);
            const D = 1.0f / min(extContext.texture.width,extContext.texture.height);
            if(maxD < D)
            {
                innerLoop!(AffineLength,true)();
            }
            else
            {
                innerLoop!(AffineLength,false)();
            }
        }
        else
        {
            innerLoop!(AffineLength,false)();
        }
    }

    const maxW = prepared.maxW;
    const minW = prepared.minW;
    const wDiff = maxW - minW;
    assert(wDiff >= 0);
    const affineThresh = (32.0f / max(clipSize.w, clipSize.h));
    if(minW < -4.0f && wDiff < affineThresh)
    {
        outerLoop!(true)();
    }
    else
    {
        outerLoop!(false)();
    }
}

void fillBackground(CtxT1)
    (in Rect clipRect, auto ref CtxT1 outContext)
{
    const color = outContext.backColor;
    const y0 = clipRect.y;
    const y1 = clipRect.y + clipRect.h;
    const x0 = clipRect.x;
    const x1 = clipRect.x + clipRect.w;
    auto line = outContext.surface[y0];
    foreach(y;y0..y1)
    {
        line[x0..x1] = color;
        ++line;
    }
}