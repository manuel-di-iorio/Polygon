/**
 * GM3D ID picking shader (static geometry).
 * Same vertex transform as shGM3DMask: world-view-projection only, no
 * lighting, no fog, no textures. The fragment outputs the flat u_id colour
 * assigned per placement (see poly_gpu_pick): R==B carries the id low
 * byte, G the high byte, so decode is immune to BGRA/RGBA readback order.
 */

attribute vec3 in_Position;

void main()
{
    vec4 object_space_pos = vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * object_space_pos;
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

