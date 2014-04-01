module gamelib.graphics.graph;

import std.traits: Unqual;
import std.range: isRandomAccessRange;

import gamelib.math;
import gamelib.util;

//poly drawing algo from TarasB
void poly(BitmapT,PtsRngT,ColorT)(BitmapT b, PtsRngT pt, in ColorT color) /*if(isRandomAccessRange!pts)*/
{
    b.lock();
    scope(exit) b.unlock();
    assert(pt.length > 0);
    auto count = pt.length;
    alias ptctype_t = Unqual!(typeof(pt[0].x));
    enum half = cast(ptctype_t)1 / cast(ptctype_t)2;
    auto minY = cast(int)(pt[0].y);
    auto maxY = cast(int)(pt[0].y);
    size_t m0 = 0;
    foreach(i;1..count)
    {
        auto y = cast(int)(pt[i].y);
        if(y < minY) m0 = i;
        minY = min(minY, y);
        maxY = max(maxY, y);
    }
    minY = max(minY, 0);
    maxY = min(maxY, b.height);

    size_t ip1, ip2, in1=m0, in2=m0;

    ptctype_t x1, x2, dx1, dx2;

    if(minY>=maxY) return;
    auto line = b[minY];

    foreach(y;minY..maxY)
    {
        if(y >= cast(int)(pt[in1].y)) // переход к следующему отрезку
        {
            do
            {
                ip1 = in1;
                in1 = (in1 == 0 ? count - 1 : in1 - 1);
            } while(y >= cast(int)(pt[in1].y));

            if((y + 1) == cast(int)(pt[in1].y))
            {
                dx1 = (pt[in1].x > pt[ip1].x ? 1000 : -1000);
                x1 = pt[ip1].x + (pt[in1].x - pt[ip1].x) * ((cast(ptctype_t)(y + 1) - pt[ip1].y) / (pt[in1].y - pt[ip1].y));
            }
            else
            {
                dx1 = (pt[in1].x - pt[ip1].x) / (pt[in1].y - pt[ip1].y);
                x1 = pt[ip1].x + (cast(ptctype_t)(y + 1) - pt[ip1].y) * dx1;
            }
            x1 -= half;
        }
        
        if(y >= cast(int)(pt[in2].y)) // переход к следующему отрезку
        {
            do // находим следующий нужный участок
            {
                ip2 = in2;
                in2 = (in2 == (count - 1) ? 0 : in2 + 1);
            } while(y >= cast(int)(pt[in2].y));

            if((y + 1) == cast(int)(pt[in2].y)) // вырожденный случай
            {
                dx2 = pt[in2].x > pt[ip2].x ? 1000 : -1000;
                x2 = pt[ip2].x + (pt[in2].x - pt[ip2].x) * ((cast(ptctype_t)(y + 1) - pt[ip2].y) / (pt[in2].y - pt[ip2].y));
            }
            else
            {
                dx2 = (pt[in2].x - pt[ip2].x) / (pt[in2].y - pt[ip2].y);
                x2 = pt[ip2].x + (cast(ptctype_t)(y + 1) - pt[ip2].y) * dx2;
            }
            x2 += half;
        }

        int ax1 = max(cast(int)(x1) + 1, 0);
        int ax2 = min(cast(int)(x2) + 1, b.width);
        line[ax1..ax2] = color;

        x1   += dx1;
        x2   += dx2;
        ++line;
    }
}

private auto initScTable(T, int Count)()
{
    import std.math;
    import gamelib.fixedpoint;
    T[(Count + 1) * 2] ret;
    foreach(i;0..Count + 1)
    {
        ret[i * 2 + 0] = cos(cast(T)i / cast(T)Count * cast(T)PI);
        ret[i * 2 + 1] = sin(cast(T)i / cast(T)Count * cast(T)PI);
    }
    return ret;
}

void circle(BitmapT,PtT,RadT,ColorT)(BitmapT b, in PtT center, in RadT radius, in ColorT color)
{
    enum scCount = 32;
    static immutable RadT[(scCount + 1) * 2] scTable = initScTable!(RadT, scCount)();
    assert(radius >= 0);
    b.lock();
    scope(exit) b.unlock();
    PtT[scCount * 2] pts;
    foreach(i;0..scCount)
    {
        auto tpt = PtT(scTable[i * 2], scTable[i * 2 + 1]);
        pts[i        ] = center + tpt * radius;
        pts[i+scCount] = center - tpt * radius;
    }
    poly(b, pts, color);
}

void line(BitmapT,PtT,WdthT,ColorT)(BitmapT b, in PtT pt1, in PtT pt2, in WdthT width, in ColorT color)
{
    b.lock();
    scope(exit) b.unlock();
    Unqual!PtT delta = (pt2 - pt1);
    if      (0 == delta.x) delta.y = (delta.y > 0) ? 1 : -1;
    else if (0 == delta.y) delta.x = (delta.x > 0) ? 1 : -1;
    else delta.normalize;
    auto wdelta = delta * (width / 2);
    PtT[4] pts;
    pts[0].x = pt1.x - wdelta.y;
    pts[0].y = pt1.y + wdelta.x;
    pts[1].x = pt1.x + wdelta.y;
    pts[1].y = pt1.y - wdelta.x;
    pts[2].x = pt2.x + wdelta.y;
    pts[2].y = pt2.y - wdelta.x;
    pts[3].x = pt2.x - wdelta.y;
    pts[3].y = pt2.y + wdelta.x;
    poly(b, pts, color);
    circle(b, pt1, width / 2, color);
    circle(b, pt2, width / 2, color);
}

void downsample(BitmapT)(BitmapT dst, BitmapT src)
{
    assert(0 == src.width  % dst.width);
    assert(0 == src.height % dst.height);
    dst.lock();
    scope(exit) dst.unlock();
    src.lock();
    scope(exit) src.unlock();
    auto mi = src.width  / dst.width;
    auto mj = src.height / dst.height;
    auto mcnt = mi * mj;
    alias col_t = Unqual!(typeof(src[0][0]));
    col_t[16] stackBuff;
    col_t[] cols;
    if(mcnt <= stackBuff.length)
    {
        cols = stackBuff[0..mcnt];
    }
    else
    {
        cols.length = mcnt;
    }

    foreach(y;0..dst.height)
    {
        foreach(x;0..dst.width)
        {
            int cr = 0;
            int cg = 0;
            int cb = 0;
            int ca = 0;

            foreach(j;0..mj)
            {
                foreach(i;0..mi)
                {
                    cols[i + mj * j] = src[y * mj + j][x * mi + i];
                }
            }

            foreach(i;0..mcnt)
            {
                cr += cols[i].r;
                cg += cols[i].g;
                cb += cols[i].b;
                ca += cols[i].a;
            }
            col_t resColor = {r: cast(ubyte)(cr / mcnt),
                              g: cast(ubyte)(cg / mcnt),
                              b: cast(ubyte)(cb / mcnt),
                              a: cast(ubyte)(ca / mcnt)};
            dst[y][x] = resColor;
        }
    }
}
