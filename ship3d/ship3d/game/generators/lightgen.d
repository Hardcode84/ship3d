module game.generators.lightgen;

import std.random;
import std.array;
import std.algorithm;
import std.range;

import game.units;
import game.renderer.light;
import game.topology.room;
import game.topology.polygon;

void generateLights(R)(auto ref R rnd, Room[] rooms)
{
    Light[][Room] roomLights;
    foreach(room; rooms[])
    {
        const bbox = room.vertices[].map!(a => a.pos).reduce!(
            (a,b) => vec3_t(zip(a[],b[]).map!(a => min(a[0],a[1])).array),
            (a,b) => vec3_t(zip(a[],b[]).map!(a => max(a[0],a[1])).array));
        const numlights = uniform(0, 3, rnd);
    numlightsloop: foreach(i;0..numlights)
        {
            foreach(j;0..10000)
            {
                const pos = vec3_t(zip(bbox[0][],bbox[1][]).map!(a => uniform!"()"(a[0],a[1],rnd)).array);
                if(room.polygons[].map!(a => a.plane).all!(a => (a.distance(pos) > 0)))
                {
                    roomLights[room] ~= Light(pos, uniform(0, 1 << LightPaletteBits, rnd));
                    continue numlightsloop;
                }
            }
            assert(false,"Cannot find valid position for light");
        }
    }
    foreach(r; rooms[])
    {
        void addLight(Room room, Polygon* srcpoly, in vec3_t pos, in LightColorT color)
        {
            assert(room !is null);
            room.staticLights ~= Light(pos, color);
            foreach(ref p;room.polygons)
            {
                if(p.isPortal && &p !is srcpoly)
                {
                    auto con = p.connection;
                    const newPos = con.transformFromPortal(pos);
                    if(con.distance(newPos) > -MaxLightDist)
                    {
                        addLight(con.room, con, newPos, color);
                    }
                }
            }
        }
        Light[] e;
        foreach(const ref l;roomLights.get(r,e))
        {
            addLight(r, null, l.pos, l.color);
        }
    }
}