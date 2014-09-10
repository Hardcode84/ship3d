module game.units;

public import gamelib.types, gamelib.linalg, gamelib.math;

//alias ColorT = RGBA8888Color;
alias ColorT = BGRA8888Color;

struct Vertex
{
    vec4 pos;
    vec2 tpos;
    ColorT color;
}
