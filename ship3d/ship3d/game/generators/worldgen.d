module game.generators.worldgen;

import std.array;
import std.random;

import game.units;
import game.world;
import game.topology.room;

import game.generators.roomgen;
import game.generators.texturegen;

Room[] generateWorld(World world, uint seed) /*pure nothrow*/
{
    Random rnd = seed;
    TextureGen texgen = seed;
    auto ret =appender!(Room[])();
    auto r = generateRoom(rnd, world);
    r.polygons[0].connect(&r.polygons[1], vec3_t(0,0,-120), quat_t.identity);
    foreach(ref p; r.polygons)
    {
        p.texture = texgen.getTexture(TextureDesc("foo"));
    }
    ret.put(r);
    return ret.data;
}

