////////////////////////////////////////////////////////////////////////////////
//
// Vertex shader for unlit (flat) instanced skinned geometry.
//
// Reads a per-instance world matrix and blends bone matrices sampled from
// a texture atlas.
//
////////////////////////////////////////////////////////////////////////////////

#define MAX_BONES 128

// Attributes
attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;
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
varying vec4 vColor;
varying vec2 vTexCoord;

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
	vec4 worldPos = world * p;

	gl_Position = gm_Matrices[MATRIX_PROJECTION] * gm_Matrices[MATRIX_VIEW] * worldPos;
	vColor = in_Colour;
	vTexCoord = in_TextureCoord;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
////////////////////////////////////////////////////////////////////////////////
//
// Fragment shader for unlit (flat) geometry.
//
// Flat mid-gray output preserving base alpha (cutout/blend). No lighting,
// no fog, no shadows.
//
////////////////////////////////////////////////////////////////////////////////

// Varyings
varying vec4 vColor;
varying vec2 vTexCoord;

// Material uniforms
uniform vec4 gm_BaseColorFactor;
uniform vec2 gm_BaseTexture_Offset;
uniform vec2 gm_BaseTexture_Scale;
uniform float gm_BaseTexture_Rotation;

// Alpha mode: 0 = OPAQUE, 1 = MASK, 2 = BLEND
uniform int gm_AlphaMode;
uniform float gm_AlphaCutoff;

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
	vec2 baseUV = transformTexCoord(
		vTexCoord,
		gm_BaseTexture_Offset,
		gm_BaseTexture_Scale,
		gm_BaseTexture_Rotation
	);
	vec4 baseColor = gm_BaseColorFactor * vColor * texture2D(gm_BaseTexture, baseUV);
	float outputAlpha = (gm_AlphaMode == 2) ? baseColor.a : 1.0;

	if (gm_AlphaMode == 1 && baseColor.a < gm_AlphaCutoff) {
		discard;
	}

	gl_FragColor = vec4(baseColor.rgb, outputAlpha);
}

