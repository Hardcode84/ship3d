module main;

import game.game;

extern(C)
{
    void _d_assert(string file, uint line)
    {
        import std.stdio;
        writefln("Assertion in \"%s\" on line %s", file, line);
        import core.stdc.stdlib;
        abort();
    }
}

void main(string[] args)
{
    scope game = new Game(args);
    game.run();
}

