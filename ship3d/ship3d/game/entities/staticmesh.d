module game.entities.staticmesh;

public import game.entities.entity;

import game.topology.mesh;

import game.units;
import game.utils;
import game.world;

final class StaticMesh : Entity
{
private:
    Mesh mMesh;
public:
    this(World w, Mesh mesh)
    {
        super(w);
        mMesh = mesh;
    }

    override void draw(ref RendererT renderer, DrawParams params) const
    {
        import std.algorithm;
        import game.renderer.light;

        auto allocState = params.alloc.state;
        scope(exit) params.alloc.restoreState(allocState);

        auto transformedVertices = transformVertices(mMesh.vertices[], mMesh.indices[].map!((ref a) => a[]).joiner, params.alloc, renderer.state.matrix);

        enum DynLights = false;
        struct Context2
        {
            const(texture_t) texture;
            static if(DynLights)
            {
                const(Light)[] lights;
            }
            const(LightController) lightController;
        }

        static if(DynLights)
        {
            Context2 ctx = {texture: mMesh.texture, lights: params.room.lights, lightController: params.room.lightController};
        }
        else
        {
            Context2 ctx = {texture: mMesh.texture, lightController: params.room.lightController};
        }

        alias RastT2 = Rasterizer!(true,false,false,DynLights);
        foreach(const ref ind; mMesh.indices[])
        {
            renderer.drawIndexedTriangle!RastT2(params.alloc, ctx, transformedVertices[], ind[]);
        }
    }
}

