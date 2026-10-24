/**
 * GM3D missing-material shader (static geometry).
 * Solid magenta: marks meshes with no material
 * so the problem is visible instead of silently wrong. No lighting, no fog,
 * no textures. Only in_Position is declared, like shGM3DGrid: extra vertex
 * attributes present in GM3D buffers are ignored.
 */

attribute vec3 in_Position;

void main()
{
    vec4 object_space_pos = vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * object_space_pos;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
/**
 * GM3D missing-material fragment shader (shared by static and skinned).
 * Solid magenta (1, 0, 1, 1).
 */

void main()
{
    gl_FragColor = vec4(1.0, 0.0, 1.0, 1.0);
}

