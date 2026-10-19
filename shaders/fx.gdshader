// Pixel FX billboards (dust, impact stars, sparks, rings) drawn from a MultiMesh pool.
// Sizes are whole texel counts and centres are snapped to the pixel grid, so effects stay
// crisp; colors come from the palette (R channel of the atlas = brighter band).
//
// INSTANCE_CUSTOM: r = palette index / 32, g = atlas tile / 4, b = size in texels / 64,
//                  a = ramp band / 4.
shader_type spatial;
render_mode unshaded, skip_vertex_transform, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/include/toon.gdshaderinc"

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform float atlas_tiles = 4.0;

varying flat int v_pal;
varying flat int v_band;
varying float v_tile;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float texel = 2.0 / abs(PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = round(INSTANCE_CUSTOM.b * 64.0);
	// Even sizes sit on pixel edges, odd sizes on pixel centres.
	vec2 grid_off = mod(VIEWPORT_SIZE + vec2(size), 2.0) * 0.5 * texel;
	vec3 cv = (VIEW_MATRIX * vec4(base, 1.0)).xyz;
	cv.xy = round((cv.xy - grid_off) / texel) * texel + grid_off;
	VERTEX = cv + vec3(VERTEX.xy * size * texel, 0.25);
	v_pal = int(round(INSTANCE_CUSTOM.r * float(PAL_COUNT)));
	v_band = int(round(INSTANCE_CUSTOM.a * 4.0));
	v_tile = round(INSTANCE_CUSTOM.g * atlas_tiles);
}

void fragment() {
	vec4 s = texture(atlas, vec2((UV.x + v_tile) / atlas_tiles, UV.y));
	ALPHA = s.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	int band = v_band + (s.r > 0.5 ? 1 : 0);
	ALBEDO = s.g > 0.5 ? palette_color(1, 3) : palette_color(v_pal, band);
	ROUGHNESS = MAT_SOLID;
}
