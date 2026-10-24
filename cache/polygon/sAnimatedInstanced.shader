////////////////////////////////////////////////////////////////////////////////
//
// Vertex shader for instanced skinned (animated) geometry.
//
// Reads a per-instance world matrix from vertex attributes and blends bone
// matrices sampled from a texture atlas to skin vertex position and TBN frame,
// then transforms to world space. Computes fog factor passed to the fragment
// stage.
//
////////////////////////////////////////////////////////////////////////////////

#define MAX_BONES 128

// Attributes
attribute vec3 in_Position;
attribute vec3 in_Normal;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;
attribute vec4 in_Tangent;
attribute vec4 in_BlendWeight;
attribute vec4 in_BlendIndices;

// Per-instance attributes
attribute vec4 in_InstanceMatrixCol0;
attribute vec4 in_InstanceMatrixCol1;
attribute vec4 in_InstanceMatrixCol2;
attribute vec4 in_InstanceMatrixCol3;
attribute float in_BoneAtlasRow;

// Uniforms
uniform sampler2D gm_BoneAtlas;
uniform float gm_BoneAtlasHeight;

// Varyings
varying vec3 vT;
varying vec3 vN;
varying float vSign;
varying float vHasTangent;

varying vec4 vColor;
varying vec2 vTexCoord;
varying vec3 vWorldPosition;
varying vec3 vShadowWorldPosition;
varying float vFogFactor;

uniform float gm_ShadowNormalOffset;

// Computes world-space tangent and normal.
void buildTBN(
	vec4 tangent, vec3 normal, mat3 xformMat3,
	out vec3 outT, out vec3 outN, out float outHasTangent
) {
	outHasTangent = (dot(tangent, tangent) > 0.0) ? 1.0 : 0.0;
	outT = xformMat3 * tangent.xyz;
	outN = xformMat3 * normal;
	outN = normalize(outN);
	outT = normalize(outT);
	outT = normalize(outT - outN * dot(outT, outN));
}

// Reads a 4x4 bone matrix from the bone atlas texture for the current instance
// row.
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
	// Instance world matrix
	mat4 world = mat4(
		in_InstanceMatrixCol0,
		in_InstanceMatrixCol1,
		in_InstanceMatrixCol2,
		in_InstanceMatrixCol3
	);

	// Skin weights
	int j0 = int(in_BlendIndices.x + 0.5);
	int j1 = int(in_BlendIndices.y + 0.5);
	int j2 = int(in_BlendIndices.z + 0.5);
	int j3 = int(in_BlendIndices.w + 0.5);

	mat4 skin = fetchBone(j0) * in_BlendWeight.x
		+ fetchBone(j1) * in_BlendWeight.y
		+ fetchBone(j2) * in_BlendWeight.z
		+ fetchBone(j3) * in_BlendWeight.w;

	vec4 p = skin * vec4(in_Position, 1.0);

	// TBN frame
	buildTBN(
		in_Tangent, in_Normal,
		mat3(world) * mat3(skin),
		vT, vN, vHasTangent
	);
	vSign = in_Tangent.w;

	// Output
	vec4 worldPos = world * p;
	vWorldPosition = worldPos.xyz;
	vShadowWorldPosition = vWorldPosition + vN * gm_ShadowNormalOffset;

	gl_Position = gm_Matrices[MATRIX_PROJECTION] * gm_Matrices[MATRIX_VIEW] * worldPos;
	float fogEnable = gm_VS_FogEnabled ? 1.0 : 0.0;
	vFogFactor = fogEnable * (gl_Position.w - gm_FogStart) * gm_RcpFogRange;
	vColor = in_Colour;
	vTexCoord = in_TextureCoord;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
////////////////////////////////////////////////////////////////////////////////
//
// Fragment shader for instanced skinned (animated) geometry.
//
// Applies Lambert diffuse lighting (directional + point lights), texture
// coordinate transformation, alpha cutout/blend, and linear fog.
//
////////////////////////////////////////////////////////////////////////////////

#define MAX_LIGHTS 8

// Varyings from vertex shader
varying vec3 vT;
varying vec3 vN;
varying float vSign;
varying float vHasTangent;
varying vec4 vColor;
varying vec2 vTexCoord;
varying vec3 vWorldPosition;
varying vec3 vShadowWorldPosition;
varying float vFogFactor;

// Material uniforms
uniform vec4 gm_BaseColorFactor;
uniform vec2 gm_BaseTexture_Offset;
uniform vec2 gm_BaseTexture_Scale;
uniform float gm_BaseTexture_Rotation;

// Alpha mode: 0 = OPAQUE, 1 = MASK, 2 = BLEND
uniform int gm_AlphaMode;
uniform float gm_AlphaCutoff;

// Lighting uniforms
uniform vec4 gm_AmbientColour;
uniform vec4 gm_Lights_Direction[MAX_LIGHTS]; // xyz = direction toward scene, w = enabled (1) or disabled (0)
uniform vec4 gm_Lights_PosRange[MAX_LIGHTS];  // xyz = world position, w = range (0 = disabled)
uniform vec4 gm_Lights_Colour[MAX_LIGHTS];    // rgb = colour
uniform int gm_ShadowLightIndex;
uniform int gm_ReceiveShadows;
uniform vec2 gm_ShadowFadeRange;
uniform vec3 gm_CameraPosition;
uniform mat4 gm_ShadowWorldToAtlas;
uniform vec2 gm_ShadowTexelSize;
uniform sampler2D gm_ShadowAtlas;

// Samples one shadow-map texel with out-of-bounds coordinates treated as lit.
float sampleShadowTexel(vec2 texelPosition, float receiverDepth)
{
	vec2 sampleUV = (texelPosition + 0.5) * gm_ShadowTexelSize;
	if (sampleUV.x <= 0.0 || sampleUV.x >= 1.0 || sampleUV.y <= 0.0 || sampleUV.y >= 1.0) return 1.0;
	return receiverDepth <= texture2D(gm_ShadowAtlas, sampleUV).r ? 1.0 : 0.0;
}

// Interpolates filtered visibility from the surrounding shadow-map texels.
float sampleShadowBilinear(vec2 texelPosition, float receiverDepth)
{
	vec2 baseTexel = floor(texelPosition);
	vec2 texelFraction = fract(texelPosition);
	float lower = mix(
		sampleShadowTexel(baseTexel, receiverDepth),
		sampleShadowTexel(baseTexel + vec2(1.0, 0.0), receiverDepth),
		texelFraction.x
	);
	float upper = mix(
		sampleShadowTexel(baseTexel + vec2(0.0, 1.0), receiverDepth),
		sampleShadowTexel(baseTexel + vec2(1.0, 1.0), receiverDepth),
		texelFraction.x
	);
	return mix(lower, upper, texelFraction.y);
}

// Calculates filtered visibility for a world-space position in the shadow map.
float sampleDirectionalShadow(vec3 shadowWorldPosition)
{
	vec4 shadowPosition = gm_ShadowWorldToAtlas * vec4(shadowWorldPosition, 1.0);
	vec3 shadowCoord = shadowPosition.xyz / shadowPosition.w;
	if (shadowCoord.x <= 0.0 || shadowCoord.x >= 1.0 || shadowCoord.y <= 0.0 || shadowCoord.y >= 1.0 || shadowCoord.z <= 0.0 || shadowCoord.z >= 1.0) return 1.0;
	vec2 texelPosition = shadowCoord.xy / gm_ShadowTexelSize - 0.5;
	float visibility = 0.0;
	float totalWeight = 0.0;
	for (int y = -1; y <= 1; ++y) {
		float yWeight = y == 0 ? 2.0 : 1.0;
		for (int x = -1; x <= 1; ++x) {
			float xWeight = x == 0 ? 2.0 : 1.0;
			float weight = xWeight * yWeight;
			visibility += sampleShadowBilinear(texelPosition + vec2(float(x), float(y)), shadowCoord.z) * weight;
			totalWeight += weight;
		}
	}
	return visibility / totalWeight;
}

// Fades directional shadowing to fully lit at the camera coverage boundary.
float getDirectionalShadowFade(vec3 worldPosition)
{
	return smoothstep(gm_ShadowFadeRange.x, gm_ShadowFadeRange.y, length(worldPosition - gm_CameraPosition));
}

// Applies offset, scale, and optional rotation to a UV coordinate.
vec2 transformTexCoord(vec2 uv, vec2 offset, vec2 scale, float rotation)
{
	vec2 transformed = uv * scale + offset;
	if (rotation != 0.0) {
		float s = sin(rotation);
		float c = cos(rotation);
		mat2 rotMat = mat2(c, s, -s, c);
		transformed = rotMat * (transformed - 0.5) + 0.5;
	}
	return transformed;
}

void main()
{
	// Base color
	vec2 baseUV = transformTexCoord(
		vTexCoord,
		gm_BaseTexture_Offset,
		gm_BaseTexture_Scale,
		gm_BaseTexture_Rotation
	);
	vec4 baseTexture = texture2D(gm_BaseTexture, baseUV);
	vec4 baseColor = gm_BaseColorFactor * vColor * baseTexture;
	float outputAlpha = (gm_AlphaMode == 2) ? baseColor.a : 1.0;

	if (gm_AlphaMode == 1 && baseColor.a < gm_AlphaCutoff) {
		discard;
	}

	vec3 N = normalize(vN);

	// Ambient
	vec3 light = gm_AmbientColour.rgb;

	// Directional lights
	for (int i = 0; i < MAX_LIGHTS; ++i) {
		vec3 L = -gm_Lights_Direction[i].xyz;
		if (dot(L, L) > 0.0001) {
			float NdotL = max(0.0, dot(N, normalize(L)));
			float shadow = 1.0;
			if (i == gm_ShadowLightIndex && gm_ReceiveShadows != 0) {
				shadow = mix(
					sampleDirectionalShadow(vShadowWorldPosition),
					1.0,
					getDirectionalShadowFade(vWorldPosition)
				);
			}
			light += NdotL * shadow * gm_Lights_Colour[i].rgb;
		}
	}

	// Point lights
	for (int i = 0; i < MAX_LIGHTS; ++i) {
		float range = gm_Lights_PosRange[i].w;
		if (range > 0.0) {
			vec3 toLight = gm_Lights_PosRange[i].xyz - vWorldPosition;
			float dist = length(toLight);
			float NdotL = max(0.0, dot(N, toLight / dist));
			float attenuation = clamp(1.0 - dist / range, 0.0, 1.0);
			light += NdotL * attenuation * gm_Lights_Colour[i].rgb;
		}
	}

	// Fog and output
	vec3 litColor = baseColor.rgb * light;
	float fogBlend = gm_PS_FogEnabled ? clamp(vFogFactor, 0.0, 1.0) : 0.0;
	litColor = mix(litColor, gm_FogColour.rgb, fogBlend);
	gl_FragColor = vec4(litColor, outputAlpha);
}

