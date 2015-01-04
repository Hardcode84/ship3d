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

Room[] generateWorld(World world, uint seed) /*pure nothrow*/
{
    Random rnd = seed;
    TextureGen texgen = seed;

    enum numGenerations = 7;
    enum numRooms = 10;

    auto ret = appender!(Room[])();
    Appender!(Room[])[numGenerations] rooms;
    foreach(g;0..numGenerations)
    {
        foreach(r;0..numRooms)
        {
            const size = vec3i(
                uniform(2,5,rnd),
                uniform(2,5,rnd),
                uniform(2,5,rnd));
            auto room = generateRoom(rnd, world, size);
            foreach(ref p; room.polygons)
            {
                p.texture = texgen.getTexture(TextureDesc(cast(ubyte)g));
            }
            rooms[g].put(room);
            if(!ret.data.empty)
            {
                auto polys1 = polygonsForPortals(ret.data[$ - 1]);
                auto polys2 = polygonsForPortals(room);
                assert(!polys1.empty);
                assert(!polys2.empty);
                polys1[uniform(0,polys1.length,rnd)].connect(polys2[uniform(0,polys2.length,rnd)]);
                //polys1[0].connect(polys2[1]);
            }
            ret.put(room);
        }
    }

    /*auto r0 = generateRoom(rnd, world, vec3i(3,3,3));
    auto r1 = generateRoom(rnd, world, vec3i(1,1,1));
    r0.polygons[5].connect(&r0.polygons[7]);
    r0.polygons[1].connect(&r0.polygons[3]);

    ret.put(r0);
    ret.put(r1);
    foreach(ref r; ret.data[])
    {
        foreach(ref p; r.polygons)
        {
            p.texture = texgen.getTexture(TextureDesc(0));
        }
    }*/
    return ret.data;
}

private:
auto polygonsForPortals(Room room)
{
    auto ret = appender!(Polygon*[])();
    ret.put(room.polygons.map!((ref a) => &a).filter!(a => (!a.isPortal && a.adjacent.all!(a => !a.isPortal))));
    return ret.data;
}