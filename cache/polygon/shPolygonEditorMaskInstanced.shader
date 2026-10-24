/**
 * GM3D selection mask shader (instanced static geometry).
 * Instance world matrix from attributes; solid white fragment.
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
 * GM3D selection mask fragment shader (shared by static and skinned mask).
 * Solid white: the edge pass thresholds on luminance, so shaded occluders
 * rendered with their own materials stay below the white level while the
 * selection is exactly 1.0.
 */

void main()
{
    gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);
}

