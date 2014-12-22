﻿module game.generators.roomgen;

import std.array;
import std.range;

import gamelib.util;

import game.units;
import game.world;
import game.topology.room;
import game.topology.polygon;

Room generateRoom(R)(auto ref R random, World world, in vec3i size)
{
    assert(size.x > 0);
    assert(size.y > 0);
    assert(size.z > 0);
    const pos_t unitLength = 30;

    auto vertices = appender!(Vertex[])();
    auto polygons = appender!(Polygon[])();
    const u = unitLength;

    const xoffset = -(u * size.x) / 2;
    const yoffset = -(u * size.y) / 2;
    const zoffset = -(u * size.z) / 2;
    //front, back, right, left, down, up
    int currInd = 0;
    foreach(k;TupleRange!(0,6))
    {
        const sizex = [size.x,size.x,size.z,size.z,size.z,size.z][k];
        const sizey = [size.y,size.y,size.y,size.y,size.x,size.x][k];

        foreach(i;0..sizey + 1)
        {
            foreach(j;0..sizex + 1)
            {
                const iu = i * u;
                const ju = j * u;
                const x = [xoffset + ju, -xoffset - ju,   xoffset     , -xoffset,       xoffset + ju, -xoffset - ju][k];
                const y = [yoffset + iu,  yoffset + iu,   yoffset + iu,  yoffset + iu,  yoffset     , -yoffset][k];
                const z = [zoffset     , -zoffset,       -zoffset - ju,  zoffset + ju, -zoffset - iu, -zoffset - iu][k];
                vertices.put(Vertex(vec4_t(x, y, z, 1),vec2_t(i % 2,j % 2)));
            }
        }
        scope(exit) currInd += (sizex + 1) * (sizey + 1);

        foreach(i;0..sizey)
        {
            foreach(j;0..sizex)
            {
                int[6] indices;
                indices[0] = (currInd + (i + 0) * (sizex + 1) + j + 0);
                indices[1] = (currInd + (i + 0) * (sizex + 1) + j + 1);
                indices[2] = (currInd + (i + 1) * (sizex + 1) + j + 1);
                indices[3] = (currInd + (i + 0) * (sizex + 1) + j + 0);
                indices[4] = (currInd + (i + 1) * (sizex + 1) + j + 1);
                indices[5] = (currInd + (i + 1) * (sizex + 1) + j + 0);
                polygons.put(Polygon(indices));
            }
        }

    }

    //
    //    4---5
    //  y/|  /|
    //  0---1 |
    //  | | | |
    //  | 7-|-6
    //  |/  |/
    //  3---2 x
    // z
    return new Room(world, vertices.data, polygons.data);
}