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
    Rect          mViewport;
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
    }

    void popMatrix() pure nothrow
    {
        assert(mCurrentMatrix > 0);
        --mCurrentMatrix;
    }

    auto ref getMatrix() const pure nothrow
    {
        return mMatrixStack[mCurrentMatrix];
    }

    auto transformVertex(T)(in ref T src) const pure nothrow
    {
        /*verts[i].pos = t * verts[i].pos;
        const w = verts[i].pos.w;
        verts[i].pos = verts[i].pos / w;
        verts[i].pos.w = w;
        verts[i].pos.x = verts[i].pos.x * mSize.w + mSize.w / 2;
        verts[i].pos.y = verts[i].pos.y * mSize.h + mSize.h / 2;*/
        const pos = getMatrix() * src.pos;
        const w = pos.w;
        T ret = src;
        ret.pos.
    }
}

