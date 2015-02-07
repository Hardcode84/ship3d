module game.generators.worldgen;

import std.stdio;
import std.array;
import std.random;
import std.algorithm;

import game.units;
import game.world;
import game.topology.room;
import game.topology.polygon;

import game.generators.roomgen;
import game.generators.texturegen;
import game.generators.lightgen;

//pure nothrow:
Room[] generateWorld(World world, uint seed)
{
    writeln("generateWorld");
    scope(exit) writeln("generateWorld done");
    Random rnd = seed;
    TextureGen texgen = seed;
    world.lightPalette = texgen.lightPalette;

    enum numGenerations = 7;
    enum numRooms = 10;

    writeln("create rooms");
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
            auto room = generateRoom(rnd, world, size, 50);
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
                auto arr = cartesianProduct(polys1,polys2).filter!(a => isCompatiblePolygons(a[0],a[1])).array;
                if(arr.empty)
                {
                    assert(false,"Unable to connect rooms");
                }
                auto res = arr[uniform(0,arr.length,rnd)];
                res[0].connect(res[1]);
            }
            write(".");
            stdout.flush();
            ret.put(room);
        }
    }
    writeln();
    writeln("create rooms done");
    generateLights(rnd, ret.data);
    return ret.data;
}

private:
auto polygonsForPortals(Room room)
{
    return room.polygons.map!((ref a) => &a).filter!(a => (!a.isPortal && a.adjacent.all!(a => !a.isPortal)));
}

bool isCompatiblePolygons(Polygon* poly1, Polygon* poly2)
{
    assert(poly1 !is null);
    assert(poly2 !is null);
    return (poly1.type == PolygonType.Front && poly2.type == PolygonType.Back) ||
           (poly1.type == PolygonType.Back  && poly2.type == PolygonType.Front) ||
           (poly1.type == PolygonType.Up    && poly2.type == PolygonType.Down) ||
           (poly1.type == PolygonType.Down  && poly2.type == PolygonType.Up) ||
           (poly1.type == PolygonType.Left  && poly2.type == PolygonType.Right) ||
           (poly1.type == PolygonType.Right && poly2.type == PolygonType.Left);
}

bool checkNormals(Polygon* poly)
{
    assert(poly !is null);
    assert(poly.isPortal);
    enum eps = 0.001f;
    return zip(poly.adjacent[],poly.connectionAdjacent[])
        .all!(a => !almost_equal(
                (a[0].plane.normal * poly.connectionDir).normalized,
                (-a[1].plane.normal),
                eps));
}