module game.generators.worldgen;

import std.array;
import std.random;

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
    foreach(ref p; r.polygons)
    {
        p.mTexture = texgen.getTexture(TextureDesc("foo"));
    }
    ret.put(r);
    return ret.data;
}

