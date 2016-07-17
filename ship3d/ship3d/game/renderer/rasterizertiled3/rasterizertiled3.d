module game.renderer.rasterizertiled3.rasterizer;

import std.traits;
import std.algorithm;
import std.array;
import std.string;
import std.functional;
import std.range;

import gamelib.types;
import gamelib.util;
import gamelib.graphics.graph;
import gamelib.memory.utils;
import gamelib.memory.arrayview;

import game.units;
import game.utils;

import game.renderer.trianglebuffer;
import game.renderer.rasterizertiled3.types;
import game.renderer.rasterizertiled3.trianglesplitter;

@nogc:

struct RasterizerTiled3(bool HasTextures, bool WriteMask, bool ReadMask, bool HasLight)
{
    version(LDC)
    {
        import ldc.attributes;
    @llvmAttr("unsafe-fp-math", "true"):
    }

    static void drawIndexedTriangle(AllocT,CtxT1,CtxT2,VertT,IndT)
        (auto ref AllocT alloc, auto ref CtxT1 outputContext, auto ref CtxT2 extContext, in VertT[] verts, in IndT[] indices) if(isIntegral!IndT)
    {
        assert(indices.length == 3);
        const(VertT)*[3] pverts;
        foreach(i,ind; indices) pverts[i] = verts.ptr + ind;
        enqueueTriangle(outputContext, extContext, pverts);
    }

private:
    struct VertsPack
    {
        vec3_t[3] verts = void;
        vec2_t[3] tcoords = void;

        this(VT)(in VT[] v)
        {
            assert(3 == v.length);
            verts = [v[0].pos.xyw,v[1].pos.xyw,v[2].pos.xyw];
            tcoords = [v[0].tpos,v[1].tpos,v[2].tpos];
        }
    }

    struct BuffElem(ExtContextT)
    {
        VertsPack vertspack;
        ExtContextT context;
    }

    static void enqueueTriangle(CtxT1,CtxT2,VertT)
        (auto ref CtxT1 outContext, auto ref CtxT2 extContext, in VertT[] pverts)
    {
        if(!isTrianglevValid(pverts[]))
        {
            return;
        }

        pushTriangleToBuffer!(flushHandler)(outContext.rasterizerCache,&outContext,BuffElem!(Unqual!(typeof(extContext)))(VertsPack(pverts), extContext));
    }

    static bool isTrianglevValid(VT)(in VT[] verts)
    {
        assert(3 == verts.length);
        const w1 = verts[0].pos.w;
        const w2 = verts[1].pos.w;
        const w3 = verts[2].pos.w;
        const x1 = verts[0].pos.x;
        const x2 = verts[1].pos.x;
        const x3 = verts[2].pos.x;
        const y1 = verts[0].pos.y;
        const y2 = verts[1].pos.y;
        const y3 = verts[2].pos.y;
        const mat = Matrix!(Unqual!(typeof(x1)),3,3)(
            x1, y1, w1,
            x2, y2, w2,
            x3, y3, w3);
        const d = mat.det;
        enum tol = 0.001f;
        if(d < tol || (w1 > tol && w2 > tol && w3 > tol))
        {
            return false;
        }
        return true;
    }

    public static void flushHandler(ContextT,ElemT)(auto ref ContextT context, in ElemT[] elements)
    {
        int i = 0;
        const clipRect = context.clipRect;
        void areaHandler(const ref TriangleArea area)
        {
            //debugOut("areaHandler");
            auto line = context.surface[area.y0];
            auto iter0 = area.iter0;
            auto iter1 = area.iter1;
            foreach(y;area.y0..area.y1)
            {
                //debugOut(iter0.x," ",iter1.x);
                const x0 = max(clipRect.x, iter0.x);
                const x1 = min(clipRect.x + clipRect.w, iter1.x);
                if(x1 > x0)
                {
                    foreach(i;x0..x1)
                    {
                        //assert(ColorGreen == line[i]);
                    }
                    line[x0..x1] = (0 == i % 2 ? ColorBlue : ColorRed);
                }
                iter0.incY();
                iter1.incY();
                ++line;
            }
            ++i;
        }

        foreach(const ref elem; elements)
        {
            splitTriangle!areaHandler(elem.vertspack.verts[], context.clipRect);
        }
    }


}
