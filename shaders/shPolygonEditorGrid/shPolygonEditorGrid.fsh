////////////////////////////////////////////////////////////////////////////////
//
// Fragment shader for the editor grid (Fprocedural grid).
//
// The model is a single large quad at Y=0; lines are computed per-pixel
// from the world position. fwidth() normalizes each line to exactly one
// pixel, with binary hard edges (no smoothing: diagonals may staircase,
// especially far away or at grazing angles). The LOD fade dissolves every
// scale exactly when its cells go sub-pixel, handing over to the next one,
// so the grid looks infinite and never merges into a solid wash. A gentle
// horizon fade softens the far edge of the quad.
// Pixels with no line are discarded, and fading lines blend toward the sky
// ground tone so they melt into the terrain instead of flashing white or
// dipping to black. Opaque output: no blending, no hue surprises. Unlit:
// fixed palette, fully independent of scene lights and fog.
//
////////////////////////////////////////////////////////////////////////////////

// Line pitch in world units and palette (tune to taste). The minor pitch
// (single-cell size) comes from u_grid_step, pushed live from GML; majors
// land every 5 minors and supers every 25, preserving the 1:5:25 ratio.
// Palette stays fixed here. Major/supers share pixels with minors: major
// color wins over minor via mix() so overlaps never add up to white.
#define GRID_MINOR_COL vec3(0.470, 0.460, 0.450)
#define GRID_MAJOR_COL vec3(0.650, 0.650, 0.650)

// Line half-width in pixels (0.5 = ~1px total lines, thinner shimmers).
#define GRID_WIDTH 0.5

// Gentle horizon dissolve (view depth): kills everything before the quad
// edge (the node is scaled 6x, so ±1800) over a long, smooth gradient so no
// cutoff line is ever visible.
#define GRID_HORIZON_A 1600.0
#define GRID_HORIZON_B 1750.0

// Varyings from vertex shader
varying vec3 vWorldPosition;
varying float vViewDepth;

// Legacy background color (kept for compatibility, no longer used:
// coverage is emitted as alpha instead of blending toward a color).
uniform vec3 u_grid_bg;

// Single-cell size in world units (minor pitch), pushed live from the
// toolbar grid combo. Uniforms start at 0 in GLSL ES and the GML side
// pushes on spawn, but the 1.0 fallback keeps the grid sane if a frame
// ever renders before the first push.
uniform float u_grid_step;

// Coverage (0..1) of the grid lines at one pitch, binary hard-edged:
// fwidth only normalizes the width to exactly one pixel, no smoothing.
float gridLine(vec2 _p, float _step) {
	vec2 _q = _p / _step;
	vec2 _w = max(fwidth(_q), vec2(0.0001));
	vec2 _g = abs(fract(_q - 0.5) - 0.5) / _w / GRID_WIDTH;
	float _d = min(min(_g.x, _g.y), 1.0);
	return 1.0 - step(1.0, _d);
}

// Distance fade per scale: each level melts away progressively with view
// depth, further than the previous, so near field stays crisp while the far
// field dissolves smoothly - including high top-down views, where the super
// scale keeps lines readable. Smoothstep over a long range: no visible band
// edge, ever.
// Calibrated for 1m cells; the main() scales the bands with u_grid_step so
// bigger cells stay readable further out (at 1m nothing changes).
#define GRID_MINOR_DIST_A 15.0
#define GRID_MINOR_DIST_B 75.0
#define GRID_MAJOR_DIST_A 60.0
#define GRID_MAJOR_DIST_B 300.0
#define GRID_SUPER_DIST_A 250.0
#define GRID_SUPER_DIST_B 1500.0
float distBand(float _d, float _a, float _b) {
	return 1.0 - smoothstep(_a, _b, _d);
}

// LOD fade for one scale: fully visible while its cells are
// comfortably resolved, dissolving across the Nyquist zone so nothing is
// left to shimmer: gone by ~1 cell-per-pixel, where lines would break into
// dashes. Each scale hands over to the next before that point.
float lodFade(vec2 _p, float _step) {
	vec2 _q = _p / _step;
	float _w = max(max(fwidth(_q).x, fwidth(_q).y), 0.0001);
	return 1.0 - smoothstep(0.6, 1.1, _w);
}

// Fade target: sky ground color below the horizon, so distant lines melt
// into the terrain tone instead of white or black. Must match u_skyBottom.
#define GRID_FADE_COL vec3(0.412, 0.388, 0.365)

void main()
{
	float _step = u_grid_step > 0.001 ? u_grid_step : 1.0;
	float _major = _step * 5.0;
	float _super = _step * 25.0;
	float minor = gridLine(vWorldPosition.xz, _step) * lodFade(vWorldPosition.xz, _step) * distBand(vViewDepth, GRID_MINOR_DIST_A * _step, GRID_MINOR_DIST_B * _step);
	float major = gridLine(vWorldPosition.xz, _major) * lodFade(vWorldPosition.xz, _major) * distBand(vViewDepth, GRID_MAJOR_DIST_A * _step, GRID_MAJOR_DIST_B * _step);
	float sup = gridLine(vWorldPosition.xz, _super) * lodFade(vWorldPosition.xz, _super) * distBand(vViewDepth, GRID_SUPER_DIST_A * _step, GRID_SUPER_DIST_B * _step);
	float horizon = 1.0 - smoothstep(GRID_HORIZON_A, GRID_HORIZON_B, vViewDepth);
	float cover = clamp(max(minor, max(major, sup)), 0.0, 1.0) * horizon;
	if (cover <= 0.01) {
		discard;
	}
	vec3 lineCol = mix(GRID_MINOR_COL, GRID_MAJOR_COL, clamp(major + sup, 0.0, 1.0));
	vec3 gridCol = mix(GRID_FADE_COL, lineCol, cover);

	gl_FragColor = vec4(gridCol, 1.0);
}
