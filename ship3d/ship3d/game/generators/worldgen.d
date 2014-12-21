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
    auto r0 = generateRoom(rnd, world, vec3i(2,2,2));
    //auto r1 = generateRoom(rnd, world, vec3i(1,1,1));
    //r.polygons[0].connect(&r.polygons[1], vec3_t(0,0,-60), quat_t.identity);
    //r.polygons[1].connect(&r.polygons[2], vec3_t(0,0,60), quat_t.yrotation(-PI / 2));
    //r0.polygons[1].connect(&r1.polygons[0], vec3_t(0,0,60), quat_t.zrotation(0*PI / 2));
    //r0.polygons[0].connect(&r1.polygons[1], vec3_t(0,0,-60), quat_t.zrotation(PI / 2));
    //r0.polygons[0].connect(&r1.polygons[2], vec3_t(60,0,0), quat_t.yrotation(PI / 2) * quat_t.xrotation(-PI / 2));
    //r0.polygons[0].connect(&r1.polygons[1], vec3_t(0,0,-60), quat_t.yrotation(0.05f));

    ret.put(r0);
    //ret.put(r1);
    foreach(ref r; ret.data[])
    {
        foreach(ref p; r.polygons)
        {
            p.texture = texgen.getTexture(TextureDesc("foo"));
        }
    }
    return ret.data;
}

