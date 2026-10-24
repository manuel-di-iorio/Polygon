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
// SMAA 1x edge detection for the editor viewport (first pass).
//
// Faithful GLSL ES 1.00 port of SMAAColorEdgeDetectionPS from SMAA.hlsl
// (SMAA 1x HIGH preset: threshold 0.1, predication off). Vertex-computed
// offsets are inlined here: GameMaker targets GLSL ES, where varying/
// parameter arrays are unreliable, so all taps derive from v_vTexcoord.
//
// Outputs detected edges in R (vertical edge) and G (horizontal edge).
// Pixels without edges are discarded.
//
// SMAA by Jorge Jimenez, Jose I. Echevarria, Belen Masia,
// Fernando Navarro and Diego Gutierrez (MIT license, (c) 2013).
// LUT data: iryoku/smaa (same license, same authors).
//
////////////////////////////////////////////////////////////////////////////////

varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform vec2 u_texel; // 1 / source size

#define SMAA_THRESHOLD 0.1
#define SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR 2.0

void main()
{
    vec2 texcoord = v_vTexcoord;
    vec2 tx = u_texel;
    vec3 C = texture2D(gm_BaseTexture, texcoord).rgb;

    vec3 Cleft = texture2D(gm_BaseTexture, texcoord + vec2(-tx.x, 0.0)).rgb;
    vec3 t = abs(C - Cleft);
    float dx = max(max(t.r, t.g), t.b);

    vec3 Ctop = texture2D(gm_BaseTexture, texcoord + vec2(0.0, -tx.y)).rgb;
    t = abs(C - Ctop);
    float dy = max(max(t.r, t.g), t.b);

    vec2 edges = step(vec2(SMAA_THRESHOLD), vec2(dx, dy));

    if (dot(edges, vec2(1.0, 1.0)) == 0.0) discard;

    vec3 Cright = texture2D(gm_BaseTexture, texcoord + vec2(tx.x, 0.0)).rgb;
    t = abs(C - Cright);
    float dx2 = max(max(t.r, t.g), t.b);

    vec3 Cbottom = texture2D(gm_BaseTexture, texcoord + vec2(0.0, tx.y)).rgb;
    t = abs(C - Cbottom);
    float dy2 = max(max(t.r, t.g), t.b);

    vec2 maxDelta = max(vec2(dx, dy), vec2(dx2, dy2));

    vec3 Cleftleft = texture2D(gm_BaseTexture, texcoord + vec2(-2.0 * tx.x, 0.0)).rgb;
    t = abs(C - Cleftleft);
    dx2 = max(max(t.r, t.g), t.b);

    vec3 Ctoptop = texture2D(gm_BaseTexture, texcoord + vec2(0.0, -2.0 * tx.y)).rgb;
    t = abs(C - Ctoptop);
    dy2 = max(max(t.r, t.g), t.b);

    maxDelta = max(maxDelta, vec2(dx2, dy2));
    float finalDelta = max(maxDelta.x, maxDelta.y);

    edges = edges * step(vec2(finalDelta), vec2(SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR) * vec2(dx, dy));

    gl_FragColor = vec4(edges, 0.0, 1.0);
}

