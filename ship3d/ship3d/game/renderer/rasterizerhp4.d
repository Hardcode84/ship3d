module game.renderer.rasterizerhp4;

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

struct RasterizerHP4(BitmapT,TextureT,DepthT = void)
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
    
    enum TileWidth   = 8;
    enum TileHeight  = 8;
    enum MetaTileWidth  = 32;
    enum MetaTileHeight = 3;
    
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

    struct MetaTile(int TileWidth, int TileHeight, PosT,PackT)
    {
        immutable(PackT)* pack;
        enum NumLines  = 3;
        enum NumVTiles = MetaTileHeight;
        enum ArrHeight = NumVTiles + 1;
        int currx = void;
        int curry = void;
        alias LineData = PosT[NumLines];
        LineData[ArrHeight] cx = void;
        immutable PosT[NumLines] dx;

        uint mask = void;

        this(in immutable(PackT)* p, int x, int y) pure nothrow
        {
            pack = p;
            foreach(i;TupleRange!(0,NumLines))
            {
                dx[i] = pack.lines[i].dy * -TileWidth;
            }
            setXY(x,y);
        }

        void setXY(int x, int y) pure nothrow
        {
            foreach(i;TupleRange!(0,NumLines))
            {
                const val = pack.lines[i].val(x, y);
                foreach(j;TupleRange!(0,ArrHeight))
                {
                    cx[j][i] = val + pack.lines[i].dx * (TileHeight * j);
                }
            }
            currx = x;
            curry = y;
            mask = (check() << (NumLines * ArrHeight));
        }

        void incX() pure nothrow
        {
            foreach(j;TupleRange!(0,ArrHeight))
            {
                foreach(i;TupleRange!(0,NumLines))
                {
                    cx[j][i] += dx[i];
                }
            }
            currx += TileWidth;
            mask >>= (NumLines * ArrHeight);
            mask = (check() << (NumLines * ArrHeight));
        }

        @property auto check() const pure nothrow
        {
            uint ret = 0;
            foreach(j;TupleRange!(0,ArrHeight))
            {
                foreach(i;TupleRange!(0,NumLines))
                {
                    ret |= ((cx[j][i] > 0) << (i + NumLines * j));
                }
            }
            return ret;
        }

        bool none(int i)() const pure nothrow
        {
            static assert(i > 0);
            static assert(i < NumVTiles);
            const val = mask >> (i * NumLines);
            return 0x0 == (val & 0b001_001_000_000_001_001) ||
                   0x0 == (val & 0b010_010_000_000_010_010) ||
                   0x0 == (val & 0b100_100_000_000_100_100);
        }
        bool all(int i)() const pure nothrow
        {
            static assert(i > 0);
            static assert(i < NumVTiles);
            const val = mask >> (i * NumLines);
            return val & 0b111_111_000_000_111_111;
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
        assert(0 == (b.width  % TileWidth));
        assert(0 == (b.height % TileHeight));
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
        alias MTileT  = MetaTile!(TileWidth,TileHeight,PosT,PackT);
        //alias TileT   = Tile!(MinTileWidth,MinTileHeight,PosT,PackT,Affine);
        //alias PointT  = Point!(PosT,PackT,Affine);
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
            auto line = mBitmap[y0];
            foreach(y;y0..y1)
            {
                line[x0..x1] = ColorGreen;
                ++line;
            }
        }

        immutable pack = PackT(pverts[0], pverts[1], pverts[2]);
        const sx = cast(int)upperVert.pos.x;
        const sy = cast(int)upperVert.pos.y;
        const tx = sx / TileWidth;
        const ty = sy / TileHeight;
        const tx0 = minX / TileWidth;
        const tx1 = maxX / TileWidth + 1;
        const ty0 = minY / TileHeight;
        const ty1 = maxY / TileHeight + 1;
        const mtx0 = tx0 / MetaTileWidth;
        const mtx1 = tx1 / MetaTileWidth + 1;
        const mty0 = ty0 / MetaTileHeight;
        const mty1 = ty1 / MetaTileHeight + 1;
        foreach(mty;mty0..mty1)
        {
            foreach(mtx;mtx0..mtx1)
            {
                auto mtile = MTileT(&pack, mtx * MetaTileWidth * TileWidth, mty * MetaTileHeight * TileHeight);

                uint[MetaTileHeight] masksFill = 0;
                uint[MetaTileHeight] masksDraw = 0;
                foreach(i;0..MetaTileWidth)
                {
                    mtile.incX();
                    foreach(j;TupleRange(0,MetaTileHeight))
                    {
                        masksFill[j] = (mtile.all!(j)() << i);
                        masksDraw[j] = (!mtile.none!(j)() << i);
                    }
                }

                foreach(ty;0..MetaTileHeight)
                {
                    int drawStart;
                    int drawEnd;
                    int fillStart;
                    int fillEnd;
                }
            }
        }

        //end
    }
}