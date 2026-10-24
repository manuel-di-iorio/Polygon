attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;

varying vec2 v_vTexcoord;
varying vec4 v_vColour;

void main()
{
    vec4 object_space_pos = vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * object_space_pos;
    v_vColour = in_Colour;
    v_vTexcoord = in_TextureCoord;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
////////////////////////////////////////////////////////////////////////////////
//
// SMAA 1x neighborhood blending for the editor viewport (third pass).
//
// Faithful GLSL ES 1.00 port of SMAANeighborhoodBlendingPS from SMAA.hlsl
// (no reprojection). gm_BaseTexture is the raw 1x 3D render, u_blendTex
// the weights from the blend pass (horizontal in R/G, vertical in B/A).
// Pixels with no weight are copied untouched.
//
// SMAA by Jorge Jimenez, Jose I. Echevarria, Belen Masia,
// Fernando Navarro and Diego Gutierrez (MIT license, (c) 2013).
//
////////////////////////////////////////////////////////////////////////////////

varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform vec2 u_texel; // 1 / source size
uniform sampler2D u_blendTex;

void main()
{
    vec2 texcoord = v_vTexcoord;
    vec4 offset = vec4(1.0, 0.0, 0.0, 1.0) * u_texel.xyxy + texcoord.xyxy;

    vec4 a;
    a.x = texture2D(u_blendTex, offset.xy).a;
    a.y = texture2D(u_blendTex, offset.zw).g;
    a.wz = texture2D(u_blendTex, texcoord).xz;

    if (dot(a, vec4(1.0, 1.0, 1.0, 1.0)) < 0.00001) {
        gl_FragColor = texture2D(gm_BaseTexture, texcoord);
        return;
    }

    bool h = max(a.x, a.z) > max(a.y, a.w);

    vec4 blendingOffset = vec4(0.0, a.y, 0.0, a.w);
    vec2 blendingWeight = a.yw;
    if (h) {
        blendingOffset = vec4(a.x, 0.0, a.z, 0.0);
        blendingWeight = a.xz;
    }
    blendingWeight = blendingWeight / dot(blendingWeight, vec2(1.0, 1.0));

    vec4 blendingCoord = blendingOffset * vec4(u_texel, -u_texel) + texcoord.xyxy;

    vec4 color = blendingWeight.x * texture2D(gm_BaseTexture, blendingCoord.xy);
    color = color + blendingWeight.y * texture2D(gm_BaseTexture, blendingCoord.zw);

    gl_FragColor = color;
}

