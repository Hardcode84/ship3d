module main;

import game.game;

void main(string[] args)
{
    scope game = new Game(args);
    game.run();
}
