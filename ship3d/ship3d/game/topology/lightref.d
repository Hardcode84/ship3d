module game.topology.lightref;

import gamelib.containers.intrusivelist;

import game.units;
import game.topology.room;
import game.renderer.light;

struct LightRef
{
    Light light;
    Room room;
    LightRef* prev; //for allocator

    IntrusiveListLink roomLink;
    IntrusiveListLink entityLink;
}

