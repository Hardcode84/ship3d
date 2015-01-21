module game.entities.lightref;

import gamelib.containers.intrusivelist;

import game.units;
import game.renderer.light;

struct LightRef
{
    Light light;
    IntrusiveListLink roomLink;
    IntrusiveListLink entityLink;
}

