////////////////////////////////////////////////////////////////////////////////
//
// SMAA 1x blending weight calculation for the editor viewport (second pass).
//
// Faithful GLSL ES 1.00 port of SMAABlendingWeightCalculationPS from
// SMAA.hlsl (HIGH preset: 16 search steps, 8 diag steps, corner rounding
// 25, no predication, no reprojection, subsample zero). Adaptations for
// GLSL ES: vertex offsets inlined (no varying arrays), while loops turned
// into bounded for loops with identical visit order, round() spelled as
// floor(x + 0.5), per-lane moves spelled as branches.
//
// gm_BaseTexture is the edge buffer (R/G from the edge pass).
// u_areaTex (160x560 RG) and u_searchTex (64x16 R) are the official SMAA
// LUTs, loaded at runtime from datafiles/__PolygonEditor__/smaa/.
// Outputs horizontal weights in R/G and vertical weights in B/A.
//
// SMAA by Jorge Jimenez, Jose I. Echevarria, Belen Masia,
// Fernando Navarro and Diego Gutierrez (MIT license, (c) 2013).
// LUT data: iryoku/smaa (same license, same authors).
//
////////////////////////////////////////////////////////////////////////////////

varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform vec2 u_texel; // 1 / edges buffer size
uniform sampler2D u_areaTex;
uniform sampler2D u_searchTex;

#define SMAA_MAX_SEARCH_STEPS 16
#define SMAA_MAX_SEARCH_STEPS_DIAG 8
#define SMAA_CORNER_ROUNDING_NORM (25.0 / 100.0)

// Decodes two binary edge values from one bilinear-filtered access.
vec2 smaaDecodeDiag(vec2 e) {
    e.r = e.r * abs(5.0 * e.r - 5.0 * 0.75);
    return floor(e + 0.5);
}

vec4 smaaDecodeDiag4(vec4 e) {
    e.rb = e.rb * abs(5.0 * e.rb - 5.0 * 0.75);
    return floor(e + 0.5);
}

// Diagonal area for a distance and crossing edges.
vec2 smaaAreaDiag(vec2 dist, vec2 e, float offset) {
    vec2 texcoord = vec2(20.0) * e + dist;
    vec2 px = vec2(1.0 / 160.0, 1.0 / 560.0);
    texcoord = px * texcoord + 0.5 * px;
    texcoord.x = texcoord.x + 0.5;
    texcoord.y = texcoord.y + (1.0 / 7.0) * offset;
    return texture2D(u_areaTex, texcoord).rg;
}

// Diagonal pattern searches (out e holds the last fetched edges).
vec2 smaaSearchDiag1(vec2 texcoord, vec2 dir, out vec2 e) {
    vec4 coord = vec4(texcoord, -1.0, 1.0);
    vec3 t = vec3(u_texel, 1.0);
    for (int i = 0; i < 7; i++) {
        if (!(coord.z < 7.0 && coord.w > 0.9)) break;
        coord.xyz = t * vec3(dir, 1.0) + coord.xyz;
        e = texture2D(gm_BaseTexture, coord.xy).rg;
        coord.w = dot(e, vec2(0.5, 0.5));
    }
    return coord.zw;
}

vec2 smaaSearchDiag2(vec2 texcoord, vec2 dir, out vec2 e) {
    vec4 coord = vec4(texcoord, -1.0, 1.0);
    coord.x = coord.x + 0.25 * u_texel.x;
    vec3 t = vec3(u_texel, 1.0);
    for (int i = 0; i < 7; i++) {
        if (!(coord.z < 7.0 && coord.w > 0.9)) break;
        coord.xyz = t * vec3(dir, 1.0) + coord.xyz;
        e = texture2D(gm_BaseTexture, coord.xy).rg;
        e = smaaDecodeDiag(e);
        coord.w = dot(e, vec2(0.5, 0.5));
    }
    return coord.zw;
}

// Diagonal weights for the current pixel (1x: no subsample offset).
vec2 smaaDiagWeights(vec2 texcoord, vec2 e) {
    vec2 weights = vec2(0.0, 0.0);
    vec4 d;
    vec2 end;
    if (e.r > 0.0) {
        vec2 sd = smaaSearchDiag1(texcoord, vec2(-1.0, 1.0), end);
        d.x = sd.x;
        d.z = sd.y;
        d.x = d.x + float(end.y > 0.9);
    } else {
        d.x = 0.0;
        d.z = 0.0;
    }
    vec2 sd = smaaSearchDiag1(texcoord, vec2(1.0, -1.0), end);
    d.y = sd.x;
    d.w = sd.y;

    if (d.x + d.y > 2.0) {
        vec4 coords = vec4(-d.x + 0.25, d.x, d.y, -d.y - 0.25) * u_texel.xyxy + texcoord.xyxy;
        vec4 c;
        c.xy = texture2D(gm_BaseTexture, coords.xy + vec2(-1.0, 0.0) * u_texel).rg;
        c.zw = texture2D(gm_BaseTexture, coords.zw + vec2(1.0, 0.0) * u_texel).rg;
        vec4 cd = smaaDecodeDiag4(c);
        c = vec4(cd.y, cd.x, cd.w, cd.z);
        vec2 cc = vec2(2.0) * c.xz + c.yw;
        if (d.z >= 0.9) cc.x = 0.0;
        if (d.w >= 0.9) cc.y = 0.0;
        weights = weights + smaaAreaDiag(d.xy, cc, 0.0);
    }

    vec2 sd3 = smaaSearchDiag2(texcoord, vec2(-1.0, -1.0), end);
    d.x = sd3.x;
    d.z = sd3.y;
    if (texture2D(gm_BaseTexture, texcoord + vec2(1.0, 0.0) * u_texel).r > 0.0) {
        vec2 sd4 = smaaSearchDiag2(texcoord, vec2(1.0, 1.0), end);
        d.y = sd4.x;
        d.w = sd4.y;
        d.y = d.y + float(end.y > 0.9);
    } else {
        d.y = 0.0;
        d.w = 0.0;
    }

    if (d.x + d.y > 2.0) {
        vec4 coords = vec4(-d.x, -d.x, d.y, d.y) * u_texel.xyxy + texcoord.xyxy;
        vec4 c;
        c.x = texture2D(gm_BaseTexture, coords.xy + vec2(-1.0, 0.0) * u_texel).g;
        c.y = texture2D(gm_BaseTexture, coords.xy + vec2(0.0, -1.0) * u_texel).r;
        c.zw = texture2D(gm_BaseTexture, coords.zw + vec2(1.0, 0.0) * u_texel).gr;
        vec2 cc = vec2(2.0) * c.xz + c.yw;
        if (d.z >= 0.9) cc.x = 0.0;
        if (d.w >= 0.9) cc.y = 0.0;
        weights = weights + smaaAreaDiag(d.xy, cc, 0.0).yx;
    }

    return weights;
}

// Length correction for the last search step (official search texture).
float smaaSearchLength(vec2 e, float offset) {
    vec2 scale = vec2(66.0, 33.0) * vec2(0.5, -1.0);
    vec2 bias = vec2(66.0, 33.0) * vec2(offset, 1.0);
    scale = scale + vec2(-1.0, 1.0);
    bias = bias + vec2(0.5, -0.5);
    scale = scale / vec2(64.0, 16.0);
    bias = bias / vec2(64.0, 16.0);
    return texture2D(u_searchTex, scale * e + bias).r;
}

// Horizontal/vertical searches (bounded loops, reference visit order).
float smaaSearchXLeft(vec2 texcoord, float end) {
    vec2 e = vec2(0.0, 1.0);
    for (int i = 0; i < 16; i++) {
        if (!(texcoord.x > end && e.g > 0.8281 && e.r == 0.0)) break;
        e = texture2D(gm_BaseTexture, texcoord).rg;
        texcoord = texcoord - vec2(2.0, 0.0) * u_texel;
    }
    float offset = 3.25 - (255.0 / 127.0) * smaaSearchLength(e, 0.0);
    return texcoord.x + u_texel.x * offset;
}

float smaaSearchXRight(vec2 texcoord, float end) {
    vec2 e = vec2(0.0, 1.0);
    for (int i = 0; i < 16; i++) {
        if (!(texcoord.x < end && e.g > 0.8281 && e.r == 0.0)) break;
        e = texture2D(gm_BaseTexture, texcoord).rg;
        texcoord = texcoord + vec2(2.0, 0.0) * u_texel;
    }
    float offset = 3.25 - (255.0 / 127.0) * smaaSearchLength(e, 0.5);
    return texcoord.x - u_texel.x * offset;
}

float smaaSearchYUp(vec2 texcoord, float end) {
    vec2 e = vec2(1.0, 0.0);
    for (int i = 0; i < 16; i++) {
        if (!(texcoord.y > end && e.r > 0.8281 && e.g == 0.0)) break;
        e = texture2D(gm_BaseTexture, texcoord).rg;
        texcoord = texcoord - vec2(0.0, 2.0) * u_texel;
    }
    float offset = 3.25 - (255.0 / 127.0) * smaaSearchLength(e.gr, 0.0);
    return texcoord.y + u_texel.y * offset;
}

float smaaSearchYDown(vec2 texcoord, float end) {
    vec2 e = vec2(1.0, 0.0);
    for (int i = 0; i < 16; i++) {
        if (!(texcoord.y < end && e.r > 0.8281 && e.g == 0.0)) break;
        e = texture2D(gm_BaseTexture, texcoord).rg;
        texcoord = texcoord + vec2(0.0, 2.0) * u_texel;
    }
    float offset = 3.25 - (255.0 / 127.0) * smaaSearchLength(e.gr, 0.5);
    return texcoord.y - u_texel.y * offset;
}

// Area for a distance and crossing edges (areas are stored quadratically).
vec2 smaaArea(vec2 dist, float e1, float e2, float offset) {
    vec2 texcoord = vec2(16.0) * floor(4.0 * vec2(e1, e2) + 0.5) + dist;
    vec2 px = vec2(1.0 / 160.0, 1.0 / 560.0);
    texcoord = px * texcoord + 0.5 * px;
    texcoord.y = texcoord.y + (1.0 / 7.0) * offset;
    return texture2D(u_areaTex, texcoord).rg;
}

// Corner rounding fixes.
void smaaCornerH(inout vec2 weights, vec4 texcoord, vec2 d) {
    vec2 leftRight = step(d.xy, d.yx);
    vec2 rounding = (1.0 - (25.0 / 100.0)) * leftRight;
    rounding = rounding / (leftRight.x + leftRight.y);
    vec2 factor = vec2(1.0, 1.0);
    factor.x = factor.x - rounding.x * texture2D(gm_BaseTexture, texcoord.xy + vec2(0.0, 1.0) * u_texel).r;
    factor.x = factor.x - rounding.y * texture2D(gm_BaseTexture, texcoord.zw + vec2(1.0, 1.0) * u_texel).r;
    factor.y = factor.y - rounding.x * texture2D(gm_BaseTexture, texcoord.xy + vec2(0.0, -2.0) * u_texel).r;
    factor.y = factor.y - rounding.y * texture2D(gm_BaseTexture, texcoord.zw + vec2(1.0, -2.0) * u_texel).r;
    weights = weights * clamp(factor, 0.0, 1.0);
}

void smaaCornerV(inout vec2 weights, vec4 texcoord, vec2 d) {
    vec2 leftRight = step(d.xy, d.yx);
    vec2 rounding = (1.0 - (25.0 / 100.0)) * leftRight;
    rounding = rounding / (leftRight.x + leftRight.y);
    vec2 factor = vec2(1.0, 1.0);
    factor.x = factor.x - rounding.x * texture2D(gm_BaseTexture, texcoord.xy + vec2(1.0, 0.0) * u_texel).g;
    factor.x = factor.x - rounding.y * texture2D(gm_BaseTexture, texcoord.zw + vec2(1.0, 1.0) * u_texel).g;
    factor.y = factor.y - rounding.x * texture2D(gm_BaseTexture, texcoord.xy + vec2(-2.0, 0.0) * u_texel).g;
    factor.y = factor.y - rounding.y * texture2D(gm_BaseTexture, texcoord.zw + vec2(-2.0, 1.0) * u_texel).g;
    weights = weights * clamp(factor, 0.0, 1.0);
}

void main()
{
    vec2 texcoord = v_vTexcoord;
    vec2 pixcoord = texcoord / u_texel;
    vec4 boff0 = vec4(-0.25, -0.125, 1.25, -0.125) * u_texel.xyxy + texcoord.xyxy;
    vec4 boff1 = vec4(-0.125, -0.25, -0.125, 1.25) * u_texel.xyxy + texcoord.xyxy;
    vec4 boff2 = vec4(-32.0, 32.0, -32.0, 32.0) * u_texel.xxyy + vec4(boff0.xz, boff1.yw);

    vec4 weights = vec4(0.0, 0.0, 0.0, 0.0);
    vec2 e = texture2D(gm_BaseTexture, texcoord).rg;

    if (e.g > 0.0) {
        weights.rg = smaaDiagWeights(texcoord, e);

        if (weights.r == -weights.g) {
            float xL = smaaSearchXLeft(boff0.xy, boff2.x);
            float yC = boff1.y;
            float e1 = texture2D(gm_BaseTexture, vec2(xL, yC)).r;

            float xR = smaaSearchXRight(boff0.zw, boff2.y);
            vec2 dd = abs(floor(vec2(1.0 / u_texel.x) * vec2(xL, xR) - pixcoord.xx + 0.5));
            vec2 sqrt_d = sqrt(dd);

            float e2 = texture2D(gm_BaseTexture, vec2(xR, yC) + vec2(1.0, 0.0) * u_texel).r;
            vec2 wh = smaaArea(sqrt_d, e1, e2, 0.0);
            vec4 ccoord = vec4(xL, texcoord.y, xR, texcoord.y);
            smaaCornerH(wh, ccoord, dd);
            weights.rg = wh;
        } else {
            e.r = 0.0;
        }
    }

    if (e.r > 0.0) {
        float yT = smaaSearchYUp(boff1.xy, boff2.z);
        float xC = boff0.x;
        float e1 = texture2D(gm_BaseTexture, vec2(xC, yT)).g;

        float yB = smaaSearchYDown(boff1.zw, boff2.w);
        vec2 dd = abs(floor(vec2(1.0 / u_texel.y) * vec2(yT, yB) - pixcoord.yy + 0.5));
        vec2 sqrt_d = sqrt(dd);

        float e2 = texture2D(gm_BaseTexture, vec2(xC, yB) + vec2(0.0, 1.0) * u_texel).g;
        vec2 wv = smaaArea(sqrt_d, e1, e2, 0.0);
        vec4 ccoord = vec4(texcoord.x, yT, texcoord.x, yB);
        smaaCornerV(wv, ccoord, dd);
        weights.ba = wv;
    }

    gl_FragColor = weights;
}
