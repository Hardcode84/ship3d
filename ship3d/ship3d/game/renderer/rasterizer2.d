module game.renderer.rasterizer2;

import std.traits;
import std.algorithm;

import gamelib.graphics.graph;
import gamelib.util;

import game.units;

struct Rasterizer2(BitmapT,TextureT)
{
private:
    BitmapT mBitmap;
    TextureT mTexture;
    Rect mClipRect;
    enum AffineLength = 16;
    struct Edge(PosT, bool Affine, bool HasTextures)
    {
    private:
        immutable PosT xStart;
        immutable PosT xDiff;
        PosT xCurr;
        immutable PosT xDelta;
        
        static if(!Affine)
        {
            PosT swCurr;
            immutable PosT swDelta;
        }
        
        static if(HasTextures)
        {
            static if(Affine)
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
        }
    public:
        this(VT)(in VT v1, in VT v2, int inc) pure nothrow
        {
            const ydiff = v2.pos.y - v1.pos.y;
            assert(ydiff > 0, debugConv(ydiff));
            xStart = v1.pos.x;
            xDiff  = v2.pos.x  - v1.pos.x;
            xDelta = xDiff / ydiff;
            xCurr  = xStart + xDelta * inc;
            
            static if(!Affine)
            {
                const w1 = cast(PosT)1 / v1.pos.w;
                const w2 = cast(PosT)1 / v2.pos.w;
                const swStart = w1;
                const swDiff  = (w2 - w1);
                swDelta = swDiff / ydiff;
                swCurr  = swStart + swDelta * inc;
            }
            
            static if(HasTextures) 
            {
                static if(Affine)
                {
                    const uStart = v1.tpos.u;
                    const uDiff  = v2.tpos.u - v1.tpos.u;
                    uDelta = uDiff / ydiff;
                    uCurr = uStart + uDelta * inc;
                    
                    const vStart = v1.tpos.v;
                    const vDiff  = v2.tpos.v - v1.tpos.v;
                    vDelta = vDiff / ydiff;
                    vCurr = vStart + vDelta * inc;
                }
                else
                {
                    const suStart = v1.tpos.u * w1;
                    const suDiff  = v2.tpos.u * w2 - suStart;
                    suDelta = suDiff / ydiff;
                    suCurr  = suStart + suDelta * inc;
                    
                    const svStart = v1.tpos.v * w1;
                    const svDiff  = v2.tpos.v * w2 - svStart;
                    svDelta = svDiff / ydiff;
                    svCurr  = svStart + svDelta * inc;
                }
            }
        }
        
        @property auto x() const pure nothrow { return xCurr; }
        static if(HasTextures)
        {
            static if(Affine)
            {
                @property auto u() const pure nothrow { return uCurr; }
                @property auto v() const pure nothrow { return vCurr; }
            }
            else
            {
                @property auto su() const pure nothrow { return suCurr; }
                @property auto sv() const pure nothrow { return svCurr; }
            }
        }
        
        static if(!Affine)
        {
            @property auto sw() const pure nothrow { return swCurr; }
        }

        ref auto opUnary(string op: "++")() pure nothrow
        {
            xCurr += xDelta;
            static if(!Affine)
            {
                swCurr += swDelta;
            }
            
            static if(HasTextures)
            {
                static if(Affine)
                {
                    uCurr += uDelta;
                    vCurr += vDelta;
                }
                else
                {
                    suCurr += suDelta;
                    svCurr += svDelta;
                }
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
        
        static if(HasTextures) 
        {
            static if(Affine)
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
        }

        this(EdgeT)(in ref EdgeT e1, in ref EdgeT e2) pure nothrow
        {
            x1 = e1.x;
            x2 = e2.x;
            const dx = x2 - x1 + 1;
            static if(!Affine)
            {
                sw1 = e1.sw;
                sw2 = e2.sw;
                dsw = (sw2 - sw1) / (dx);
            }
            
            static if(HasTextures)
            {
                static if(Affine)
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
            
            static if(HasTextures)
            {
                static if(Affine)
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
            }
            
            static if(HasColor && !Affine)
            {
                factor += factorStep * val;
                colorStart = colorEnd;
                colorEnd = ColT.lerp(color2, color1, factor / sw1);
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
    
    void drawIndexedTriangle(bool HasTextures,VertT,IndT)(in VertT[] verts, in IndT[3] indices) if(isIntegral!IndT)
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
        const affine = false;//(abs(cxdiff) > AffineLength * 25);
        
        if(reverseSpans)
        {
            if(affine) drawTriangle!(HasTextures,true,true)(pverts);
            else       drawTriangle!(HasTextures,false,true)(pverts);
        }
        else
        {
            if(affine) drawTriangle!(HasTextures,true,false)(pverts);
            else       drawTriangle!(HasTextures,false,false)(pverts);
        }
    }
    @nogc private void drawTriangle(bool HasTextures,bool Affine,bool ReverseSpans,VertT)(in VertT[3] pverts)
    {
        static assert(HasTextures != HasColor);
        assert(isSorted!("a.pos.y < b.pos.y")(pverts[0..$]));
        //alias PosT = FixedPoint!(16,16,int);
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
        
        alias EdgeT = Edge!(PosT,Affine,HasTextures,ColT);
        alias SpanT = Span!(PosT,Affine,HasTextures,ColT);
        auto edge1 = EdgeT(pverts[0], pverts[2], minYinc);
        
        auto line = mBitmap[minY];
        
        const minX = cast(PosT)(mClipRect.x);
        const maxX = cast(PosT)(mClipRect.x + mClipRect.w);
        
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
                    line[x] = mTexture.get(u,v);
                    u += span.du;
                    v += span.dv;
                }
            }
        }
        
        foreach(i;TupleRange!(0,2))
        {
            static if(0 == i)
            {
                const yStart  = minY;
                const yEnd    = midY;
                if(yStart == yEnd) continue;
                auto edge2 = EdgeT(pverts[0], pverts[1], minYinc);
            }
            else
            {
                const yStart  = midY;
                const yEnd    = maxY;
                if(yStart == yEnd) continue;
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
                                span.inc(cast(PosT)AffineLength);
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

