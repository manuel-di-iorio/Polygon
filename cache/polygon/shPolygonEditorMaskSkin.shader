/**
 * GM3D selection mask shader (skinned geometry).
 * Same solid-white output as shGM3DMask, but applies GPU bone skinning first
 * (same inputs as sAnimated) so the mask follows the animated pose instead
 * of the bind pose. No lighting, no fog, no textures.
 */

#define MAX_BONES 128

attribute vec3 in_Position;
attribute vec4 in_BlendWeight;
attribute vec4 in_BlendIndices;

uniform mat4 gm_BoneMatrices[MAX_BONES];

void main()
{
    int j0 = int(in_BlendIndices.x + 0.5);
    int j1 = int(in_BlendIndices.y + 0.5);
    int j2 = int(in_BlendIndices.z + 0.5);
    int j3 = int(in_BlendIndices.w + 0.5);

    mat4 skin = gm_BoneMatrices[j0] * in_BlendWeight.x
        + gm_BoneMatrices[j1] * in_BlendWeight.y
        + gm_BoneMatrices[j2] * in_BlendWeight.z
        + gm_BoneMatrices[j3] * in_BlendWeight.w;

    vec4 p = skin * vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * p;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
/**
 * GM3D selection mask fragment shader (skinned variant).
 * Solid white, see shGM3DMask.fsh.
 */

void main()
{
    gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);
}

