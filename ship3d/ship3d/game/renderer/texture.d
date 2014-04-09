module game.renderer.texture;

final class Texture(ColT)
{
private:
    ColT[] mData;
    immutable int mWidth;
    immutable int mHeight;
    immutable size_t mPitch;
public:
    this(int w, int h)
    {
        assert(w > 0);
        assert(h > 0);
        mWidth = w;
        mHeight = h;
        mPitch = w;
        mData.length = mPitch * mHeight;
    }
}

