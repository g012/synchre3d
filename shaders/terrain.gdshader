// Island terrain: grass top with soft patchy color variation, layered earth on hole walls
// and cliffs, rocky underside. Palette indices are picked procedurally in world space so
// the pattern is perfectly stable on screen.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

#include "res://shaders/include/toon.gdshaderinc"

uniform float dither = 0.1;
global uniform sampler2D grass_density_map : filter_linear, repeat_disable;
uniform float patch_scale = 0.45;

const int P_STONE_DARK = 16;
const int P_STONE = 17;
const int P_MOSS = 19;
const int P_LEAF_DARK = 20;
const int P_LEAF = 21;
const int P_LEAF_LIGHT = 22;
const int P_GRASS = 23;
const int P_EARTH_DARK = 24;
const int P_EARTH = 25;
const int P_EARTH_LIGHT = 26;

varying vec3 v_world;
varying vec3 v_world_normal;
varying float v_pit;
varying vec2 v_frag;
varying float v_index;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Shared with the grass shader so blades take exactly the color of the ground below them.
int ground_index(vec2 xz, vec2 frag) {
	float density = texture(grass_density_map, (xz - arena_sdf_rect.xy) / arena_sdf_rect.zw).r;
	if (density + (bayer4(frag) - 0.5) * 0.35 > 0.45) {
		return P_LEAF; // shaded soil under grass clumps
	}
	return grass_palette_index(xz, patch_scale, bayer4(frag));
}

int wall_index(vec3 p, bool outer) {
	float y = -p.y + value_noise(p.xz * 2.5 + vec2(p.y * 0.7)) * 0.08;
	if (y < 0.1) {
		return P_LEAF_DARK;
	}
	if (y < 0.42) {
		return P_EARTH_LIGHT;
	}
	if (y < 0.9) {
		return P_EARTH;
	}
	if (outer && y > pit_depth * 0.82) {
		return P_STONE_DARK;
	}
	return P_EARTH_DARK;
}

int underside_index(vec3 p) {
	float y = -p.y - pit_depth;
	float n = value_noise(p.xz * 1.5 + vec2(y * 0.8)) * 0.35;
	float band = fract((y + n) * 0.55);
	if (band < 0.18) {
		return P_EARTH_DARK;
	}
	if (band < 0.55) {
		return P_STONE_DARK;
	}
	return P_STONE;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = MAT_SOLID;
	v_frag = FRAGCOORD.xy;

	vec2 sdf = arena_sdf_at(v_world.xz);
	int idx;
	float pit = 0.0;
	if (v_world_normal.y > 0.8 && v_world.y > -0.02) {
		idx = ground_index(v_world.xz, FRAGCOORD.xy);
	} else if (v_world.y > -pit_depth - 0.05 && v_world_normal.y > -0.5) {
		bool outer = sdf.g > -0.3;
		idx = wall_index(v_world, outer);
		pit = outer ? 0.0 : 1.0;
	} else {
		idx = underside_index(v_world);
	}
	v_index = float(idx);
	v_pit = pit;
}

void light() {
	DIFFUSE_LIGHT += toon_shade(int(v_index + 0.5), NORMAL, LIGHT, ATTENUATION, v_frag, dither, false, v_world, v_pit);
}
