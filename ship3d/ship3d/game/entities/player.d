module game.entities.player;

public import game.entities.inertialentity;

import game.units;
import game.controls;

import game.world;

class Player : InertialEntity
{
    static assert(KeyActions.min >= 0);
    static assert(KeyActions.max < 0xff);
    bool mActState[KeyActions.max + 1] = false;
    void onKeyEvent(in ref KeyEvent e)
    {
        /*debugOut(e.action);
        if(e.pressed)
        {
            if(KeyActions.FORWARD == e.action)
            {
                move(dir * vec3_t(0,0,1.0f)*10);
            }
            else if(KeyActions.BACKWARD == e.action)
            {
                move(dir * vec3_t(0,0,-1.0f)*10);
            }
        }*/
        mActState[e.action] = e.pressed;
    }

    @property actState(in KeyActions a) const pure nothrow { return mActState[a]; }

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
        super.update();
        if(actState(KeyActions.FORWARD))
        {
            accelerate(dir * vec3_t(0,0,1.0f)*0.3f);
        }
        else if(actState(KeyActions.BACKWARD))
        {
            accelerate(dir * vec3_t(0,0,-1.0f)*0.3f);
        }

        enum strafeDir = quat_t.yrotation(PI / 2);
        if(actState(KeyActions.STRAFE_LEFT))
        {
            accelerate(dir * strafeDir * vec3_t(0,0,1.0f)*0.3f);
        }
        else if(actState(KeyActions.STRAFE_RIGHT))
        {
            accelerate(dir * strafeDir * vec3_t(0,0,-1.0f)*0.3f);
        }
    }
}

