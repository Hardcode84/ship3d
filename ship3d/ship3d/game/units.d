module game.units;

public import gamelib.types;
public import gamelib.linalg;
public import gamelib.math;
public import gamelib.fixedpoint;
public import gamelib.graphics.color;

static if(0)
{
    import gamelib.memory.stackalloc;
    alias StackAlloc = gamelib.memory.stackalloc.StackAlloc;
}
else
{
    import gamelib.memory.growablestackalloc;
    alias StackAlloc = gamelib.memory.growablestackalloc.GrowableStackAlloc;
}

import game.renderer.texture;
import game.renderer.palette;

//alias ColorT = RGBA8888Color;
alias ColorT = BGRA8888Color;
alias LightColorT = int;

alias pos_t = float;
//alias pos_t = FixedPoint!(16,16,int);
alias quat_t = Quaternion!pos_t;
alias vec4_t = Vector!(pos_t,4);
alias vec3_t = Vector!(pos_t,3);
alias vec2_t = Vector!(pos_t,2);
alias mat4_t = Matrix!(pos_t,4,4);
alias mat3_t = Matrix!(pos_t,3,3);
alias mat2_t = Matrix!(pos_t,2,2);

enum PaletteBits      = 6;
enum LightPaletteBits = 6;
enum LightColorBits   = 3;
enum LightBrightnessBits = LightPaletteBits - LightColorBits;
enum LightmapRes = 16;
static assert(LightColorBits > 0);
static assert(LightBrightnessBits > 0);

alias light_palette_t = Palette!(ColorT,LightPaletteBits, true,"+");
//alias palette_t = LightPalette!(ColorT,PaletteBits,LightPaletteBits);
alias palette_t = Palette!(ColorT,LightPaletteBits, false);
alias texture_t = Texture!(BaseTextureRGB!(ColorT));
alias lightmap_t = Texture!(BaseTextureRGB!byte);
//alias texture_t = Texture!(BaseTextureRGB!ColorT);
//enum LightUnitDist = 10;
enum MaxLightDist = 200;

static if(0)
{
    import game.renderer.rasterizerhybrid3;
    alias Rasterizer =   RasterizerHybrid3;
}
else static if(0)
{
    import game.renderer.rasterizertiled2;
    alias Rasterizer =   RasterizerTiled2;
}
else
{
    import game.renderer.rasterizertiled3.rasterizer;
    alias Rasterizer =   RasterizerTiled3;
}

struct Vertex
{
    vec3_t pos;
    vec2_t tpos;
}

struct TransformedVertex
{
    vec3_t refPos;
    vec2_t tpos;
    vec4_t pos;
}
