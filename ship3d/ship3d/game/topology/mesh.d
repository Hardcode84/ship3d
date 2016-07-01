module game.topology.mesh;

import game.units;

struct Mesh
{
    Vertex[] vertices;
    uint[3][] indices;
    texture_t texture;
}

void addTriangles(IndT)(ref Mesh mesh, in Vertex[] vertices, in IndT[3][] indices)
{
    const start = cast(IndT)mesh.vertices.length;
    mesh.vertices.length = start + vertices.length;
    mesh.vertices[start..$] = vertices[];
    const indStart = mesh.indices.length;
    mesh.indices.length = indStart + indices.length;
    foreach(i,const ref ind; indices[])
    {
        mesh.indices[indStart + i] = [ind[0] + start,ind[1] + start,ind[2] + start];
    }
}
