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
    auto ret = appender!(Room[])();
    auto r0 = generateRoom(rnd, world, vec3i(1,1,1));
    auto r1 = generateRoom(rnd, world, vec3i(1,1,1));
    r0.polygons[1].connect(&r1.polygons[5]);

    ret.put(r0);
    ret.put(r1);
    foreach(ref r; ret.data[])
    {
        foreach(ref p; r.polygons)
        {
            p.texture = texgen.getTexture(TextureDesc("foo"));
        }
    }
    return ret.data;
}

