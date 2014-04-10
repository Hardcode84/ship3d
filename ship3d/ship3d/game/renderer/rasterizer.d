module game.renderer.rasterizer;

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
    enum AffineLength = 16;
    struct Edge(PosT, bool Affine)
    {
    private:
        PosT factor;
        immutable PosT factorStep;
        immutable PosT xStart;
        immutable PosT xDiff;

        static if(Affine)
        {
            immutable PosT uStart;
            immutable PosT uDiff;

            immutable PosT vStart;
            immutable PosT vDiff;
        }
        else
        {
            immutable PosT suStart;
            immutable PosT suDiff;

            immutable PosT svStart;
            immutable PosT svDiff;

            immutable PosT swStart;
            immutable PosT swDiff;
        }
    public:
        this(VT)(in VT v1, in VT v2, int inc) pure nothrow
        {
            const ydiff = v1.pos.y - v2.pos.y;
            factorStep = cast(PosT)1 / ydiff;
            factor = factorStep * inc;
            xStart = v1.pos.x;
            xDiff  = v1.pos.x  - v2.pos.x;
            static if(Affine)
            {
                uStart = v1.tpos.u;
                uDiff  = v1.tpos.u - v2.tpos.u;
                vStart = v1.tpos.v;
                vDiff  = v1.tpos.v - v2.tpos.v;
            }
            else
            {
                const w1 = cast(PosT)1 / v1.pos.w;
                const w2 = cast(PosT)1 / v2.pos.w;
                suStart = v1.tpos.u * w1;
                suDiff  = suStart - v2.tpos.u * w2;
                svStart = v1.tpos.v * w1;
                svDiff  = svStart - v2.tpos.v * w2;
                swStart = w1;
                swDiff  = (w1 - w2);
            }
        }

        @property auto x() const pure nothrow { return xStart + xDiff * factor; }
        static if(Affine)
        {
            @property auto u() const pure nothrow { return uStart + uDiff * factor; }
            @property auto v() const pure nothrow { return vStart + vDiff * factor; }
        }
        else
        {
            @property auto su() const pure nothrow { return suStart + suDiff * factor; }
            @property auto sv() const pure nothrow { return svStart + svDiff * factor; }
            @property auto sw() const pure nothrow { return swStart + swDiff * factor; }
        }
        ref auto opUnary(string op: "++")() pure nothrow { factor += factorStep; return this; }
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

    void drawIndexedTriangle(VertT,IndT)(in VertT[] verts, in IndT[3] indices) if(isIntegral!IndT)
    {
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        sort!("a.pos.y < b.pos.y")(pverts[0..$]);

        const e1xdiff = pverts[0].pos.x - pverts[2].pos.x;
        const e2xdiff = pverts[0].pos.x - pverts[1].pos.x;

        const e1ydiff = pverts[0].pos.y - pverts[2].pos.y;
        const e2ydiff = pverts[0].pos.y - pverts[1].pos.y;

        const bool reverseSpans = ((e1xdiff / e1ydiff) * e2ydiff) < e2xdiff;

        drawTriangle!false(pverts, reverseSpans);
    }
    private void drawTriangle(bool Affine,VertT)(in VertT[3] pverts, bool reverseSpans)
    {
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

        auto edge1 = Edge!(PosT,Affine)(pverts[0], pverts[2], minYinc);

        auto line = mBitmap[minY];

        const minX = cast(PosT)(mClipRect.x);
        const maxX = cast(PosT)(mClipRect.x + mClipRect.w);
        foreach(i;TupleRange!(0,2))
        {
            static if(0 == i)
            {
                const yStart  = minY;
                const yEnd    = midY;
                auto edge2 = Edge!(PosT,Affine)(pverts[0], pverts[1], minYinc);
            }
            else
            {
                const yStart  = midY;
                const yEnd    = maxY;
                auto edge2 = Edge!(PosT,Affine)(pverts[1], pverts[2], midYinc);
            }

            foreach(y;yStart..yEnd)
            {
                auto x1 = edge1.x;
                auto x2 = edge2.x;
                if(reverseSpans)
                {
                    swap(x1, x2);
                }
                const dx = (x2 - x1);
                const x1inc = max(cast(PosT)0, minX - x1);
                x1 += x1inc;
                x2 = min(x2, maxX);

                const ix1 = cast(int)x1;
                const ix2 = cast(int)x2;
                static if(Affine)
                {
                    auto u1 = edge1.u;
                    auto u2 = edge2.u;
                    auto v1 = edge1.v;
                    auto v2 = edge2.v;
                    if(reverseSpans)
                    {
                        swap(u1, u2);
                        swap(v1, v2);
                    }
                    const du = (u2 - u1) / dx;
                    const dv = (v2 - v1) / dx;
                    u1 += du * x1inc;
                    v1 += dv * x1inc;

                    drawSpan(line, y, ix1, ix2, u1, du, v1, dv);
                }
                else
                {
                    auto su1 = edge1.su;
                    auto su2 = edge2.su;
                    auto sv1 = edge1.sv;
                    auto sv2 = edge2.sv;
                    auto sw1 = edge1.sw;
                    auto sw2 = edge2.sw;
                    if(reverseSpans)
                    {
                        swap(su1, su2);
                        swap(sv1, sv2);
                        swap(sw1, sw2);
                    }
                    const dsu = (su2 - su1) / dx;
                    const dsv = (sv2 - sv1) / dx;
                    const dsw = (sw2 - sw1) / dx;
                    su1 += dsu * x1inc;
                    sv1 += dsv * x1inc;
                    sw1 += dsw * x1inc;

                    auto u = su1 / sw1;
                    auto v = sv1 / sw1;
                    int x = ix1;
                    while(true)
                    {
                        const nx = (x + AffineLength);
                        if(nx < ix2)
                        {
                            su1 += dsu * cast(PosT)AffineLength;
                            sv1 += dsv * cast(PosT)AffineLength;
                            sw1 += dsw * cast(PosT)AffineLength;
                            const nu = su1 / sw1;
                            const nv = sv1 / sw1;
                            const du = (nu - u) / cast(PosT)AffineLength;
                            const dv = (nv - v) / cast(PosT)AffineLength;
                            drawSpan(line, y, x, nx, u, du, v, dv);
                            u = nu;
                            v = nv;
                        }
                        else
                        {
                            const rem =  cast(PosT)(ix2 - x);
                            su1 += dsu * rem;
                            sv1 += dsv * rem;
                            sw1 += dsw * rem;
                            const nu = su1 / sw1;
                            const nv = sv1 / sw1;
                            const du = (nu - u) / rem;
                            const dv = (nv - v) / rem;
                            drawSpan(line, y, x, ix2, u, du, v, dv);
                            break;
                        }
                        x = nx;
                    }
                }
                ++edge1;
                ++edge2;
                ++line;
            }
        }
    }
    private void drawSpan(LineT)(auto ref LineT line,
                                 int y,
                                 int x1, int x2,
                                 float u1, float du,
                                 float v1, float dv)
    {
        if(x1 >= x2) return;
        const w = mTexture.width - 1;
        const h = mTexture.height - 1;
        const tview = mTexture.view();
        auto u = u1;
        auto v = v1;
        foreach(x;x1..x2)
        {
            const tx = cast(int)(u * w);
            const ty = cast(int)(v * h);
            line[x] = tview[ty][tx];
            u += du;
            v += dv;
        }
    }
}

