module gamelib.graphics.surfaceview;

struct SurfaceView(ElemT)
{
private:
    immutable int    mWidth;
    immutable int    mHeight;
    immutable size_t mPitch;
    void* mData;
public:
    this(T)(auto ref T surf)
    {
        assert(surf.isLocked);
        mWidth  = surf.width;
        mHeight = surf.height;
        mPitch  = surf.pitch;
        mData   = surf.data;
    }

    auto opIndex(int y) pure nothrow
    {
        //assert(y >= 0 && y < height);
        struct Line
        {
        private:
            debug
            {
                int width;
                int height;
                int y;
            }
            size_t pitch;
            ElemT* data;
            
            void checkCoord(int x) const pure nothrow
            {
                assert(x >= 0);
                debug
                {
                    assert(x < width);
                    assert(y >= 0);
                    assert(y < height);
                }
            }
        public:
            
            auto opIndex(int x) const pure nothrow
            {
                checkCoord(x);
                return data[x];
            }
            
            auto opIndexAssign(in ElemT value, int x) pure nothrow
            {
                checkCoord(x);
                return data[x] = value;
            }
            
            auto opSlice(int x1, int x2) inout pure nothrow
            {
                checkCoord(x1);
                assert(x2 >= x1);
                debug assert(x2 <= width);
                return data[x1..x2];
            }
            
            auto opSliceAssign(T)(in T val, int x1, int x2) pure nothrow
            {
                checkCoord(x1);
                assert(x2 >= x1);
                debug assert(x2 <= width);
                return data[x1..x2] = val;
            }
            
            ref auto opUnary(string op)() pure nothrow if(op == "++" || op == "--")
            {
                mixin("data = cast(ElemT*)(cast(byte*)data"~op[0]~" pitch);");
                debug
                {
                    mixin("y"~op~";");
                }
                return this;
            }
        }

        assert(mData);
        Line ret = {pitch: mPitch, data: cast(ElemT*)(mData + mPitch * y) };
        debug
        {
            ret.width = mWidth;
            ret.height = mHeight;
            ret.y = y;
        }
        return ret;
    }
}

