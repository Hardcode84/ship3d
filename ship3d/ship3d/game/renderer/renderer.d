module game.renderer.renderer;

import std.traits;
import std.algorithm;

import gamelib.types;

//import game.units;
import game.renderer.rasterizerhp5;

struct Renderer(State)
{
private:
    State[]         mStateStack = [State()];
    int             mCurrentState = 0;
    Size            mViewport;

    enum                VertexCacheSize = 512; //in bytes
    void[]              mCachedVertices;
    static assert(VertexCacheSize % uint.sizeof == 0);
    enum                BitArraySize = VertexCacheSize / uint.sizeof;
    uint[BitArraySize]  mCacheBitArray;

    bool isCached(T1, T2)(in ref T1 vert, in T2 ind) const pure nothrow
    {
        static assert(isIntegral!T2);
        assert(ind < (VertexCacheSize / T1.sizeof));
        return 0x0 != (mCacheBitArray[ind / 32] & (1u << (ind % 32)));
    }
    auto transformVertex(T)(in ref T src) const pure nothrow
    {
        const pos = getState().matrix * src.pos;
        const w = pos.w;
        T ret = src;
        ret.pos.x = (pos.x / w) * mViewport.w + mViewport.w / 2;
        ret.pos.y = (pos.y / w) * mViewport.h + mViewport.h / 2;
        return ret;
    }

public:
    /*this(auto ref BitmapT surf) pure nothrow
    {
        // Constructor code
        mBitmap = surf;
    }*/

    @property viewport() const pure nothrow { return mViewport; }
    @property viewport(in Size rc) pure nothrow { mViewport = rc; }

    void pushState() pure nothrow
    {
        if(mCurrentState >= (mStateStack.length))
        {
            mStateStack.length = max(mStateStack.length * 2, 1);
        }

        ++mCurrentState;
        mStateStack[mCurrentState] = mStateStack[mCurrentState - 1];
    }

    void popState() pure nothrow
    {
        assert(mCurrentState > 0);
        --mCurrentState;
    }

    inout auto ref getState() inout pure nothrow
    {
        assert(mCurrentState >= 0);
        assert(mCurrentState < mStateStack.length);
        return mStateStack[mCurrentState];
    }

    void resetVertexCache() pure nothrow
    {
        mCacheBitArray[] = 0;
    }

    void drawIndexedTriangle(RasterizerT,CtxT,VertexT,IndexT)(in auto ref CtxT context, in VertexT[] verts, in IndexT[] indices)
    {
        static assert(isIntegral!IndexT);
        assert(indices.length % 3 == 0);
        assert(verts.length < (VertexCacheSize / VertexT.sizeof));
        auto transformedVerts = cast(VertexT[])(mCachedVertices[]);
        RasterizerT rast;
        foreach(i;0..indices.length / 3)
        {
            const i0 = i * 3;
            const i1 = i0 + 3;
            foreach(j;i0..i1)
            {
                if(!isCached(verts[j], j))
                {
                    transformedVerts[j] = transformVertex(verts[j]);
                }
            }
            rast.drawIndexedTriangle!(true)(getState(), context, transformedVerts, indices[i0..i1]);
        }
    }
}

