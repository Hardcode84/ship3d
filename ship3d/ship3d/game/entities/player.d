module game.entities.player;

public import game.entities.inertialentity;

import game.units;
import game.controls;

import game.world;

class Player : InertialEntity
{
//pure nothrow:
private:
    static assert(KeyActions.min >= 0);
    static assert(KeyActions.max < 0xff);
    bool mActState[KeyActions.max + 1] = false;
    void onKeyEvent(in ref KeyEvent e)
    {
        //debugOut(e.action);
        mActState[e.action] = e.pressed;
    }

    @property actState(in KeyActions a) const { return mActState[a]; }

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
        if(actState(KeyActions.FORWARD))
        {
            accelerate(dir * vec3_t(0,0,1.0f)*0.1f);
        }
        else if(actState(KeyActions.BACKWARD))
        {
            accelerate(dir * vec3_t(0,0,-1.0f)*0.1f);
        }

        enum strafeDir = quat_t.yrotation(PI / 2);
        if(actState(KeyActions.STRAFE_LEFT))
        {
            accelerate(dir * strafeDir * vec3_t(0,0,1.0f)*0.1f);
        }
        else if(actState(KeyActions.STRAFE_RIGHT))
        {
            accelerate(dir * strafeDir * vec3_t(0,0,-1.0f)*0.1f);
        }

        enum rollSpeed = PI / 2 * 0.01f;
        if(actState(KeyActions.ROLL_LEFT))
        {
            rotate(quat_t.zrotation(-rollSpeed));
        }
        else if(actState(KeyActions.ROLL_RIGHT))
        {
            rotate(quat_t.zrotation(rollSpeed));
        }
        super.update();
    }
}

