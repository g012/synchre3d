// Billboard grass tufts and flowers (MultiMesh).
//
// * Each tuft is a screen-aligned 16x16-texel sprite whose base is snapped to the pixel
//   grid, so sprite texels map 1:1 to screen pixels and never shimmer.
// * Lighting and shadows are evaluated at the tuft's base (LIGHT_VERTEX) with an up normal,
//   so grass shades exactly like the ground it grows from; blade colors come from the same
//   palette function as the terrain, tips use the next-brighter ramp band.
// * Wind: travelling gusts in world space + small noise, displacement quantized to whole
//   texels so blades step crisply. Grass bends away from characters (global actor_a/b).
//
// Atlas channels: R = height along the blade (0 base .. 1 tip), G = petal, B = flower centre.
// INSTANCE_CUSTOM: r = petal palette index / 32 (0 = grass tuft), g = atlas tile / 8,
//                  b = random seed.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, ambient_light_disabled, specular_disabled;

#include "res://shaders/include/toon.gdshaderinc"

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform float atlas_tiles = 8.0;
uniform float sprite_texels = 16.0;
uniform float patch_scale = 0.45;
uniform float dither = 0.1;
uniform float sway_amount = 0.11;
uniform float bend_amount = 0.26;
uniform float depth_bias = 0.06;

global uniform vec4 actor_a;
global uniform vec4 actor_b;

varying flat int v_ground_idx;
varying flat int v_accent_idx;
varying vec3 v_base_view;
varying vec3 v_base_world;
varying vec3 v_up_view;
varying float v_tile;
varying vec2 v_frag;
varying float v_height;
varying float v_petal;
varying float v_center;

vec2 actor_push(vec2 base, vec4 actor) {
	vec2 d = base - actor.xz;
	float dist = length(d);
	float k = clamp(1.0 - dist / max(actor.w, 0.001), 0.0, 1.0);
	return d / max(dist, 0.001) * k * k;
}

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	// abs(): the projection may carry a Y flip depending on the rendering backend.
	float texel = 2.0 / abs(PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vec2 grid_off = mod(VIEWPORT_SIZE, 2.0) * 0.5 * texel;

	vec3 bv = (VIEW_MATRIX * vec4(base, 1.0)).xyz;
	bv.xy = round((bv.xy - grid_off) / texel) * texel + grid_off;

	float rnd = INSTANCE_CUSTOM.b;
	float top = 1.0 - UV.y;
	float phase = dot(base.xz, wind_direction) * 0.55 - wind_time * 1.6;
	float gust = pow(sin(phase) * 0.5 + 0.5, 3.0);
	float flutter = value_noise(base.xz * 1.3 + vec2(wind_time * 0.9, rnd * 7.0));
	vec2 push = wind_direction * (gust * 1.0 + flutter * 0.35 + 0.15) * sway_amount * wind_strength;
	vec2 bend = actor_push(base.xz, actor_a) + actor_push(base.xz, actor_b);
	push += bend * bend_amount;
	vec3 pv = (VIEW_MATRIX * vec4(push.x, 0.0, push.y, 0.0)).xyz;
	pv.xy = round(pv.xy / texel) * texel;

	vec2 local = VERTEX.xy * sprite_texels * texel;
	// A tiny pull toward the camera avoids z-fighting with the ground at the base.
	VERTEX = bv + vec3(local, 0.0) + vec3(pv.xy * top, depth_bias);
	// Tufts whose base is over a hole (holes can open at runtime) collapse to a point.
	if (arena_sdf_at(base.xz).r > -0.08) {
		VERTEX = bv;
	}
	v_up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = v_up_view;
	// Light/shadow sample point: just above the soil to avoid shadow acne on the ground plane.
	v_base_view = (VIEW_MATRIX * vec4(base + vec3(0.0, 0.12, 0.0), 1.0)).xyz;
	v_base_world = base;

	v_tile = round(INSTANCE_CUSTOM.g * atlas_tiles);
	v_accent_idx = int(round(INSTANCE_CUSTOM.r * float(PAL_COUNT)));
	// Blades are the lawn green over the darker soil of the clump; a few are lighter.
	v_ground_idx = 23;
	if (v_accent_idx == 0 && rnd > 0.85) {
		v_ground_idx = 22;
	}
}

void fragment() {
	vec4 s = texture(atlas, vec2((UV.x + v_tile) / atlas_tiles, UV.y));
	ALPHA = s.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = vec3(1.0);
	ROUGHNESS = MAT_GRASS;
	NORMAL = v_up_view;
	LIGHT_VERTEX = v_base_view;
	v_frag = FRAGCOORD.xy;
	v_height = s.r;
	v_petal = s.g;
	v_center = s.b;
}

void light() {
	int band = toon_band(toon_light_amount(NORMAL, LIGHT, ATTENUATION) * cloud_light(v_base_world), v_frag, dither, false);
	// Blade gradient: soil-coloured base, lawn body, bright tip.
	int idx = v_height < 0.3 ? 21 : v_ground_idx;
	if (v_height > 0.78) {
		band += 1;
	}
	if (v_center > 0.5) {
		idx = 28; // flower_yellow centre
		band = band + 1;
	} else if (v_petal > 0.5) {
		idx = v_accent_idx;
		band = max(band, 1) + 1;
	}
	DIFFUSE_LIGHT += palette_color(idx, band);
}
