module game.generators.roomgen;

import std.array;

import gamelib.util;

import game.units;
import game.world;
import game.topology.room;
import game.topology.polygon;

Room generateRoom(R)(auto ref R random, World world)
{
    const pos_t unitLength = 30;
    /*const w = 1;
    const h = 1;
    const d = 1;
    const maxX = (w * unitLength) / 2;
    const maxY = (h * unitLength) / 2;
    const maxZ = (d * unitLength) / 2;
    const minX = -maxX;
    const minY = -maxY;
    const minZ = -maxZ;*/

    auto vertices = appender!(Vertex[])();
    auto polygons = appender!(Polygon[])();
    /*foreach(i;TupleRange!(0,6))
    {
        static if(0 == i)
        {
            const maxJ = w;
            const maxK = h;
        }
    }*/
    const u = unitLength;
    vertices.put(Vertex(vec4_t(-u,-u,-u,1),vec2_t(0,0)));//0
    vertices.put(Vertex(vec4_t( u,-u,-u,1),vec2_t(1,0)));//1
    vertices.put(Vertex(vec4_t( u, u,-u,1),vec2_t(1,1)));//2
    vertices.put(Vertex(vec4_t(-u, u,-u,1),vec2_t(0,1)));//3

    vertices.put(Vertex(vec4_t(-u,-u, u,1),vec2_t(1,1)));//4
    vertices.put(Vertex(vec4_t( u,-u, u,1),vec2_t(0,1)));//5
    vertices.put(Vertex(vec4_t( u, u, u,1),vec2_t(0,0)));//6
    vertices.put(Vertex(vec4_t(-u, u, u,1),vec2_t(1,0)));//7

    //    4---5
    //   /|  /|
    //  0---1 |
    //  | | | |
    //  | 7-|-6
    //  |/  |/
    //  3---2

    //polygons.put(Polygon([0,1,2,0,2,3]));//front
    polygons.put(Polygon([0,1,2,0,2,3]));//front
    polygons.put(Polygon([4,6,5,4,7,6]));//back
    polygons.put(Polygon([0,7,4,0,3,7]));//left
    polygons.put(Polygon([1,5,6,1,6,2]));//right
    polygons.put(Polygon([4,5,1,4,1,0]));//up
    polygons.put(Polygon([7,2,6,7,3,2]));//down

    return new Room(world, vertices.data, polygons.data);
}