module gamelib.graphics.renderer2d.vectorfont;

import std.math;

import gamelib.types;
import gamelib.linalg: Vector;

import gamelib.graphics.graph;

import gamelib.graphics.renderer2d.font;
import gamelib.graphics.renderer2d.renderer;
import gamelib.graphics.surface;
import gamelib.graphics.renderer2d.texture;

final class VectorFont : BaseFont
{
public:
    import gamelib.fixedpoint;
    private alias ST = float;//FixedPoint!(16,16,int);
    this(OT,DT)(Renderer ren, int fontHeight, in OT[] desc, in DT[] data, ST scale = 1, ST width = 1)
    {
        immutable surfSize = 256;

        size_t texIndex = 0;
        size_t glyphIndex = 0;
        FFSurface!(Color)[] surfaces;
        scope(exit)
        {
            foreach(s;surfaces) s.dispose();
        }

        GlyphData[] glyphs;

        auto surf = new FFSurface!(Color)(surfSize,surfSize);
        scope(exit) surf.dispose();
        while(glyphIndex < desc.length)
        {
            auto lscale = scale;
            auto lwidth = width;
            immutable surfBorder = 16;
            surf.fill(ColorTransparentWhite);
            alias T = Vector!(ST,2);
            auto pto = T(cast(ST)0,cast(ST)0);
            ST maxHeight = 0;

            foreach(g;desc[glyphIndex..$])
            {
                int aasteps = 4;
                int aadiv = 2;
                auto brdr = lwidth + aasteps / aadiv;
                auto wdth = cast(int)(g.width  * lscale) + cast(int)(lscale * brdr * 2);
                auto hght = cast(int)(g.height * lscale) + cast(int)(lscale * brdr * 2);
                if((pto.x + wdth) >= (surfSize - surfBorder))
                {
                    pto.y += maxHeight;
                    if((pto.y + hght) >= (surfSize - surfBorder))
                    {
                        ++texIndex;
                        break;
                    }
                    pto.x = 0;
                    maxHeight = 0;
                }
                import std.algorithm: max;
                maxHeight = max(maxHeight, cast(ST)hght);

                foreach_reverse(s;0..aasteps)
                {
                    auto color = ColorWhite;
                    color.a = cast(ubyte)(255 - s * 255 / aasteps);
                    foreach(i;1..g.numPoints)
                    {
                        auto p1x = data[g.dataOffset + (i - 1) * 2 + 0];
                        auto p1y = data[g.dataOffset + (i - 1) * 2 + 1];
                        auto p2x = data[g.dataOffset + (i - 0) * 2 + 0];
                        auto p2y = data[g.dataOffset + (i - 0) * 2 + 1];
                        if(p1x < 0 || p2x < 0) continue;
                        auto pt1 = T(cast(ST)((p1x + brdr) * lscale),cast(ST)((p1y + brdr) * lscale)) + pto;
                        auto pt2 = T(cast(ST)((p2x + brdr) * lscale),cast(ST)((p2y + brdr) * lscale)) + pto;
                        line(surf, pt1, pt2, lwidth * lscale + cast(ST)s / aadiv, color);
                    }
                }
                Rect srcRc = {x: cast(int)(pto.x), y: cast(int)(pto.y), w: wdth, h: hght};
                pto.x += wdth;
                GlyphData d;
                d.ch = g.ch;
                d.srcRect = srcRc;
                Rect dstRc = {x: cast(int)width, y: cast(int)width, w: cast(int)(g.width * scale), h: cast(int)(g.base * scale)};
                d.dstRect = dstRc;
                d.textureIndex = texIndex;
                glyphs ~= d;
                ++glyphIndex;
            }

            auto newSurf = new FFSurface!(Color)(surfSize,surfSize);
            scope(failure) newSurf.dispose();
            downsample(newSurf, surf);
            surfaces ~= newSurf;
        }

        Texture[] textures;
        scope(failure)
        {
            foreach(t;textures) t.dispose();
        }

        foreach(s;surfaces)
        {
            textures ~= new Texture(ren, s);
        }

        super(cast(int)ceil(fontHeight * scale), glyphs, textures);
    }
}

