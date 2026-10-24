////////////////////////////////////////////////////////////////////////////////
//
// Vertex shader for skydome background.
//
// Passes object-space direction through; the dome node is positioned at the
// camera each step, so object direction equals view direction.
//
////////////////////////////////////////////////////////////////////////////////

// Attributes
attribute vec3 in_Position;

// Varyings
varying vec3 vDir;

void main()
{
	vDir = in_Position;
	gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * vec4(in_Position, 1.0);
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
////////////////////////////////////////////////////////////////////////////////
//
// Fragment shader for skydome background.
//
// Vertical gradient (top / horizon / bottom) plus sun glow disk.
// Unlit, no fog, no shadows, opaque.
//
// Day/night cycle derived from the sun direction Y component (elevation):
//   sunElev > 0.25  -> full day
//   sunElev ~ 0     -> sunset / sunrise
//   sunElev < -0.15 -> full night
//
////////////////////////////////////////////////////////////////////////////////

// Varyings
varying vec3 vDir;

// Gradient exponents
#define SKY_TOP_POW 0.6
#define SKY_BOT_BLEND 0.05

// Sky uniforms – u_skyTop/Horizon/Bottom are the base DAY palette.
uniform vec3 u_skyTop;
uniform vec3 u_skyHorizon;
uniform vec3 u_skyBottom;
uniform vec3 u_sunDir;
uniform vec3 u_sunColor;
uniform float u_sunGlow;

void main()
{
	vec3 d = normalize(vDir);

	// Normalize sun direction.
	vec3 sd = u_sunDir;
	float sl = length(sd);
	sd = sl > 0.0001 ? sd / sl : vec3(0.0, 1.0, 0.0);

	// Sun elevation: +1 = zenith, 0 = horizon, -1 = nadir.
	float sunElev = sd.y;

	// =====================================================================
	// Palette blending: day -> sunset -> night
	// =====================================================================

	vec3 dayTop     = u_skyTop;
	vec3 dayHorizon = u_skyHorizon;
	vec3 dayBottom  = u_skyBottom;

	// Sunset / sunrise – realistic warm tones:
	//   upper sky fades to deep indigo,
	//   horizon glows soft peach-pink,
	//   ground darkens to a warm neutral.
	vec3 sunsetTop     = vec3(0.10, 0.08, 0.25);
	vec3 sunsetHorizon = vec3(0.95, 0.55, 0.35);
	vec3 sunsetBottom  = vec3(0.15, 0.10, 0.08);

	// Night – very deep dark blue.
	vec3 nightTop     = vec3(0.005, 0.006, 0.04);
	vec3 nightHorizon = vec3(0.010, 0.014, 0.05);
	vec3 nightBottom  = vec3(0.003, 0.003, 0.012);

	float tSunset = smoothstep(0.25, 0.0, sunElev);
	float tNight  = smoothstep(-0.05, -0.20, sunElev);

	vec3 skyTop     = mix(mix(dayTop,     sunsetTop,     tSunset), nightTop,     tNight);
	vec3 skyHorizon = mix(mix(dayHorizon, sunsetHorizon, tSunset), nightHorizon, tNight);
	vec3 skyBottom  = mix(mix(dayBottom,  sunsetBottom,  tSunset), nightBottom,  tNight);

	// Sky gradient.
	vec3 col = d.y >= 0.0
		? mix(skyHorizon, skyTop, pow(d.y, SKY_TOP_POW))
		: mix(skyHorizon, skyBottom, smoothstep(0.0, SKY_BOT_BLEND, -d.y));

	// Sun visibility attenuator (fades to zero below horizon).
	float sunVis = clamp(sunElev * 8.0 + 0.5, 0.0, 1.0);

	// =====================================================================
	// Sun – fixed-size small disk + warm halo (halo grows at sunset).
	// The disk size is angularly constant (independent of sun elevation)
	// so the sun does not appear to grow between sunrise and midday.
	// =====================================================================
	float s = dot(d, sd);

	// Approximate angular distance from sun center:
	//   theta ≈ acos(s) ≈ sqrt(2(1-s))   for s close to 1
	// We just use (1-s) directly as a monotonic proxy for thresholding.
	float sunAng = 1.0 - clamp(s, -1.0, 1.0);

	// Sun disk – clearly visible small disk, angularly constant, game-sized.
	const float SUN_RADIUS = 0.00045;
	const float SUN_EDGE   = 0.00018;
	float disk = (1.0 - smoothstep(SUN_RADIUS, SUN_RADIUS + SUN_EDGE, sunAng));
	// Make disk 12% brighter for a clear bloom-like core.
	float diskBright = 1.12;

	// Halo – warm glow. Only the halo grows at sunset (atmospheric
	// scattering illusion); the hard disk remains fixed size.
	float sPos = max(s, 0.0);
	float haloTight  = pow(sPos, 220.0) * 0.20;
	float haloLoose  = pow(sPos, 40.0)  * 0.06;
	vec3  haloCol    = vec3(1.0, 0.84, 0.36);
	vec3  halo       = (haloTight + haloLoose) * haloCol;

	// Warm sky tint close to the sun – stronger near horizon (sunset).
	float warmthPow = mix(32.0, 18.0, tSunset);
	float warmthAmp = mix(0.22, 0.38, tSunset);
	float warmth    = pow(sPos, warmthPow) * warmthAmp * u_sunGlow * sunVis;
	col = mix(col, vec3(1.0, 0.86, 0.42), warmth);

	// Composite: disk uses u_sunColor as tint (so artist can tweak),
	// halo is pre-tinted above.
	col += u_sunColor * disk * diskBright * u_sunGlow * sunVis;
	col += u_sunColor * halo * u_sunGlow * sunVis;

	gl_FragColor = vec4(col, 1.0);
}

