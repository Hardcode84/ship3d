﻿module game.topology.plane;

import std.array;
import std.traits;

import game.units;

struct Plane
{
pure nothrow:
private:
    struct Edge
    {
        pure nothrow:
        immutable pos_t dx, dy, c;
        this(pos_t dx1, pos_t dy1, pos_t c1)
        {
            dx = dx1;
            dy = dy1;
            c  = c1;
        }
        this(V)(in V v0, in V v1)
        {
            dx = v1.x - v0.x;
            dy = v1.y - v0.y;
            c  = (dy * v0.x - dx * v0.y);
        }
        
        auto val(pos_t x, pos_t y) const
        {
            return c + dx * y - dy * x;
        }

        auto val(V)(in V v) const
        {
            return val(v.x, v.y);
        }

        bool opEquals(in Edge e) const
        {
            const eps = 0.001f;
            return almost_equal(dx, e.dx, eps) &&
                   almost_equal(dy, e.dy, eps) &&
                   almost_equal(c,  e.c,  eps);
        }

        auto opUnary(string op : "-")() const
        {
            return Edge(-dx, -dy, -c);
        }
    }
    immutable vec3_t mNormal;
    immutable vec3_t mVec0;
    immutable vec3_t mVec1;
    immutable pos_t  mD;
    Edge[]           mEdges;
public:
    package this(V)(in V v0, in V v1, in V v2)
    {
        mNormal = cross((v1.xyz - v0.xyz),(v2.xyz - v0.xyz)).normalized;
        mVec0   = (v1.xyz - v0.xyz).normalized;
        mVec1   = cross(mNormal, mVec0).normalized;
        mD      = -dot(v0.xyz, mNormal);
        mEdges  = [
            Edge(project(v0.xyz), project(v1.xyz)),
            Edge(project(v1.xyz), project(v2.xyz)),
            Edge(project(v2.xyz), project(v0.xyz))];
    }

    auto edges() inout { return mEdges[]; }

    pos_t distance(in vec3_t pos) const
    {
        return dot(pos, normal) + mD;
    }

    auto project(in vec3_t pos) const
    {
        return vec2_t(dot(pos, mVec0) + mD, dot(pos, mVec1) + mD);
    }

    @property vec3_t normal() const
    {
        return mNormal;
    }

    bool opEquals(in Plane p) const
    {
        const eps = 0.001f;
        return almost_equal(mNormal.x, p.mNormal.x, eps) &&
               almost_equal(mNormal.y, p.mNormal.y, eps) &&
               almost_equal(mNormal.z, p.mNormal.z, eps) &&
               almost_equal(mD,        p.mD,        eps);
    }

    package void merge(V)(in V v0, in V v1, in V v2)
    {
        Edge[3] edges1 = [
            Edge(project(v0.xyz), project(v1.xyz)),
            Edge(project(v1.xyz), project(v2.xyz)),
            Edge(project(v2.xyz), project(v0.xyz))];

        auto newEdges = appender!(Edge[]);
    outer0: foreach(const ref e0; edges1[])
        {
            foreach(const ref e1; edges[])
            {
                if(e0 == -e1)
                {
                    continue outer0;
                }
                else if(e0 == e1)
                {
                    continue outer0;
                }
            }
            newEdges ~= e0;
        }

    outer1: foreach(const ref e0; edges[])
        {
            foreach(const ref e1; edges1[])
            {
                if(e0 == -e1)
                {
                    continue outer1;
                }
            }
            newEdges ~= e0;
        }
        mEdges = newEdges.data;
        //assert(!edges.empty);
    }

    bool checkCollision(in vec3_t pos, in pos_t size) const
    {
        //assert(!edges.empty);
        if(distance(pos) > size) return false;
        foreach(const ref e; edges)
        {
            if(e.val(project(pos)) < -size) return false;
        }
        return true;
    }
}

Plane[] createPlanes(V,I)(in V[] vertices, in I[] indices) pure nothrow if(isIntegral!I)
{
    assert(indices.length > 0);
    assert(0 == indices.length % 3);
    Plane[] ret;
outer: foreach(i;0..indices.length/3)
    {
        const i0 = indices[i * 3 + 0];
        const i1 = indices[i * 3 + 1];
        const i2 = indices[i * 3 + 2];
        /*debugOut(i0);
        debugOut(i1);
        debugOut(i2);
        debugOut(vertices.length);*/
        auto pl = Plane(vertices[i0].pos,vertices[i1].pos,vertices[i2].pos);
        foreach(ref p;ret[])
        {
            if(p == pl)
            {
                p.merge(vertices[i0].pos,vertices[i1].pos,vertices[i2].pos);
                continue outer;
            }
        }
        ret ~= pl;
    }
    return ret;
}
