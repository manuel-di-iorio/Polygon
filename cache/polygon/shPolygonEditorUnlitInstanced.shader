////////////////////////////////////////////////////////////////////////////////
//
// Vertex shader for unlit (flat) instanced static geometry.
//
// Reads a per-instance world matrix from vertex attributes.
//
////////////////////////////////////////////////////////////////////////////////

// Attributes
attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;

// Per-instance attributes
attribute vec4 in_InstanceMatrixCol0;
attribute vec4 in_InstanceMatrixCol1;
attribute vec4 in_InstanceMatrixCol2;
attribute vec4 in_InstanceMatrixCol3;

// Varyings
varying vec4 vColor;
varying vec2 vTexCoord;

void main()
{
	// Instance world matrix
	mat4 world = mat4(
		in_InstanceMatrixCol0,
		in_InstanceMatrixCol1,
		in_InstanceMatrixCol2,
		in_InstanceMatrixCol3
	);

	vec4 worldPos = world * vec4(in_Position, 1.0);

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

