module game.renderer.renderer;

import std.traits;
import std.algorithm;

import gamelib.types;

//import game.units;
import game.renderer.rasterizerhp5;

struct Renderer(State, int MaxDepth)
{
private:
    State[MaxDepth] mStateStack;
    int             mCurrentState = 0;

public:
//pure nothrow:

    void pushState()
    {
        assert(mCurrentState < MaxDepth);
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
        T ret = src;
        ret.pos = getState().matrix * src.pos;
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
            rast.drawIndexedTriangle(getState(), context, verts, indices[i0..i1]);
        }
    }
}

