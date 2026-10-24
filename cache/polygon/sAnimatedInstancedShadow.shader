////////////////////////////////////////////////////////////////////////////////
//
// Vertex shader for instanced skinned (animated) shadow geometry.
//
// Reads a per-instance world matrix and bone matrices from the atlas, then
// transforms vertex position to directional shadow-map clip space. Passes
// texture coordinates for alpha-cutout evaluation.
//
////////////////////////////////////////////////////////////////////////////////

#define MAX_BONES 128

// Attributes
attribute vec3 in_Position;
attribute vec2 in_TextureCoord;
attribute vec4 in_BlendWeight;
attribute vec4 in_BlendIndices;
attribute vec4 in_InstanceMatrixCol0;
attribute vec4 in_InstanceMatrixCol1;
attribute vec4 in_InstanceMatrixCol2;
attribute vec4 in_InstanceMatrixCol3;
attribute float in_BoneAtlasRow;

// Uniforms
uniform sampler2D gm_BoneAtlas;
uniform float gm_BoneAtlasHeight;

// Varyings
varying vec2 vTexCoord;

// Reads a 4x4 bone matrix from the bone atlas texture for the current instance
// row.
mat4 fetchBone(int boneIndex)
{
	float v = (in_BoneAtlasRow + 0.5) / gm_BoneAtlasHeight;
	float w = float(MAX_BONES * 4);
	return mat4(
		texture2D(gm_BoneAtlas, vec2((float(boneIndex * 4) + 0.5) / w, v)),
		texture2D(gm_BoneAtlas, vec2((float(boneIndex * 4 + 1) + 0.5) / w, v)),
		texture2D(gm_BoneAtlas, vec2((float(boneIndex * 4 + 2) + 0.5) / w, v)),
		texture2D(gm_BoneAtlas, vec2((float(boneIndex * 4 + 3) + 0.5) / w, v))
	);
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
	mat4 skin = fetchBone(int(in_BlendIndices.x + 0.5)) * in_BlendWeight.x
		+ fetchBone(int(in_BlendIndices.y + 0.5)) * in_BlendWeight.y
		+ fetchBone(int(in_BlendIndices.z + 0.5)) * in_BlendWeight.z
		+ fetchBone(int(in_BlendIndices.w + 0.5)) * in_BlendWeight.w;

	gl_Position = gm_Matrices[MATRIX_PROJECTION] * gm_Matrices[MATRIX_VIEW] * world * skin * vec4(in_Position, 1.0);
	vTexCoord = in_TextureCoord;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
////////////////////////////////////////////////////////////////////////////////
//
// Fragment shader for instanced skinned (animated) shadow geometry.
//
// Discards masked fragments and writes raster depth into the shadow map.
//
////////////////////////////////////////////////////////////////////////////////

// Varyings
varying vec2 vTexCoord;

// Material uniforms
uniform vec4 gm_BaseColorFactor;
uniform int gm_AlphaMode;
uniform float gm_AlphaCutoff;

void main()
{
	if (gm_AlphaMode == 1 && texture2D(gm_BaseTexture, vTexCoord).a * gm_BaseColorFactor.a < gm_AlphaCutoff) {
		discard;
	}
	gl_FragColor = vec4(gl_FragCoord.z);
}

