////////////////////////////////////////////////////////////////////////////////
//
// Vertex shader for unlit (flat) geometry, static and skinned.
//
// u_skinned selects the skinning path (bone matrices); static meshes ignore
// the bone attributes and take the direct path.
//
////////////////////////////////////////////////////////////////////////////////

#define MAX_BONES 128

// Attributes
attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;
attribute vec4 in_BlendWeight;
attribute vec4 in_BlendIndices;

// Uniforms
uniform mat4 gm_BoneMatrices[MAX_BONES];
uniform float u_skinned;

// Varyings
varying vec4 vColor;
varying vec2 vTexCoord;

void main()
{
	vec4 p = vec4(in_Position, 1.0);
	if (u_skinned > 0.5) {
		int j0 = int(in_BlendIndices.x + 0.5);
		int j1 = int(in_BlendIndices.y + 0.5);
		int j2 = int(in_BlendIndices.z + 0.5);
		int j3 = int(in_BlendIndices.w + 0.5);

		mat4 skin = gm_BoneMatrices[j0] * in_BlendWeight.x
			+ gm_BoneMatrices[j1] * in_BlendWeight.y
			+ gm_BoneMatrices[j2] * in_BlendWeight.z
			+ gm_BoneMatrices[j3] * in_BlendWeight.w;

		p = skin * p;
	}

	gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * p;
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

