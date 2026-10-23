// Pond water surface: one flat quad per pond at WATER_LEVEL. Everything is worked out from
// the shared analytic ground functions (no depth texture), so it lines up exactly with the
// terrain and moves with spell-made holes and mounds:
// * color bands by water depth (light sky-blue shallows -> deep teal), dithered borders and a
//   slow drifting sheen; cloud shadows darken it by one band
// * a foam line on the shore and along any lip where the water spills into a gap
// * short world-space, view-aligned horizontal glints that flick on and off (the "little
//   animated waves" of David Holland's 3D pixel art)
// * ripple rings around fighters wading in it (actor_a / actor_b, shared with the grass)
// Over gaps (holes, off the island) and dry ground it discards.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled, cull_disabled;

#include "res://shaders/include/toon.gdshaderinc"

global uniform vec4 actor_a;
global uniform vec4 actor_b;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Shallow -> deep: white foam, light shallows, sky blue, teal, deep teal, darkest teal.
vec3 water_ramp(int i) {
	if (i >= 5) return palette_color(1, 3);
	if (i == 4) return palette_color(15, 3);
	if (i == 3) return palette_color(15, 2);
	if (i == 2) return palette_color(13, 2);
	if (i == 1) return palette_color(13, 1);
	return palette_color(13, 0);
}

// 1 on a 1-pixel ring of radius r around c.
float ring(vec2 p, vec2 c, float r, float px) {
	return step(abs(length(p - c) - r), px * 0.6);
}

// Ripples around a fighter standing in the water.
float ripples(vec2 xz, vec4 actor, float px, float dith) {
	if (actor.w <= 0.0 || WATER_LEVEL - arena_height(actor.xz).x <= 0.0 || abs(actor.y - WATER_LEVEL) > 0.6) {
		return 0.0;
	}
	float hit = ring(xz, actor.xz, 0.3, px * 1.5);
	for (int k = 0; k < 2; k++) {
		float f = fract(TIME * 0.7 + float(k) * 0.5);
		hit = max(hit, ring(xz, actor.xz, 0.32 + f * 0.55, px) * step(dith, 1.0 - f));
	}
	return hit;
}

void fragment() {
	vec2 xz = v_world.xz;
	float depth = WATER_LEVEL - arena_height(xz).x;
	float gap = arena_ground_sdf(xz);
	if (depth <= 0.0 || gap > 0.0) {
		discard;
	}
	float dith = bayer4(FRAGCOORD.xy);
	// Screen-horizontal and screen-depth axes on the ground plane, and the world size of one
	// pixel along each.
	vec2 ax = normalize(INV_VIEW_MATRIX[0].xz);
	vec2 ay = vec2(-ax.y, ax.x);
	float u = dot(xz, ax);
	float v = dot(xz, ay);
	float px_u = max(fwidth(u), 1e-4);
	float px_v = max(fwidth(v), 1e-4);

	// Depth bands, wobbling slowly so the shallows breathe.
	float wob = (value_noise(xz * 1.6 + TIME * vec2(0.13, 0.07)) - 0.5) * 0.04;
	float dd = depth + wob + (dith - 0.5) * 0.03;
	int idx = dd < 0.045 ? 4 : (dd < 0.1 ? 3 : (dd < 0.17 ? 2 : (dd < 0.24 ? 1 : 0)));
	// Drifting sheen (sky reflection) one band lighter, cloud shadows one band darker.
	float sheen = fbm2(xz * 0.45 + TIME * vec2(0.04, 0.02));
	if (sheen + (dith - 0.5) * 0.08 > 0.66) {
		idx = min(idx + 1, 4);
	}
	if (cloud_light(v_world) + (dith - 0.5) * 0.15 < 0.85) {
		idx = max(idx - 1, 0);
	}

	// Glints: one per cell of a grid aligned with the screen, short horizontal 1-pixel lines.
	vec2 cell_size = vec2(0.75, 0.24);
	vec2 cell = floor(vec2(u, v) / cell_size);
	float h = hash12(cell);
	float h2 = hash12(cell + 17.31);
	float life = fract(TIME * (0.25 + 0.2 * h2) + h);
	if (life < 0.45 && depth > 0.05) {
		float k = life / 0.45;
		float half_len = cell_size.x * (0.12 + 0.18 * h2) * sin(k * PI);
		float uc = (cell.x + 0.25 + 0.5 * h2) * cell_size.x;
		float vc = (cell.y + 0.3 + 0.4 * h) * cell_size.y;
		if (abs(v - vc) < px_v * 0.5 && abs(u - uc) < half_len) {
			idx = k < 0.5 ? 5 : 4;
		}
	}

	// Foam: on the shore, along spill lips, and ripples around waders.
	float shore = depth + (value_noise(xz * 7.0 + vec2(TIME * 0.6, 0.0)) - 0.5) * 0.012;
	if (shore < 0.018 || gap > -0.06 - 0.03 * sin(TIME * 5.0 + u * 9.0)) {
		idx = 5;
	} else if (shore < 0.03 && dith < 0.5) {
		idx = 4;
	}
	if (ripples(xz, actor_a, max(px_u, px_v), dith) + ripples(xz, actor_b, max(px_u, px_v), dith) > 0.0) {
		idx = max(idx, 4);
	}
	ALBEDO = water_ramp(idx);
	ROUGHNESS = MAT_GRASS;
}
