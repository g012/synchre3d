// Island terrain: grass top with soft patchy color variation, layered earth on hole walls
// and cliffs, rocky underside, rock on steep mound slopes. Palette indices are picked
// procedurally in world space so the pattern is perfectly stable on screen.
//
// UV2.x = how much a vertex follows the mound height (1 on the top and hole rims, 0 at the
// bottom of walls and on the outer shell); UV2.y = 1 on the grass top. The top discards
// fragments over holes; a hole's wall (self_hole_id) discards where another hole cuts it.
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

// Set on hole wall instances: the id of the hole the wall belongs to.
instance uniform float self_hole_id = -1.0;

varying vec3 v_world;
varying vec3 v_world_normal;
varying float v_ground_h;
varying float v_top;
varying vec2 v_grad;
varying float v_pit;
varying vec2 v_frag;
varying float v_index;
varying float v_depth;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 hg = UV2.x > 0.0 ? arena_height(w.xz) : vec3(0.0);
	VERTEX.y += hg.x * UV2.x;
	v_top = UV2.y;
	if (v_top > 0.5) {
		NORMAL = normalize(vec3(-hg.y, 1.0, -hg.z));
	}
	v_ground_h = hg.x;
	v_grad = hg.yz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
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

// Steep mound slopes: grassy shoulder -> earth -> brown rock -> stone toward the peak.
int slope_index(vec3 p, float ny, vec2 frag) {
	float lumps = fbm2(p.xz * 1.4 + vec2(p.y * 0.8));
	float v = (0.72 - ny) * 4.5 + p.y * 0.22 + lumps * 0.45 + (bayer4(frag) - 0.5) * 0.3;
	if (v < 0.2) {
		return P_LEAF_DARK;
	}
	if (v < 0.75) {
		return P_EARTH;
	}
	if (v < 1.4) {
		return P_BROWN_DARK;
	}
	return P_STONE;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = MAT_SOLID;
	v_frag = FRAGCOORD.xy;

	int idx;
	float pit = 0.0;
	// Depth below the local ground surface (mounds lift the rim of walls too).
	vec3 rel = vec3(v_world.x, v_world.y - v_ground_h, v_world.z);
	if (v_top > 0.5) {
		if (arena_holes_dist(v_world.xz, -1.0) < 0.0) {
			discard;
		}
		vec3 n = normalize(v_world_normal);
		if (dot(v_grad, v_grad) > 0.0) {
			NORMAL = normalize((VIEW_MATRIX * vec4(arena_light_normal(v_grad), 0.0)).xyz);
		}
		// Hills stay grassy; only mountain-steep flanks (> ~45 deg) turn to earth and rock.
		idx = n.y + (bayer4(FRAGCOORD.xy) - 0.5) * 0.06 > 0.7 ? ground_index(v_world.xz, FRAGCOORD.xy) : slope_index(v_world, n.y, FRAGCOORD.xy);
	} else {
		if (self_hole_id >= 0.0 && arena_holes_dist(v_world.xz, self_hole_id) < 0.0) {
			discard;
		}
		idx = earth_index(rel, FRAGCOORD.xy);
		// Hole walls (inside the island footprint, within the slab) sink into darkness.
		bool hole_wall = arena_sdf_at(v_world.xz).g < -0.3 && rel.y > -pit_depth - 0.05 && v_world_normal.y > -0.5;
		pit = hole_wall ? 1.0 : 0.0;
	}
	v_index = float(idx);
	v_pit = pit;
	v_depth = rel.y;
}

void light() {
	DIFFUSE_LIGHT += toon_shade(int(v_index + 0.5), NORMAL, LIGHT, ATTENUATION, v_frag, dither, false, vec3(v_world.x, v_depth, v_world.z), v_pit);
}
