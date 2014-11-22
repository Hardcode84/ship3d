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

public:
    /*this(auto ref BitmapT surf) pure nothrow
    {
        // Constructor code
        mBitmap = surf;
    }*/
    pure nothrow:

    @property viewport() const { return mViewport; }
    @property viewport(in Size rc)  { mViewport = rc; }

    void pushState()
    {
        if(mCurrentState >= (mStateStack.length))
        {
            mStateStack.length = max(mStateStack.length * 2, 1);
        }

        ++mCurrentState;
        mStateStack[mCurrentState] = mStateStack[mCurrentState - 1];
    }

    void popState()
    {
        assert(mCurrentState > 0);
        --mCurrentState;
    }

    auto ref getState() inout
    {
        assert(mCurrentState >= 0);
        assert(mCurrentState < mStateStack.length);
        return mStateStack[mCurrentState];
    }

    auto transformVertex(T)(in ref T src) const
    {
        const pos = getState().matrix * src.pos;
        const w = pos.w;
        T ret = src;
        ret.pos.x = (pos.x / w) * mViewport.w + mViewport.w / 2;
        ret.pos.y = (pos.y / w) * mViewport.h + mViewport.h / 2;
        return ret;
    }

    void drawIndexedTriangle(RasterizerT,CtxT,VertexT,IndexT)(in auto ref CtxT context, in VertexT[] verts, in IndexT[] indices)
    {
        //debugOut("Renderer.drawIndexedTriangle");
        static assert(isIntegral!IndexT);
        assert(indices.length % 3 == 0);
        RasterizerT rast;
        foreach(i;0..indices.length / 3)
        {
            const i0 = i * 3;
            const i1 = i0 + 3;
            rast.drawIndexedTriangle!(true)(getState(), context, verts, indices[i0..i1]);
        }
    }
}

