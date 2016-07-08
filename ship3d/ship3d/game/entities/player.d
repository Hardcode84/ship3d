module game.entities.player;

import gamelib.containers.intrusivelist;

public import game.entities.inertialentity;

import game.topology.lightref;
import game.topology.polygon;

import game.renderer.light;

import game.controls;

class Player : InertialEntity
{
//pure nothrow:
private:
    static assert(KeyActions.min >= 0);
    static assert(KeyActions.max < 0xff);
    bool[KeyActions.max + 1] mActState = false;
    pos_t mRollSpeed = 0.0f;

    IntrusiveList!(LightRef,"entityLink") mLightRefs;

    void onKeyEvent(in ref KeyEvent e)
    {
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
        const speedCoeff = 0.01f;//0.1f;
        if(actState(KeyActions.FORWARD))
        {
            accelerate(dir * vec3_t(0,0,1.0f)*speedCoeff);
        }
        else if(actState(KeyActions.BACKWARD))
        {
            accelerate(dir * vec3_t(0,0,-1.0f)*speedCoeff);
        }

        enum strafeDir = quat_t.yrotation(PI / 2);
        if(actState(KeyActions.STRAFE_LEFT))
        {
            accelerate(dir * strafeDir * vec3_t(0,0,1.0f)*speedCoeff);
        }
        else if(actState(KeyActions.STRAFE_RIGHT))
        {
            accelerate(dir * strafeDir * vec3_t(0,0,-1.0f)*speedCoeff);
        }

        enum rollSpeed = PI / 2 * 0.001f;
        if(actState(KeyActions.ROLL_LEFT))
        {
            mRollSpeed -= rollSpeed;
            //rotate(quat_t.zrotation(-rollSpeed));
        }
        else if(actState(KeyActions.ROLL_RIGHT))
        {
            mRollSpeed += rollSpeed;
            //rotate(quat_t.zrotation(rollSpeed));
        }
        mRollSpeed *= 0.95f;
        rotate(quat_t.zrotation(mRollSpeed));
        super.update();
    }

    override void onAddedToWorld(Room room, in vec3_t pos, in quat_t dir) 
    {
        super.onAddedToWorld(room, pos, dir);
    }

    override void onAddedToRoom(EntityRef* eref)
    {
        super.onAddedToRoom(eref);
    }
    
    override void onRemovedFromRoom(EntityRef* eref)
    {
        super.onRemovedFromRoom(eref);
    }

    override void updatePos()
    {
        super.updatePos();
        auto range = mLightRefs[];
        while(!range.empty)
        {
            auto r = range.front;
            range.popFront;
            r.room.removeLight(r);
        }
        assert(mLightRefs.empty);
        auto con = mainConnection;
        addLight(con.room, null, con.pos);
    }

    private void addLight(Room room, Polygon* srcpoly, in vec3_t pos)
    {
        assert(room !is null);
        mLightRefs.insertFront(room.addLight(Light(pos, 7)));
        foreach(ref p;room.polygons)
        {
            if(p.isPortal && &p !is srcpoly)
            {
                auto con = p.connection;
                const newPos = con.transformFromPortal(pos);
                if(con.distance(newPos) > -MaxLightDist)
                {
                    addLight(con.room, con, newPos);
                }
            }
        }
    }
}

