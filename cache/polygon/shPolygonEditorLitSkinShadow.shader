////////////////////////////////////////////////////////////////////////////////
//
// Vertex shader for skinned (animated) shadow geometry.
//
// Blends bone matrices from a uniform array, transforms vertex position to
// directional shadow-map clip space, and passes texture coordinates for
// alpha-cutout evaluation.
//
// Ported from YoYoGames/GM3D-Samples (develop branch, shAnimatedShadow).
//
////////////////////////////////////////////////////////////////////////////////

#define MAX_BONES 128

// Attributes
attribute vec3 in_Position;
attribute vec2 in_TextureCoord;
attribute vec4 in_BlendWeight;
attribute vec4 in_BlendIndices;

// Uniforms
uniform mat4 gm_BoneMatrices[MAX_BONES];

// Varyings
varying vec2 vTexCoord;

void main()
{
	// Skin weights
	int j0 = int(in_BlendIndices.x + 0.5);
	int j1 = int(in_BlendIndices.y + 0.5);
	int j2 = int(in_BlendIndices.z + 0.5);
	int j3 = int(in_BlendIndices.w + 0.5);

	mat4 skin = gm_BoneMatrices[j0] * in_BlendWeight.x
		+ gm_BoneMatrices[j1] * in_BlendWeight.y
		+ gm_BoneMatrices[j2] * in_BlendWeight.z
		+ gm_BoneMatrices[j3] * in_BlendWeight.w;

	gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * skin * vec4(in_Position, 1.0);
	vTexCoord = in_TextureCoord;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
////////////////////////////////////////////////////////////////////////////////
//
// Fragment shader for skinned (animated) shadow geometry.
//
// Discards masked fragments and writes raster depth into the shadow map.
//
// Ported from YoYoGames/GM3D-Samples (develop branch, shAnimatedShadow).
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

