﻿module game.units;

public import gamelib.types, gamelib.linalg, gamelib.math, gamelib.fixedpoint, gamelib.graphics.color;

import game.renderer.texture;
import game.renderer.palette;

//alias ColorT = RGBA8888Color;
alias ColorT = BGRA8888Color;

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

alias light_palette_t = Palette!(ColorT,LightPaletteBits, true,"+");
alias palette_t = LightPalette!(ColorT,PaletteBits,LightPaletteBits);
//alias palette_t = Palette!ColorT;
alias texture_t = Texture!(BaseTexturePaletted!(ColorT,palette_t));
//alias texture_t = Texture!(BaseTextureRGB!ColorT);
enum LightUnitDist = 10;


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

@nogc TransformedVertex transformVertex(in Vertex v, in mat4_t mat) pure nothrow
{
    TransformedVertex ret = void;
    ret.refPos = v.pos;
    ret.pos    = mat * vec4_t(v.pos, 1);
    ret.tpos   = v.tpos;
    return ret;
}
