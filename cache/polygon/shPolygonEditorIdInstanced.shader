/**
 * GM3D ID picking shader (instanced static geometry).
 * Instance world matrix from attributes; flat u_id fragment.
 */

attribute vec3 in_Position;

attribute vec4 in_InstanceMatrixCol0;
attribute vec4 in_InstanceMatrixCol1;
attribute vec4 in_InstanceMatrixCol2;
attribute vec4 in_InstanceMatrixCol3;

void main()
{
    mat4 world = mat4(
        in_InstanceMatrixCol0,
        in_InstanceMatrixCol1,
        in_InstanceMatrixCol2,
        in_InstanceMatrixCol3
    );

    vec4 worldPos = world * vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
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

