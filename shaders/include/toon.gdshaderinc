// Shared toon lighting for every lit surface in the game.
//
// Colors never come from material albedo: each surface carries a *palette index* and the
// light pass picks one of four hand-tuned ramp colors (shadow / half / lit / highlight) from
// assets/palette/palette_ramp.png. Lighting can therefore only ever produce palette colors,
// which keeps the whole frame on a limited, coherent palette.
//
// Surfaces write ALBEDO = 1.0 and use `ambient_light_disabled`, so DIFFUSE_LIGHT is the final
// color. Band transitions can be softened with a stable screen-space Bayer dither.

#ifndef TOON_INC
#define TOON_INC
#include "res://shaders/include/noise.gdshaderinc"

global uniform sampler2D palette_ramp : filter_nearest;
global uniform float wind_time;
global uniform vec2 wind_direction;
global uniform float wind_strength;
// 0 disables drifting cloud shadows.
global uniform float cloud_shadow_strength;
global uniform float pit_depth;
// Baked arena distance field: R = walkable ground (negative = solid), G = island outline.
global uniform sampler2D arena_sdf : filter_linear, repeat_disable;
global uniform vec4 arena_sdf_rect;
// Runtime holes and mounds (written by Arena._upload_features, one texel per item):
//   row 0: hole (center.x, center.z, radius, scale)   row 1: (ph0, ph1, wobble, id)
//   row 2: mound (center.x, center.z, radius, height) row 3: (ph0, ph1, sharpness, 0)
global uniform sampler2D arena_features : filter_nearest, repeat_disable;
global uniform int arena_hole_count;
global uniform int arena_mound_count;
// Mounds flatten out between these distances inside the island edge.
global uniform vec2 arena_island_fade;

// Material ids written to ROUGHNESS so the post-process can tell surfaces apart
// (decoded in post_outline.gdshader).
const float MAT_SOLID = 1.0;
const float MAT_CHARACTER = 0.75;
const float MAT_FOLIAGE = 0.5;
const float MAT_GRASS = 0.25;

const int PAL_INK = 0;
const int PAL_COUNT = 32;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 palette_color(int index, int band) {
	return srgb_to_linear(texelFetch(palette_ramp, ivec2(clamp(index, 0, PAL_COUNT - 1), clamp(band, 0, 3)), 0).rgb);
}

int palette_from_uv(float u) {
	return int(floor(u * float(PAL_COUNT)));
}

// 4x4 ordered dither threshold in [0, 1).
float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(floor(frag), 4.0));
	int i = p.x + p.y * 4;
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	                              3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

// Light amount in [0,1] -> discrete band. `dither` widens the band edges into a 4x4 pattern.
int toon_band(float light_amount, vec2 frag, float dither, bool allow_highlight) {
	float v = light_amount + (bayer4(frag) - 0.5) * dither;
	if (allow_highlight && v > 0.93) {
		return 3;
	}
	if (v > 0.5) {
		return 2;
	}
	return v > 0.14 ? 1 : 0;
}

// Directional-light term: N.L wrapped slightly so terminators sit a bit past 90 degrees,
// multiplied by the (hard) shadow attenuation.
float toon_light_amount(vec3 normal, vec3 light, float attenuation) {
	float ndl = dot(normal, light);
	float wrapped = clamp((ndl + 0.15) / 1.15, 0.0, 1.0);
	return wrapped * step(0.5, attenuation);
}

// Large soft cloud shadows drifting with the wind; returns a light multiplier in [0, 1].
// Their soft edges turn into ordered-dither bands through toon_band().
float cloud_light(vec3 world_pos) {
	vec2 q = world_pos.xz * 0.19 - wind_direction * wind_time * 0.06;
	float n = fbm2(q);
	return 1.0 - smoothstep(0.08, 0.3, n) * cloud_shadow_strength;
}

float world_y_floor() {
	return -pit_depth * 3.0;
}

vec2 arena_sdf_at(vec2 xz) {
	return texture(arena_sdf, (xz - arena_sdf_rect.xy) / arena_sdf_rect.zw).rg;
}

// Signed distance to hole `i`'s outline (negative inside). Mirrors Arena.hole_sdf().
float arena_hole_dist(vec2 xz, int i) {
	vec4 a = texelFetch(arena_features, ivec2(i, 0), 0);
	if (a.w <= 0.02) {
		return 1e3;
	}
	vec4 b = texelFetch(arena_features, ivec2(i, 1), 0);
	vec2 d = xz - a.xy;
	float l = length(d);
	float reach = (a.z + b.z) * a.w;
	if (l > reach + 0.05) {
		return l - reach;
	}
	float ang = atan(d.y, d.x);
	return l - (a.z + b.z * (0.6 * sin(3.0 * ang + b.x) + 0.4 * sin(5.0 * ang + b.y))) * a.w;
}

// Smallest hole distance at `xz`, ignoring the hole whose id is `skip_id` (-1: none).
float arena_holes_dist(vec2 xz, float skip_id) {
	float m = 1e3;
	for (int i = 0; i < arena_hole_count; i++) {
		if (abs(texelFetch(arena_features, ivec2(i, 1), 0).w - skip_id) < 0.5) {
			continue;
		}
		m = min(m, arena_hole_dist(xz, i));
	}
	return m;
}

// Walkable ground SDF (negative = solid): island outline minus holes. Mirrors Arena.ground_sdf().
float arena_ground_sdf(vec2 xz) {
	return max(arena_sdf_at(xz).g, -arena_holes_dist(xz, -1.0));
}

// Ground height and slope at `xz`: vec3(height, dh/dx, dh/dz). Mirrors Arena.height_at();
// the slope is the analytic radial derivative of the tallest mound (normals only).
vec3 arena_height(vec2 xz) {
	if (arena_mound_count == 0) {
		return vec3(0.0);
	}
	float best = 0.0;
	vec2 grad = vec2(0.0);
	for (int i = 0; i < arena_mound_count; i++) {
		vec4 a = texelFetch(arena_features, ivec2(i, 2), 0);
		vec2 d = xz - a.xy;
		float l = length(d);
		if (a.w <= 0.0 || l >= a.z * 1.17) {
			continue;
		}
		vec4 b = texelFetch(arena_features, ivec2(i, 3), 0);
		float ang = atan(d.y, d.x);
		float rr = a.z * (1.0 + 0.1 * sin(3.0 * ang + b.x) + 0.06 * sin(5.0 * ang + b.y));
		float x = l / rr;
		if (x >= 1.0) {
			continue;
		}
		float s = (1.0 - x * x) * (1.0 - x * x);
		float ds = -4.0 * x * (1.0 - x * x);
		float p = pow(1.0 - x, 1.5);
		float dp = -1.5 * sqrt(1.0 - x);
		float h = a.w * mix(s, p, b.z);
		if (h > best) {
			best = h;
			grad = a.w * mix(ds, dp, b.z) / rr * d / max(l, 1e-4);
		}
	}
	float fade = smoothstep(arena_island_fade.x, arena_island_fade.y, -arena_sdf_at(xz).g);
	return vec3(best, grad) * fade;
}

// Lighting normal for the ground at slope `grad` (dh/dx, dh/dz). The slope is exaggerated so
// gentle hills already cross a toon band on their shaded flank (otherwise a 40 deg grassy
// hill shades like flat lawn and its shape does not read).
vec3 arena_light_normal(vec2 grad) {
	return normalize(vec3(-grad.x * 2.4, 1.0, -grad.y * 2.4));
}

// 1 when a point is inside the island footprint but below the grass, i.e. down a hole.
float pit_mask(vec3 world_pos) {
	return step(arena_sdf_at(world_pos.xz).g, -0.25) * step(world_y_floor(), world_pos.y);
}

// Surfaces down a hole sink toward ink in a few dithered steps.
vec3 apply_pit_darkness(vec3 color, float world_y, float mask, vec2 frag) {
	float d = clamp(-world_y / max(pit_depth, 0.01), 0.0, 1.0) * mask;
	d = floor(d * 4.0 + bayer4(frag) * 0.999) / 4.0;
	return mix(color, palette_color(PAL_INK, 0), d * 0.9);
}

vec3 toon_shade(int index, vec3 normal, vec3 light, float attenuation, vec2 frag, float dither, bool allow_highlight, vec3 world_pos, float pit) {
	float amount = toon_light_amount(normal, light, attenuation) * cloud_light(world_pos);
	int band = toon_band(amount, frag, dither, allow_highlight);
	return apply_pit_darkness(palette_color(index, band), world_pos.y, pit, frag);
}
#endif
