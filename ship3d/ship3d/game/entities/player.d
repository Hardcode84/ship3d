module game.entities.player;

public import game.entities.entity;

import game.units;
import game.controls;

import game.world;

class Player : Entity
{
    void onKeyEvent(in ref KeyEvent e)
    {
        debugOut(e.action);
        if(KeyActions.FORWARD == e.action)
        {
            move(dir * vec3_t(0,0,1.0f)*3);
        }
        else if(KeyActions.BACKWARD == e.action)
        {
            move(dir * vec3_t(0,0,-1.0f)*3);
        }
    }

    void onCursorEvent(in ref CursorEvent e)
    {
        enum xrot = -PI / 2 * 0.001f;
        enum yrot = -PI / 2 * 0.001f;
        rotate(quat_t.yrotation(xrot * e.dx) * quat_t.xrotation(yrot * e.dy));
    }

    void onInputEvent(in ref InputEvent e)
    {
        e.tryVisit(&this.onKeyEvent,
                   &this.onCursorEvent,
                   () {});
    }
public:
    this(World w)
    {
        super(w);
        world.addInputListener(&this.onInputEvent);
    }

    override void dispose()
    {
        world.removeInputListener(&this.onInputEvent);
    }

    override void update()
    {
    }
}

