// Tree / bush foliage made of pixel-art leaf-cluster billboards (MultiMesh).
//
// Cards are scattered over the surface of a rough "blob" mesh made in Blender. Each card is
// lit as a whole with the blob normal at its anchor (passed in INSTANCE_CUSTOM), so the
// canopy reads as a few crisp toon bands while the leaf texture breaks up the silhouette.
// Cards sway with the same wind field as the grass, in whole-texel steps.
//
// INSTANCE_CUSTOM: rgb = blob normal * 0.5 + 0.5, a = atlas tile / 4.
// Atlas: A = mask, R = sun-side highlight pixels, G = shade pixels.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, ambient_light_disabled, specular_disabled;

#include "res://shaders/include/toon.gdshaderinc"

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform float atlas_tiles = 4.0;
uniform float sprite_texels = 16.0;
uniform int leaf_index = 21;
uniform float dither = 0.12;
uniform float sway_amount = 0.05;


varying vec3 v_normal_view;
varying vec3 v_center_view;
varying vec3 v_center_world;
varying float v_tile;
varying vec2 v_frag;
varying float v_lit;
varying float v_shade;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 n_world = normalize(INSTANCE_CUSTOM.rgb * 2.0 - 1.0);
	float texel = 2.0 / abs(PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vec2 grid_off = mod(VIEWPORT_SIZE, 2.0) * 0.5 * texel;

	// Gusts travel across the canopy; upper cards move more.
	float phase = dot(base.xz, wind_direction) * 0.55 - wind_time * 1.6;
	float gust = pow(sin(phase) * 0.5 + 0.5, 3.0);
	float flutter = value_noise(base.xz * 2.1 + base.y + vec2(wind_time * 1.3));
	vec3 sway = vec3(wind_direction.x, 0.0, wind_direction.y) * (gust + flutter * 0.4) * sway_amount * wind_strength * (0.5 + base.y * 0.25);

	vec3 cv = (VIEW_MATRIX * vec4(base + sway, 1.0)).xyz;
	cv.xy = round((cv.xy - grid_off) / texel) * texel + grid_off;
	VERTEX = cv + vec3(VERTEX.xy * sprite_texels * texel, 0.0);
	v_normal_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	NORMAL = v_normal_view;
	v_center_view = cv;
	v_center_world = base;
	v_tile = round(INSTANCE_CUSTOM.a * atlas_tiles);
}

void fragment() {
	vec4 s = texture(atlas, vec2((UV.x + v_tile) / atlas_tiles, UV.y));
	ALPHA = s.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = vec3(1.0);
	ROUGHNESS = MAT_FOLIAGE;
	NORMAL = v_normal_view;
	LIGHT_VERTEX = v_center_view;
	v_frag = FRAGCOORD.xy;
	v_lit = s.r;
	v_shade = s.g;
}

void light() {
	float amount = toon_light_amount(NORMAL, LIGHT, ATTENUATION) * cloud_light(v_center_world);
	int band = toon_band(amount, v_frag, dither, false);
	int idx = leaf_index;
	// Leaf texture detail: sunlit leaf tips go one band up (and to the lighter green),
	// shaded leaves one band down.
	if (v_lit > 0.5 && band >= 1) {
		band += 1;
		idx = band >= 3 ? leaf_index + 1 : leaf_index;
	} else if (v_shade > 0.5) {
		band -= 1;
	}
	DIFFUSE_LIGHT += palette_color(idx, band);
}
