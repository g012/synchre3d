// Island terrain: grass top with soft patchy color variation, layered earth on hole walls
// and cliffs, rocky underside. Palette indices are picked procedurally in world space so
// the pattern is perfectly stable on screen.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

#include "res://shaders/include/toon.gdshaderinc"

uniform float dither = 0.1;
global uniform sampler2D grass_density_map : filter_linear, repeat_disable;
uniform float patch_scale = 0.45;
// Extra depth (beyond pit_depth) over which the underside fades from earth to stone.
uniform float underside_fade_depth = 3.0;

const int P_BROWN_DARK = 8;
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

// One soil-to-rock gradient for every vertical surface (hole walls, cliffs, underside),
// driven by depth below the grass so the island reads as a single mass:
// grass lip -> light topsoil -> earth -> dark earth -> brown rock -> stone, each step with
// noisy dithered borders.
int earth_index(vec3 p, vec2 frag) {
	float wobble = value_noise(p.xz * 2.3 + vec2(p.y * 0.6)) * 0.09;
	// Dithered offset softens every band border into a 1-2 pixel ordered-dither seam.
	float d = -p.y + wobble + (bayer4(frag) - 0.5) * 0.1;
	if (d < 0.1) {
		return P_LEAF_DARK;
	}
	if (d < 0.42) {
		return P_EARTH_LIGHT;
	}
	if (d < 0.95) {
		return P_EARTH;
	}
	// Below the topsoil, a continuous "rockiness" ramp walks through a chain of warm-to-cool
	// colors (dark earth -> brown rock -> stone). Noise lumps and a Bayer offset break the
	// borders up so the change is progressive, with no stripes or hard seams.
	float t = smoothstep(0.95, pit_depth + underside_fade_depth, d);
	float lumps = fbm2(p.xz * 0.75 + vec2(p.y * 1.1, -p.y * 0.6));
	float v = t * 2.0 + lumps * 0.55 + (bayer4(frag) - 0.5) * 0.25;
	if (v < 0.7) {
		return P_EARTH_DARK;
	}
	if (v < 1.45) {
		return P_BROWN_DARK;
	}
	return P_STONE_DARK;
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
	} else {
		idx = earth_index(v_world, FRAGCOORD.xy);
		// Hole walls (inside the island footprint, within the slab) sink into darkness.
		bool hole_wall = sdf.g < -0.3 && v_world.y > -pit_depth - 0.05 && v_world_normal.y > -0.5;
		pit = hole_wall ? 1.0 : 0.0;
	}
	v_index = float(idx);
	v_pit = pit;
}

void light() {
	DIFFUSE_LIGHT += toon_shade(int(v_index + 0.5), NORMAL, LIGHT, ATTENUATION, v_frag, dither, false, v_world, v_pit);
}
