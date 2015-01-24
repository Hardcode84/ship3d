module game.topology.refalloc;

import gamelib.memory.poolalloc;

public import game.topology.entityref;
public import game.topology.lightref;

alias RefAllocator = PoolAlloc!(EntityRef,LightRef);