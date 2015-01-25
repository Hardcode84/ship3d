module game.generators.worldgen;

import std.array;
import std.random;
import std.algorithm;

import game.units;
import game.world;
import game.topology.room;
import game.topology.polygon;

import game.generators.roomgen;
import game.generators.texturegen;

//pure nothrow:
Room[] generateWorld(World world, uint seed)
{
    Random rnd = seed;
    TextureGen texgen = seed;
    world.lightPalette = texgen.lightPalette;

    enum numGenerations = 7;
    enum numRooms = 10;

    auto ret = appender!(Room[])();

    /*auto room = generateRoom(rnd, world, vec3i(3,3,3));
    foreach(ref p; room.polygons)
    {
        p.texture = texgen.getTexture(TextureDesc(cast(ubyte)0));
    }
    ret.put(room);*/
    Appender!(Room[])[numGenerations] rooms;
    foreach(g;0..numGenerations)
    {
        foreach(r;0..numRooms)
        {
            const size = vec3i(
                uniform(1,5,rnd),
                uniform(1,5,rnd),
                uniform(1,5,rnd));
            auto room = generateRoom(rnd, world, size);
            foreach(ref p; room.polygons)
            {
                p.texture = texgen.getTexture(TextureDesc(cast(ubyte)g));
            }
            rooms[g].put(room);
            if(!ret.data.empty)
            {
                auto polys1 = polygonsForPortals(ret.data[$ - 1]).array;
                auto polys2 = polygonsForPortals(room).array;
                assert(!polys1.empty);
                assert(!polys2.empty);
                polys1[uniform(0,polys1.length,rnd)].connect(polys2[uniform(0,polys2.length,rnd)]);
            }
            ret.put(room);
        }
    }
    return ret.data;
}

private:
auto polygonsForPortals(Room room)
{
    return room.polygons.map!((ref a) => &a).filter!(a => (!a.isPortal && a.adjacent.all!(a => !a.isPortal)));
}