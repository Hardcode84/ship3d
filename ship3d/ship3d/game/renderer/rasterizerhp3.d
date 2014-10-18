module game.renderer.rasterizerhp3;

import std.traits;
import std.algorithm;
import std.array;
import std.string;
import std.functional;
import std.range;

import gamelib.util;
import gamelib.math;
import gamelib.graphics.graph;

import game.units;

@nogc:

struct RasterizerHP3(BitmapT,TextureT,DepthT = void)
{
@nogc:
private:
    BitmapT mBitmap;
    TextureT mTexture;
    enum HasDepth = !is(DepthT : void);
    static if(HasDepth)
    {
        DepthT mDepthMap;
    }
    Rect mClipRect;
    
    enum MinTileWidth  = 8;
    enum MinTileHeight = 8;
    
    struct Line(PosT,bool Affine)
    {
    @nogc:
        immutable PosT dx, dy, c;
        
        this(VT)(in VT v1, in VT v2, in VT v3, in PosT baryInvDenom) pure nothrow
        {
            const x1 = v1.pos.x;
            const x2 = v2.pos.x;
            const y1 = v1.pos.y;
            const y2 = v2.pos.y;
            const w = Affine ? cast(PosT)1 : cast(PosT)v3.pos.w;
            dx = (x2 - x1) * baryInvDenom / w;
            dy = (y2 - y1) * baryInvDenom / w;
            const inc = (dy < 0 || (dy == 0 && dx > 0)) ? cast(PosT)1 / cast(PosT)16 : cast(PosT)0;
            c = (dy * x1 - dx * y1) + inc * baryInvDenom / w;
        }
        
        auto val(int x, int y) const pure nothrow
        {
            return c + dx * y - dy * x;
        }
    }
    
    struct Plane(PosT)
    {
    @nogc:
        immutable PosT ac;
        immutable PosT bc;
        immutable PosT dc;
        this(V)(in V v1, in V v2, in V v3) pure nothrow
        {
            const v12 = v2 - v1;
            const v13 = v3 - v1;
            
            const norm = cross(v12,v13);
            //ax + by + cz = d
            ac = norm.x / norm.z;
            bc = norm.y / norm.z;
            dc = ac * v1.x + bc * v1.y + v1.z;
        }
        
        auto get(int x, int y) const pure nothrow
        {
            //z = d/c - (a/c)x - (b/c)y)
            return dc - ac * x - bc * y;
        }
    }
    
    struct LinesPack(PosT,LineT,bool Affine)
    {
    @nogc:
        alias vec3 = Vector!(PosT,3);
        alias PlaneT = Plane!(PosT);
        enum NumLines = 3;
        immutable LineT[NumLines] lines;
        
        static if(!Affine)
        {
            immutable PlaneT wplane;
        }
        this(VT)(in VT v1, in VT v2, in VT v3) pure nothrow
        {
            const invDenom = cast(PosT)(1 / ((v2.pos - v1.pos).xy.wedge((v3.pos - v1.pos).xy)));
            lines = [
                LineT(v1, v2, v3, invDenom),
                LineT(v2, v3, v1, invDenom),
                LineT(v3, v1, v2, invDenom)];
            
            static if(!Affine)
            {
                wplane = PlaneT(vec3(v1.pos.xy, cast(PosT)1 / v1.pos.w),
                                vec3(v2.pos.xy, cast(PosT)1 / v2.pos.w),
                                vec3(v3.pos.xy, cast(PosT)1 / v3.pos.w));
            }
        }
        
    }
    
    /+struct Tile(PosT,PackT,bool Affine)
    {
    @nogc:
        const(PackT)* pack;
        enum NumLines = 3;
        PosT[NumLines] cx = void, cy = void;
        static if(!Affine)
        {
            PosT currw = void;
            PosT prevw = void;
        }
        
        this(in PackT* p, int x, int y)
        {
            pack = p;
            setXY(x,y);
        }
        void setXY(int x, int y) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cy[i] = pack.lines[i].val(x, y);
                cx[i] = cy[i];
            }
            static if(!Affine)
            {
                currw = pack.wplane.get(x,y);
                prevw = currw;
            }
        }
        
        void incX(int val) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cx[i] -= pack.lines[i].dy * val;
            }
            static if(!Affine)
            {
                currw -= pack.wplane.ac * val;
            }
        }
        
        void incY(int val) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cy[i] += pack.lines[i].dx * val;
                cx[i] = cy[i];
            }
            static if(!Affine)
            {
                currw = prevw - pack.wplane.bc * val;
                prevw = currw;
            }
        }
        
        @property auto all() const pure nothrow
        {
            //return all!"a.curr > 0"(lines[]);
            return cx[0] > 0 && cx[1] > 0 && cx[2] > 0;
        }
        
        @property auto check() const pure nothrow
        {
            uint ret = 0;
            foreach(i;TupleRange!(0,NumLines))
            {
                ret |= ((cx[i] > 0) << i);
            }
            return ret;
        }
        
        void getBarycentric(int dx = 0)(PosT[] ret) const pure nothrow
            in
        {
            assert(ret.length == NumLines);
        }
        out
        {
            //assert(almost_equal(cast(PosT)1, ret.sum, 1.0f/255.0f), debugConv(ret.sum));
        }
        body
        {
            foreach(i;TupleRange!(1,NumLines))
            {
                enum li = (i + 1) % NumLines;
                auto val = cx[li] - pack.lines[li].dy * dx;
                static if(!Affine)
                {
                    val /= (currw - pack.wplane.ac * dx);
                }
                ret[i] = val;
            }
            ret[0] = cast(PosT)1 - ret[1] - ret[2];
        }
    }+/
    struct Tile(int TileWidth, int TileHeight, PosT,PackT,bool Affine)
    {
        immutable(PackT)* pack;
        enum NumLines = 3;
        int currx = void;
        int curry = void;
        PosT[NumLines] cx0 = void, cx1 = void;
        static if(!Affine)
        {
            PosT currw0 = void, currw1 = void;
        }

        this(in immutable(PackT)* p, int x, int y) pure nothrow
        {
            pack = p;
            setXY(x,y);
        }

        void setXY(int x, int y) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                const val = pack.lines[i].val(x, y);
                cx0[i] = val;
                cx1[i] = val + pack.lines[i].dx * TileHeight;
            }
            static if(!Affine)
            {
                currw0 = pack.wplane.get(x,y);
                currw1 = currw0 - pack.wplane.bc * TileHeight;
            }
            currx = x;
            curry = y;
        }

        void incX(string sign)() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                const dx = pack.lines[i].dy * -TileWidth;
                mixin("cx0[i] "~sign~"= dx;");
                mixin("cx1[i] "~sign~"= dx;");
            }
            static if(!Affine)
            {
                const dw = pack.wplane.ac * -TileWidth;
                mixin("currw0 "~sign~"= dw;");
                mixin("currw1 "~sign~"= dw;");
            }
            mixin("currx"~sign~"= TileWidth;");
        }
        
        void incY() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cx0[i] = cx1[i];
                cx1[i] += pack.lines[i].dx * TileHeight;
            }
            static if(!Affine)
            {
                currw0 = currw1;
                currw1 -= pack.wplane.bc * TileHeight;
            }
            curry += TileHeight;
        }
        @property auto check() const pure nothrow
        {
            uint ret = 0;
            foreach(j;TupleRange!(0,2))
            {
                foreach(i;TupleRange!(0,NumLines))
                {
                    import std.conv;
                    mixin("ret |= ((cx"~text(j)~"[i] > 0) << (i+"~text(NumLines * j)~"));");
                }
            }
            return ret;
        }
    }

    struct Point(PosT,PackT,bool Affine)
    {
        immutable(PackT)* pack;
        enum NumLines = 3;
        int currx = void;
        int curry = void;
        PosT[NumLines] cx = void;
        this(TileT)(in ref TileT tile, int x, int y) pure nothrow
        {
            pack = tile.pack;
            foreach(i;TupleRange!(0,NumLines))
            {
                const val = pack.lines[i].val(x, y);
                cx[i] = val;
            }
            currx = x;
            curry = y;
        }

        void incX(string sign)() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                const dx = -pack.lines[i].dy;
                mixin("cx[i] "~sign~"= dx;");
            }
            mixin("currx"~sign~"= 1;");
        }
        
        void incY() pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                cx[i] += pack.lines[i].dx;
            }
            curry += 1;
        }

        bool check() const pure nothrow
        {
            return cx[0] > 0 && cx[1] > 0 && cx[2] > 0;
        }
    }
    
    struct Span(PosT,ColT,DpthT)
    {
        enum HasColor = !is(ColT : void);
        enum HasDepth = !is(DpthT : void);
        int x0 = void, x1 = void;
        int y = void;
        static if(HasColor)
        {
            ColT col0 = void, col1 = void;
        }
        static if(HasDepth)
        {
            DpthT w0 = void, w1 = void;
        }
    }
public:
    this(BitmapT b)
        in
    {
        assert(b !is null);
        assert(0 == (b.width  % MinTileWidth));
        assert(0 == (b.height % MinTileHeight));
        static if(HasDepth)
        {
            assert(mDepthMap !is null);
        }
    }
    body
    {
        mBitmap = b;
        mClipRect = Rect(0, 0, mBitmap.width, mBitmap.height);
    }
    
    static if(HasDepth)
    {
        this(BitmapT b, DepthT d)
            in
        {
            assert(d ! is null);
            assert(b.width  == d.width);
            assert(b.height == d.height);
        }
        body
        {
            mDepthMap = d;
            this(b);
        }
    }
    
    @property auto texture()       inout pure nothrow { return mTexture; }
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
    
    void drawIndexedTriangle(bool HasTextures = false, bool HasColor = true,VertT,IndT)(in VertT[] verts, in IndT[3] indices) pure nothrow if(isIntegral!IndT)
    {
        const c = (verts[1].pos.xyz - verts[0].pos.xyz).cross(verts[2].pos.xyz - verts[0].pos.xyz);
        if(c.z <= 0)
        {
            return;
        }
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        
        const e1xdiff = pverts[0].pos.x - pverts[2].pos.x;
        const e2xdiff = pverts[0].pos.x - pverts[1].pos.x;
        
        const e1ydiff = pverts[0].pos.y - pverts[2].pos.y;
        const e2ydiff = pverts[0].pos.y - pverts[1].pos.y;
        
        const cxdiff = ((e1xdiff / e1ydiff) * e2ydiff) - e2xdiff;
        const reverseSpans = (cxdiff < 0);
        const affine = false;//(abs(cxdiff) > AffineLength * 25);
        
        if(affine) drawTriangle!(HasTextures, HasColor,true)(pverts);
        else       drawTriangle!(HasTextures, HasColor,false)(pverts);
    }
    @nogc private void drawTriangle(bool HasTextures, bool HasColor,bool Affine,VertT)(in VertT[3] pverts) pure nothrow
    {
        static assert(HasTextures != HasColor);
        //alias PosTF = FixedPoint!(16,16,int);
        alias PosT = Unqual!(typeof(VertT.pos.x));
        static if(HasColor)
        {
            alias ColT = Unqual!(typeof(VertT.color));
            immutable ColT vcols[3] = [pverts[0].color,pverts[1].color,pverts[2].color];
            auto calcColor(T)(in T[] bary) pure nothrow
            in
            {
                assert(bary.length == vcols.length);
            }
            body
            {
                return vcols[0] * bary[0] + vcols[1] * bary[1] + vcols[2] * bary[2];
            }
        }
        else
        {
            alias ColT = void;
        }
        alias LineT   = Line!(PosT,Affine);
        alias PackT   = LinesPack!(PosT,LineT,Affine);
        alias TileT   = Tile!(MinTileWidth,MinTileHeight,PosT,PackT,Affine);
        alias PointT  = Point!(PosT,PackT,Affine);
        alias SpanT   = Span!(PosT,ColT,PosT);
        
        int minY = cast(int)min(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        int maxY = cast(int)max(pverts[0].pos.y, pverts[1].pos.y, pverts[2].pos.y);
        
        int minX = cast(int)min(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        int maxX = cast(int)max(pverts[0].pos.x, pverts[1].pos.x, pverts[2].pos.x);
        minX = max(mClipRect.x, minX);
        maxX = min(mClipRect.x + mClipRect.w, maxX);
        minY = max(mClipRect.y, minY);
        maxY = min(mClipRect.y + mClipRect.h, maxY);
        //immutable upperVert = reduce!((a,b) => a.pos.y < b.pos.y ? a : b)(pverts);
        const upperVert = (pverts[0].pos.y < pverts[1].pos.y ? 
                          (pverts[0].pos.y < pverts[2].pos.y ? pverts[0] : pverts[2]) :
                          (pverts[1].pos.y < pverts[2].pos.y ? pverts[1] : pverts[2]));
        @nogc void drawSpan(LineT,SpanT)(auto ref LineT line, in ref SpanT span) pure nothrow
        {
            static if(HasColor)
            {
                ditherColorLine(line,span.x0,span.x1,span.y,span.col0,span.col1);
            }
        }

        @nogc void fillTile(T)(in ref T tile, int x0, int y0, int x1, int y1)
        {
            auto line = mBitmap[y0];
            foreach(y;y0..y1)
            {
                line[x0..x1] = ColorRed;
                ++line;
            }
        }
        @nogc void drawTile(bool Left, T)(in ref T tile, int x0, int y0, int x1, int y1, int sx, int sy)
        {
            debugOut("draw");
            debugOut(x0);
            debugOut(y0);
            debugOut("---");
            debugOut(sx);
            debugOut(sy);
            assert(sx >= x0);
            assert(sx < x1);
            assert(sy >= y0);
            assert(sy < y1);
            auto pt = PointT(tile, sx, sy);
            //auto ptRight = pt;
            //auto ptDown  = pt;
            /*foreach(y;sy..y1)
            {
                foreach(x;sx..x1)
                {
                }
                sx = x0;
            }*/
            debugOut("-------");
            while(!pt.check())
            {
                if(pt.curry >= y1) return;
                pt.incY();
                //debugOut("inc");
            }
            debugOut(x0);
            //debugOut(sx);
            sy = pt.curry;
            SpanT[MinTileHeight] spans = void;
            int ey = sy;
            while(ey < y1)
            {
                bool hasDown = false;
                auto ptRight = pt;
                PointT ptDown = void;
                ptRight.incX!"+"();
                const my = ey % MinTileHeight;
                spans[my].y = ey;
                foreach(i;TupleRange!(0,2))
                {
                    static if(1 == i)
                    {
                        pt = ptRight;
                    }
                    //debugOut(pt.currx);
                    ptDown = pt;
                    ptDown.incY();
                    enum sign = (i == 0 ? "-" : "+");
                    while(true)
                    {
                        //debugOut(pt.currx);
                        if(pt.currx <= x0) 
                        {
                            //debugOut("->lbrk<-");
                            break;
                        }
                        if(pt.currx >= x1)
                        {
                            //debugOut("->rbrk<-");
                            break;
                        }
                        if(!hasDown)
                        {
                            if(ptDown.check())
                            {
                                //debugOut("save down");
                                hasDown = true;
                            }
                            else
                            {
                                ptDown.incX!(sign)();
                            }
                        }
                        if(!pt.check())
                        {
                            //debugOut("->cbrk<-");
                            break;
                        }
                        //debugOut("iter");
                        pt.incX!(sign)();
                    }
                    import std.conv;
                    mixin("spans[my].x"~text(i)~"= pt.currx;");
                    //debugOut(pt.currx);
                    //spans[ey].x0 = pt.currx;
                }
                if(!hasDown || ey >= y1)
                {
                    break;
                }

                //debugOut(spans[my].x0);
                //debugOut(spans[my].x1);
                ++ey;
                pt = ptDown;
            }

            auto line = mBitmap[sy];
            /*debugOut("---");
            debugOut(y0);
            debugOut(sy);
            debugOut(ey);*/
            debugOut(x0);
            foreach(y;sy..ey)
            {
                const my = y % MinTileHeight;
                debugOut("-");
                debugOut(spans[my].x0);
                debugOut(spans[my].x1);
                assert(spans[my].x0 >= x0);
                assert(spans[my].x1 <= x1);
                static if(Left)
                {
                    if(spans[my].x0 == x0)
                    {
                        debugOut("left");
                        //sy = y;
                    }
                }
                else
                {
                    if(spans[my].x1 == x1)
                    {
                        debugOut("right");
                        //sy = y;
                    }
                }
                line[spans[my].x0..spans[my].x1] = ColorGreen;
                //line[x0..x1]  = ColorGreen;
                ++line;
            }

            /+foreach(y;y0..y1)
            {
                //line[x0..x1] = ColorGreen;
                auto pt = PointT(tile, x0, y);
                foreach(x;x0..x1)
                {
                    /+if(pt.check())
                    {
                        line[x] = ColorGreen;
                    }+/
                    line[x] = pt.check() ? ColorGreen : ColorBlue;
                    pt.incX!"+"();
                }
                pt.incY();
                ++line;
            }+/
        }

        immutable pack = PackT(pverts[0], pverts[1], pverts[2]);
        int sx = cast(int)upperVert.pos.x;
        int sy = cast(int)upperVert.pos.y;
        const tx = sx / MinTileWidth;
        const ty = sy / MinTileHeight;
        TileT currentTile    = TileT(&pack, tx * MinTileWidth, ty * MinTileHeight);
        TileT savedRightTile;
        TileT savedDownTile;
        //debugOut("-----");
        while(true)
        {
            bool savedDown = false;
            auto none(in uint val) pure nothrow
            {
                return 0x0 == (val & 0b001_001_001_001) ||
                       0x0 == (val & 0b010_010_010_010) ||
                       0x0 == (val & 0b100_100_100_100);
            }
            auto all(in uint val) pure nothrow
            {
                return val == 0b111_111_111_111;
            }
            auto down(in uint val) pure nothrow
            {
                //return 0x0 != (val & 0b111_000_111_000);
                return 0x0 != (val & 0b001_000_001_000) &&
                       0x0 != (val & 0b010_000_010_000) &&
                       0x0 != (val & 0b100_000_100_000);
            }
            uint tileMask = (currentTile.check() << 6);
            savedRightTile = currentTile;

            const y0 = currentTile.curry;
            const y1 = y0 + MinTileHeight;
            //drawTile(currentTile, currentTile.currx, y0, currentTile.currx + MinTileWidth, y1);

            //move left
            while(true)
            {
                //debugOut("left iter");
                currentTile.incX!("-")();
                tileMask >>= 6;
                tileMask |= (currentTile.check() << 6);
                if(!savedDown && down(tileMask))
                {
                    savedDownTile = currentTile;
                    savedDown = true;
                }
                if(none(tileMask))
                {
                    break;
                }
                const x0 = currentTile.currx;
                const x1 = x0 + MinTileWidth;

                sx = x1 - 1;
                sy = y0;
                if(all(tileMask))
                {
                    fillTile(currentTile, x0, y0, x1, y1);
                }
                else
                {
                    drawTile!true(currentTile, x0, y0, x1, y1, sx, sy);
                }
                sx = x0 - 1;
                sy = y0;
            }

            //move right
            tileMask = (savedRightTile.check() << 6);
            while(true)
            {
                //debugOut("right iter");
                const x0 = savedRightTile.currx;
                const x1 = x0 + MinTileWidth;
                savedRightTile.incX!("+")();
                tileMask >>= 6;
                tileMask |= (savedRightTile.check() << 6);
                if(!savedDown && down(tileMask))
                {
                    savedDownTile = savedRightTile;
                    savedDown = true;
                }
                if(none(tileMask))
                {
                    break;
                }
                
                sx = x0;
                sy = y0;
                if(all(tileMask))
                {
                    fillTile(savedRightTile, x0, y0, x1, y1);
                    //sy = y0;
                }
                else
                {
                    drawTile!false(savedRightTile, x0, y0, x1, y1, sx, sy);
                }
                //sx = x0;
                //sy = y0;
            }

            if(!savedDown)
            {
                break;
            }
            currentTile = savedDownTile;
            currentTile.incY();
            sy += MinTileHeight;
        }
        //TileT current;
        //end
    }
}