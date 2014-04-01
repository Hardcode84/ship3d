module gamelib.graphics.renderer2d.font;

import std.traits;
import std.range;

import gamelib.types;
import gamelib.graphics.renderer2d.renderer;
import gamelib.graphics.renderer2d.texture;

package struct GlyphData
{
    dchar ch;
    Rect dstRect;
    Rect srcRect;
    int textureIndex;
}

abstract class BaseFont
{
private:
    immutable int mHeight;
    immutable int mNLHeight;
    GlyphData[dchar] mGlyphs;
    Texture[] mTextures;

    dchar[] mCharBuffer;

    auto getGlyph(dchar ch) const pure nothrow
    {
        return (ch in mGlyphs);
    }

    final void outTextInternal(S)(Renderer ren, in Point pos, in S str, in Color col)
        if(is(S : dstring) || is(S : dchar[]))
    {
        assert(mTextures.length > 0);
        foreach(t;mTextures)
        {
            t.colorMod = col;
        }

        int cx = pos.x;
        int cy = pos.y;
        foreach(ch;str)
        {
            if('\n' == ch)
            {
                cx = pos.x;
                cy += mNLHeight;
            }
            else
            {
                auto glyph = getGlyph(ch);
                assert(glyph !is null);
                assert(glyph.ch == ch);

                Rect dstRect = glyph.srcRect;
                dstRect.x = cx - glyph.dstRect.x;
                dstRect.y = cy - glyph.dstRect.y - glyph.dstRect.h;
                ren.draw(mTextures[glyph.textureIndex], &glyph.srcRect, &dstRect);
                cx += glyph.dstRect.w;
            }
        }
    }

public:
    this(int height, in GlyphData[] glyphs, Texture[] textures)
    {
        assert(glyphs.length > 0);
        assert(textures.length > 0);
        mCharBuffer.length = 64;
        mHeight = height;
        mNLHeight = mHeight + mHeight / 2;
        foreach(g;glyphs)
        {
            mGlyphs[g.ch] = g;
        }
        mTextures = textures.dup;
    }

    final void dispose() nothrow
    {
        foreach(t;mTextures)
        {
            t.dispose();
        }
        mTextures.length = 0;
    }

    enum
    {
        VALIGN_TOP    = 1 << 0,
        VALIGN_CENTER = 1 << 1,
        VALIGN_BOTTOM = 1 << 2,
        HALIGN_LEFT   = 1 << 3,
        HALIGN_CENTER = 1 << 4,
        HALIGN_RIGHT  = 1 << 6,
        ALIGN_DEFAULT = VALIGN_TOP | HALIGN_LEFT,
        ALIGN_CENTER  = VALIGN_CENTER | HALIGN_CENTER
    }

    final outText(S)(Renderer ren, in Rect rc, S str, uint flags = ALIGN_DEFAULT, in Color col = ColorWhite)
        if(is(S : string) || is(S : char[]) || is(S : wstring) || is(S : wchar[]))
    {
        import gamelib.math: uppow2;
        if(str.length > mCharBuffer.length) mCharBuffer.length = uppow2(str.length);
        size_t index = 0;
        size_t buffIndex = 0;
        while(index < str.length)
        {
            import std.utf: decode;
            mCharBuffer[buffIndex++] = decode(str, index);
        }
        outText(ren, rc, mCharBuffer[0..buffIndex], flags, col);
    }

    final outText(S)(Renderer ren, in Rect rc, S str, uint flags = ALIGN_DEFAULT, in Color col = ColorWhite)
        if(is(S : dstring) || is(S : dchar[]))
    {
        int hght = mHeight;
        int wdth = 0;
        int tempWdth = 0;
        foreach(ch;str)
        {
            if('\n' == ch)
            {
                wdth = max(wdth, tempWdth);
                tempWdth = 0;
                hght += mNLHeight;
            }
            else
            {
                auto glyph = getGlyph(ch);
                assert(glyph !is null);
                tempWdth += glyph.dstRect.w;
            }
        }
        wdth = max(wdth, tempWdth);

        Point pos;
        if(flags & HALIGN_LEFT)
        {
            pos.x = rc.x;
        }
        else if(flags & HALIGN_CENTER)
        {
            pos.x = rc.x + (rc.w - wdth) / 2;
        }
        else if(flags & HALIGN_RIGHT)
        {
            pos.x = rc.x + (rc.w - wdth);
        }
        else assert(false, "Horizontal align not specified");

        if(flags & VALIGN_TOP)
        {
            pos.y = rc.y + mHeight;
        }
        else if(flags & VALIGN_CENTER)
        {
            pos.y = rc.y + (rc.h - hght) / 2;
        }
        else if(flags & VALIGN_BOTTOM)
        {
            pos.y = rc.y + rc.h - hght;
        }
        else assert(false, "Vertical align not specified");

        outTextInternal(ren, pos, str, col);
    }
}

