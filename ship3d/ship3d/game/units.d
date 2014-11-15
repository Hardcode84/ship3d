module game.units;

public import gamelib.types, gamelib.linalg, gamelib.math, gamelib.fixedpoint;

import game.renderer.texture;

//alias ColorT = RGBA8888Color;
alias ColorT = BGRA8888Color;

alias pos_t = float;
//alias pos_t = FixedPoint!(16,16,int);
alias vec4_t = Vector!(pos_t,4);
alias vec2_t = Vector!(pos_t,2);
alias mat4_t = Matrix!(pos_t,4,4);

alias texture_t = Texture!(BaseTextureRGB!ColorT);

struct Vertex
{
    vec4_t pos;
    vec2_t tpos;
    ColorT color;
}
