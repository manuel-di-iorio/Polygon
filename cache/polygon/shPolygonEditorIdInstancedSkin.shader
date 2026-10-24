/**
 * GM3D ID picking shader (instanced skinned geometry).
 * Instance world matrix plus bone-atlas skinning; flat u_id fragment.
 */

#define MAX_BONES 128

attribute vec3 in_Position;
attribute vec4 in_BlendWeight;
attribute vec4 in_BlendIndices;

attribute vec4 in_InstanceMatrixCol0;
attribute vec4 in_InstanceMatrixCol1;
attribute vec4 in_InstanceMatrixCol2;
attribute vec4 in_InstanceMatrixCol3;
attribute float in_BoneAtlasRow;

uniform sampler2D gm_BoneAtlas;
uniform float gm_BoneAtlasHeight;

mat4 fetchBone(int boneIndex)
{
    float invWidth = 1.0 / float(MAX_BONES * 4);
    float invHeight = 1.0 / gm_BoneAtlasHeight;
    float v = (in_BoneAtlasRow + 0.5) * invHeight;
    vec4 c0 = texture2D(gm_BoneAtlas, vec2((float(boneIndex * 4 + 0) + 0.5) * invWidth, v));
    vec4 c1 = texture2D(gm_BoneAtlas, vec2((float(boneIndex * 4 + 1) + 0.5) * invWidth, v));
    vec4 c2 = texture2D(gm_BoneAtlas, vec2((float(boneIndex * 4 + 2) + 0.5) * invWidth, v));
    vec4 c3 = texture2D(gm_BoneAtlas, vec2((float(boneIndex * 4 + 3) + 0.5) * invWidth, v));
    return mat4(c0, c1, c2, c3);
}

void main()
{
    mat4 world = mat4(
        in_InstanceMatrixCol0,
        in_InstanceMatrixCol1,
        in_InstanceMatrixCol2,
        in_InstanceMatrixCol3
    );

    int j0 = int(in_BlendIndices.x + 0.5);
    int j1 = int(in_BlendIndices.y + 0.5);
    int j2 = int(in_BlendIndices.z + 0.5);
    int j3 = int(in_BlendIndices.w + 0.5);

    mat4 skin = fetchBone(j0) * in_BlendWeight.x
        + fetchBone(j1) * in_BlendWeight.y
        + fetchBone(j2) * in_BlendWeight.z
        + fetchBone(j3) * in_BlendWeight.w;

    vec4 p = skin * vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    vec4 worldPos = world * p;
    gl_Position = gm_Matrices[MATRIX_PROJECTION] * gm_Matrices[MATRIX_VIEW] * worldPos;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
/**
 * GM3D ID picking fragment shader (static variant).
 * Flat u_id output, set per placement via mat.setFloatArray("u_id", ...).
 * Alpha stays 1: id 0 (black) is reserved for "miss".
 */

uniform vec4 u_id;

void main()
{
    gl_FragColor = u_id;
}

