module game.topology.lightref;

import gamelib.containers.intrusivelist;

import game.units;

struct LightRef
{
    vec3_t pos;
    LightColorT color;
    LightRef* prev; //for allocator

    IntrusiveListLink roomLink;
    IntrusiveListLink entityLink;
}

