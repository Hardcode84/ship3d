module gamelib.graphics.renderer2d.textureview;

import gamelib.types;
import gamelib.graphics.renderer2d.texture;

final class TextureView
{
    private Texture mTexture;
    private Rect mRect;

    this(Texture tex, in Rect rc = Rect(-1, -1, -1, -1))
    {
        assert(tex !is null);
        if(rc.w < 0)
        {
            auto props = tex.props();
            mRect = Rect(0, 0, props.width, props.height);
        }
        else
        {
            mRect = rc;
        }
        mTexture = tex;
    }

    @property auto rect()    const pure nothrow { return mRect; }
    @property auto width()   const pure nothrow { return mRect.w; }
    @property auto height()  const pure nothrow { return mRect.h; }

    @property auto texture() pure nothrow { return mTexture; }
}

