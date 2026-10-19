// Glowing magic (gathering orbs, bolts, rune discs). Unshaded and banded in palette colors:
// a white-hot core, the spell color, then its darker rim, with an ordered-dither shimmer
// between bands. Writes the "grass" material id so the outline pass leaves it un-outlined:
// glowing things read as light rather than as solid objects.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;

#include "res://shaders/include/toon.gdshaderinc"

uniform int palette_index = 15;
// 0..1: how charged the magic is (bigger white core, faster shimmer).
uniform float energy = 0.5;
// Flat rune rings: a glowing band near the edge of the quad instead of a sphere.
uniform bool disc = false;

void fragment() {
	float facing;
	if (disc) {
		float r = length(UV - 0.5) * 2.0;
		facing = 1.0 - abs(r - 0.84) / 0.14;
		if (facing < 0.0) {
			discard;
		}
	} else {
		facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	}
	float shimmer = (bayer4(FRAGCOORD.xy + vec2(floor(TIME * (8.0 + 10.0 * energy)))) - 0.5) * 0.22;
	float v = facing + shimmer;
	vec3 c;
	if (v > 0.9 - 0.3 * energy) {
		c = palette_color(1, 3);
	} else if (v > 0.5) {
		c = palette_color(palette_index, 3);
	} else if (v > 0.18) {
		c = palette_color(palette_index, 2);
	} else {
		c = palette_color(palette_index, 1);
	}
	ALBEDO = c;
	ROUGHNESS = MAT_GRASS;
}
