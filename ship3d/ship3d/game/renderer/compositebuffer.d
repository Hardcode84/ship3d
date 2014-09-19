module game.renderer.compositebuffer;

final class CompositeBuffer(ColBuffT,DepthBuffT)
{
private:
    ColBuffT   mColorBuff;
    DepthBuffT mDepthBuff;
public:
    this(int w, int h)
    {
        mColorBuff = new ColBuffT(w,h);
        mDepthBuff = new DepthBuffT(w,h);
    }

    final auto opIndex(int y) pure nothrow
    {
        alias CViewT = typeof(mColorBuff[y]);
        alias DViewT = typeof(mDepthBuff[y]);
        //import gamelib.graphics.surfaceview;
        //SurfaceView!ColorT view = mColorBuff;
        struct
        {
            CViewT cview;
            DViewT dview;
            alias cview this;

        } view_t;
        view_t view = {cview:mColorBuff[y], dview:mDepthBuff[y]};
        return view[y];
    }
}

