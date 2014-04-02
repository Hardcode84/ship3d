module game.units;

public import gamelib.types, gamelib.linalg, gamelib.math;

struct Vertex
{
    vec4 pos;
    ColorT color;
}

alias ColorT = Color;
