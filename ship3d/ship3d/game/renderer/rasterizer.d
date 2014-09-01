﻿module game.renderer.rasterizer;

import std.traits;
import std.algorithm;

import gamelib.util;

import game.units;

struct Rasterizer(BitmapT,TextureT)
{
private:
    BitmapT mBitmap;
    TextureT mTexture;
    Rect mClipRect;
    enum AffineLength = 32;
    struct Edge(PosT, bool Affine, bool HasTextures, ColT)
    {
    private:
        enum HasColor = !is(ColT : void);
        immutable PosT xStart;
        immutable PosT xDiff;
        PosT xCurr;
        immutable PosT xDelta;

        static if(!Affine)
        {
            PosT swCurr;
            immutable PosT swDelta;
        }

        static if(HasTextures) static if(Affine)
        {
            PosT uCurr;
            immutable PosT uDelta;

            PosT vCurr;
            immutable PosT vDelta;
        }
        else
        {
            PosT suCurr;
            immutable PosT suDelta;

            PosT svCurr;
            immutable PosT svDelta;
        }

        static if(HasColor)
        {
            PosT scCurr;
            immutable PosT scDelta;
            ColT color1 = void;
            ColT color2 = void;
        }
    public:
        this(VT)(in VT v1, in VT v2, int inc) pure nothrow
        {
            const ydiff = v2.pos.y - v1.pos.y;
            xStart = v1.pos.x;
            xDiff  = v1.pos.x  - v2.pos.x;
            xCurr  = xStart;
            xDelta = xDiff / ydiff;
            static if(!Affine)
            {
                const w1 = cast(PosT)1 / v1.pos.w;
                const w2 = cast(PosT)1 / v2.pos.w;
                //debugOut("-1-");
                //debugOut(w1);
                //debugOut(w2);
                const swStart = w1;
                const swDiff  = (w1 - w2);
                swDelta = swDiff / (ydiff + 1);
                swCurr  = swStart + swDelta * inc;
            }

            static if(HasTextures) static if(Affine)
            {
                const uStart = v1.tpos.u;
                const uDiff  = v1.tpos.u - v2.tpos.u;
                uDelta = uDiff / ydiff;
                uCurr = uStart + uDelta * inc;

                const vStart = v1.tpos.v;
                const vDiff  = v1.tpos.v - v2.tpos.v;
                vDelta = vDiff / ydiff;
                vCurr = vStart + vDelta * inc;
            }
            else
            {
                const suStart = v1.tpos.u * w1;
                const suDiff  = suStart - v2.tpos.u * w2;
                suDelta = suDiff / ydiff;
                suCurr  = suStart + suDelta * inc;

                const svStart = v1.tpos.v * w1;
                const svDiff  = svStart - v2.tpos.v * w2;
                svDelta = svDiff / ydiff;
                svCurr  = svStart + svDelta * inc;
            }

            static if(HasColor)
            {
                static if(Affine)
                {
                    scDelta = cast(PosT)1 / ydiff;
                }
                else
                {
                    scDelta = w2 / ydiff;
                }
                scCurr = scDelta * inc;
                //debugOut("-2-");
                //debugOut(ydiff);
                //debugOut(scCurr);
                //debugOut(scDelta);
                color1 = v1.color;
                color2 = v2.color;
            }
        }

        @property auto x() const pure nothrow { return xCurr; }
        static if(HasTextures) static if(Affine)
        {
            @property auto u() const pure nothrow { return uCurr; }
            @property auto v() const pure nothrow { return vCurr; }
        }
        else
        {
            @property auto su() const pure nothrow { return suCurr; }
            @property auto sv() const pure nothrow { return svCurr; }
        }

        static if(!Affine)
        {
            @property auto sw() const pure nothrow { return swCurr; }
        }

        static if(HasColor)
        {
            @property auto color() const pure nothrow
            {
                static if(Affine)
                {
                    const f = scCurr;
                    //debugOut("---");
                    //debugOut(scCurr);
                    //debugOut(scDelta);
                }
                else
                {
                    const f = scCurr / sw;
                    //debugOut("---");
                    //debugOut(scCurr);
                    //debugOut(scDelta);
                    //debugOut(sw);
                    //debugOut(swDelta);
                    //debugOut(f);
                }
                return ColT.lerp(color1, color2, f);
            }
        }

        ref auto opUnary(string op: "++")() pure nothrow
        {
            xCurr += xDelta;
            static if(!Affine)
            {
                swCurr += swDelta;
            }

            static if(HasTextures) static if(Affine)
            {
                uCurr += uDelta;
                vCurr += vDelta;
            }
            else
            {
                suCurr += suDelta;
                svCurr += svDelta;
            }

            static if(HasColor)
            {
                scCurr += scDelta;
            }
            return this; 
        }
    }
    struct Span(PosT, bool Affine,bool HasTextures, ColT)
    {
        private enum HasColor = !is(ColT : void);
        PosT x1, x2;
        static if(!Affine)
        {
            PosT sw1, sw2;
            immutable PosT dsw;
        }

        static if(HasTextures) static if(Affine)
        {
            PosT u, u2;
            PosT v, v2;
            immutable PosT du, dv;
        }
        else
        {
            PosT su1, su2;
            PosT sv1, sv2;
            immutable PosT dsu, dsv;
            PosT nu, nv;
            PosT pu, pv;
            PosT du, dv;
        }

        static if(HasColor)
        {
            PosT factor;
            immutable PosT factorStep;
            ColT color1 = void;
            ColT color2 = void;
            ColT colorStart = void;
            ColT colorEnd = void;
        }

        this(EdgeT)(in EdgeT e1, in EdgeT e2) pure nothrow
        {
            x1 = e1.x;
            x2 = e2.x;
            const dx = x2 - x1;
            static if(!Affine)
            {
                sw1 = e1.sw;
                sw2 = e2.sw;
                dsw = (sw2 - sw1) / (dx + 1);
            }

            static if(HasTextures) static if(Affine)
            {
                u  = e1.u;
                u2 = e2.u;
                v  = e1.v;
                v2 = e2.v;
                du = (u2 - u) / dx;
                dv = (v2 - v) / dx;
            }
            else
            {
                su1 = e1.su;
                su2 = e2.su;
                sv1 = e1.sv;
                sv2 = e2.sv;

                dsu = (su2 - su1) / dx;
                dsv = (sv2 - sv1) / dx;

                nu = su1 / sw1;
                nv = sv1 / sw1;
            }

            static if(HasColor)
            {
                factor = 0;
                factorStep = cast(PosT)1 / (dx + 1);
                color1 = e1.color;
                color2 = e2.color;
                static if(Affine)
                {
                    colorStart = color1;
                    colorEnd   = color2;
                }
                else
                {
                    //colorStart= color1; //
                    colorEnd = color2;
                }
            }
        }
        @property bool valid() const pure nothrow { return x2 > x1; }
        void clip(PosT minX, PosT maxX) pure nothrow
        {
            const x1inc = max(cast(PosT)0, minX - x1);
            x1 += x1inc;
            x2 = min(x2, maxX);
            if(!valid) return;
            inc(x1inc);
        }
        void inc(in PosT val) pure nothrow
        in
        {
            assert(valid);
        }
        body
        {
            static if(!Affine)
            {
                sw1 += dsw * val;
            }

            static if(HasTextures) static if(Affine)
            {
                u += du * val;
                v += dv * val;
            }
            else
            {
                pu = nu;
                pv = nv;
                su1 += dsu * val;
                sv1 += dsv * val;
                nu = su1 / sw1;
                nv = sv1 / sw1;
                du = (nu - pu) / val;
                dv = (nv - pv) / val;
            }

            static if(HasColor && !Affine)
            {
                factor += factorStep * val;
                colorStart = colorEnd;
                colorEnd = ColT.lerp(color2, color1, factor);
            }
        }
        static if(HasTextures) static if(!Affine)
        {
            @property PosT u() const pure nothrow { return pu; }
            @property PosT v() const pure nothrow { return pv; }
        }
    }
public:
    this(BitmapT b)
    {
        assert(b !is null);
        b.lock();
        mBitmap = b;
        mClipRect = Rect(0, 0, mBitmap.width, mBitmap.height);
    }

    ~this()
    {
        mBitmap.unlock();
    }

    @property auto texture() inout pure nothrow { return mTexture; }
    @property void texture(TextureT tex) pure nothrow { mTexture = tex; }

    @property void clipRect(in Rect rc) pure nothrow
    {
        const srcLeft   = rc.x;
        const srcTop    = rc.y;
        const srcRight  = rc.x + rc.w;
        const srcBottom = rc.y + rc.h;
        const dstLeft   = max(0, srcLeft);
        const dstTop    = max(0, srcTop);
        const dstRight  = min(srcRight,  mBitmap.width);
        const dstBottom = min(srcBottom, mBitmap.height);
        mClipRect = Rect(dstLeft, dstTop, dstRight - dstLeft, dstBottom - dstTop);
    }

    void drawIndexedTriangle(bool HasTextures = false, bool HasColor = true,VertT,IndT)(in VertT[] verts, in IndT[3] indices) if(isIntegral!IndT)
    {
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        sort!("a.pos.y < b.pos.y")(pverts[0..$]);

        const e1xdiff = pverts[0].pos.x - pverts[2].pos.x;
        const e2xdiff = pverts[0].pos.x - pverts[1].pos.x;

        const e1ydiff = pverts[0].pos.y - pverts[2].pos.y;
        const e2ydiff = pverts[0].pos.y - pverts[1].pos.y;

        const cxdiff = ((e1xdiff / e1ydiff) * e2ydiff) - e2xdiff;
        const reverseSpans = (cxdiff < 0);
        const affine = true;//(abs(cxdiff) > AffineLength * 25);

        if(reverseSpans)
        {
            if(affine) drawTriangle!(HasTextures, HasColor,true,true)(pverts);
            else       drawTriangle!(HasTextures, HasColor,false,true)(pverts);
        }
        else
        {
            if(affine) drawTriangle!(HasTextures, HasColor,true,false)(pverts);
            else       drawTriangle!(HasTextures, HasColor,false,false)(pverts);
        }
    }
    private void drawTriangle(bool HasTextures, bool HasColor,bool Affine,bool ReverseSpans,VertT)(in VertT[3] pverts)
    {
        static assert(HasTextures != HasColor);
        assert(isSorted!("a.pos.y < b.pos.y")(pverts[0..$]));
        alias PosT = Unqual!(typeof(VertT.pos.x));
        auto minY = cast(int)pverts[0].pos.y;
        auto midY = cast(int)pverts[1].pos.y;
        auto maxY = cast(int)pverts[2].pos.y;

        const minYinc = max(0, mClipRect.y - minY);
        const midYinc = max(0, mClipRect.y - midY);
        minY += minYinc;
        midY += midYinc;
        maxY = min(maxY, mClipRect.y + mClipRect.h);
        if(minY >= maxY) return;
        midY = min(midY, maxY);

        static if(HasColor)
        {
            alias ColT = Unqual!(typeof(VertT.color));
        }
        else
        {
            alias ColT = void;
        }
        alias EdgeT = Edge!(PosT,Affine,HasTextures,ColT);
        alias SpanT = Span!(PosT,Affine,HasTextures,ColT);
        auto edge1 = EdgeT(pverts[0], pverts[2], minYinc);

        auto line = mBitmap[minY];

        const minX = cast(PosT)(mClipRect.x);
        const maxX = cast(PosT)(mClipRect.x + mClipRect.w);

        static if(HasTextures)
        {
            const tw = mTexture.width - 1;
            const th = mTexture.height - 1;
            const tview = mTexture.view();
        }
        void drawSpan(int y,
                      int x1, int x2,
                      in SpanT span)
        {
            if(x1 >= x2) return;
            static if(HasTextures)
            {
                Unqual!(typeof(span.u)) u = span.u;
                Unqual!(typeof(span.v)) v = span.v;
                foreach(x;x1..x2)
                {
                    const tx = cast(int)(u * tw) & tw;
                    const ty = cast(int)(v * th) & th;
                    line[x] = tview[ty][tx];
                    u += span.du;
                    v += span.dv;
                }
            }

            static if(HasColor)
            {
                void divLine(int x1, int x2, in ColT col1, in ColT col2)
                {
                    if((x2 - x1) <= 1) return;
                    const x = x1 + (x2 - x1) / 2;
                    const col = ColT.average(col1, col2);
                    line[x] = col;
                    divLine(x1, x , col1, col);
                    divLine(x , x2, col , col2);
                }
                divLine(x1, x2 + 1, span.colorStart, span.colorEnd);
                //line[x1..x2] = span.colorStart;
                /*foreach(x;x1..x2)
                {
                    //line[x] = span.colorStart;
                    //line[x] = (y % 2 == 1) ? span.colorStart : span.colorEnd;
                    line[x] = ColT.lerp(span.colorEnd, span.colorStart, cast(PosT)(x - x1) / cast(PosT)(x2 - x1));
                }*/

            }
            //line[x1..x2] = ColorRed;
        }

        foreach(i;TupleRange!(0,2))
        {
            static if(0 == i)
            {
                const yStart  = minY;
                const yEnd    = midY;
                auto edge2 = EdgeT(pverts[0], pverts[1], minYinc);
            }
            else
            {
                const yStart  = midY;
                const yEnd    = maxY;
                auto edge2 = EdgeT(pverts[1], pverts[2], midYinc);
            }

            foreach(y;yStart..yEnd)
            {
                static if(ReverseSpans)
                {
                    auto span = SpanT(edge2, edge1);
                }
                else
                {
                    auto span = SpanT(edge1, edge2);
                }
                span.clip(minX, maxX);
                //debugOut(y);
                if(span.valid)
                {
                    const ix1 = cast(int)span.x1;
                    const ix2 = cast(int)span.x2;
                    static if(Affine)
                    {
                        drawSpan(y, ix1, ix2, span);
                    }
                    else
                    {
                        int x = ix1;
                        while(true)
                        {
                            const nx = (x + AffineLength);
                            if(nx < ix2)
                            {
                                span.inc(AffineLength);
                                drawSpan(y, x, nx, span);
                            }
                            else
                            {
                                const rem =  cast(PosT)(ix2 - x);
                                span.inc(rem);
                                drawSpan(y, x, ix2, span);
                                break;
                            }
                            x = nx;
                        }
                    }
                }
                ++edge1;
                ++edge2;
                ++line;
            }
        }
    }
}

