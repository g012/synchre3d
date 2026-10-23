// Falling water hanging from a pond's lip (built by Water): streaks scrolling down in
// world-anchored 1-pixel columns, white foam where it pours over, then it either dissolves
// into mist (off the island's edge) or sinks into the dark (down a hole).
// UV.y = distance fallen (world units); UV2.x = 1 off the edge, 0 into a hole.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled, cull_disabled;

#include "res://shaders/include/toon.gdshaderinc"

uniform float texel = 0.031;
uniform float speed = 3.2;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fall = UV.y;
	bool edge = UV2.x > 0.5;
	float dith = bayer4(FRAGCOORD.xy);
	if (edge) {
		// Breaks up into mist on the way down.
		if (dith < (fall - 1.5) / 4.0) {
			discard;
		}
	} else if (fall > 2.0) {
		discard;
	}
	vec2 ax = normalize(INV_VIEW_MATRIX[0].xz);
	float col = floor(dot(v_world.xz, ax) / texel);
	float h = hash12(vec2(col, 3.7));
	// Water speeds up as it falls.
	float y = fall * (1.0 + fall * 0.15) - TIME * speed * (0.8 + 0.4 * h);
	float s = fract(y * (0.9 + 0.5 * h) + h * 7.0);
	int band = s < 0.12 ? 3 : (s < 0.45 ? 2 : 1);
	vec3 c = band == 3 ? palette_color(1, 3) : palette_color(15, band);
	if (h > 0.8 && band == 1) {
		c = palette_color(13, 2);
	}
	// Foam where it pours over the lip.
	if (fall < 0.08 + 0.06 * hash12(vec2(col, floor(TIME * 8.0)))) {
		c = palette_color(1, 3);
	}
	if (!edge) {
		// Into a hole: sinks into darkness like the hole walls.
		float d = clamp(fall / 1.6, 0.0, 1.0);
		d = floor(d * 4.0 + dith * 0.999) / 4.0;
		c = mix(c, palette_color(PAL_INK, 0), d * 0.9);
	}
	ALBEDO = c;
	ROUGHNESS = MAT_GRASS;
}
