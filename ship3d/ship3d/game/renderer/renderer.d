module game.renderer.renderer;

import game.units;
import game.renderer.rasterizerhp5;

class Renderer(BitmapT,TextureT)
{
private:
    alias RastT = RasterizerHP5!(BitmapT,TextureT);
    RastT         mRasterizer;
    mat4_t[]      mMatrixStack = [mat4_t];
    int           mCurrentMatrix = 0;
    Size          mViewport;

    enum                VertexCacheSize = 512; //in bytes
    void[]              mCachedVertices;
    static assert(VertexCacheSize % uint.sizeof == 0);
    enum                BitArraySize = VertexCacheSize / uint.sizeof;
    uint[BitArraySize]  mCacheBitArray;

    void resetVertexCache() pure nothrow
    {
        mCacheBitArray = 0;
    }

public:
    this(auto ref BitmapT surf) pure nothrow
    {
        // Constructor code
        mRasterizer = surf;
    }

    void setMatrix(in ref mat4_t m) pure nothrow
    {
        assert(mCurrentMatrix >= 0);
        assert(mCurrentMatrix < mMatrixStack.lenght);
        mMatrixStack[mCurrentMatrix] = m;
    }

    void pushMatrix(in ref mat4_t m) pure nothrow
    {
        if(mCurrentMatrix >= (mMatrixStack.length))
        {
            mMatrixStack.length = max(mMatrixStack.length * 2, 1);
        }
        ++mCurrentMatrix;
        mMatrixStack[mCurrentMatrix] = m;
        resetVertexCache();
    }

    void popMatrix() pure nothrow
    {
        assert(mCurrentMatrix > 0);
        --mCurrentMatrix;
        resetVertexCache();
    }

    auto ref getMatrix() const pure nothrow
    {
        return mMatrixStack[mCurrentMatrix];
    }

    auto transformVertex(T)(in ref T src) const pure nothrow
    {
        const pos = getMatrix() * src.pos;
        const w = pos.w;
        T ret = src;
        ret.pos.x = (pos.x / w) * mViewport.w + mViewport.w / 2;
        ret.pos.y = (pos.y / w) * mViewport.h + mViewport.h / 2;
        return ret;
    }
}

