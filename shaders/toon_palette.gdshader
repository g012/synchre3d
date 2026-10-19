// Generic toon material for meshes (Blender assets, props, characters).
// Palette index comes from UV2.x (baked per face in Blender) unless `palette_index` >= 0.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

#include "res://shaders/include/toon.gdshaderinc"

uniform int palette_index = -1;
uniform float material_id = 1.0;
uniform float dither = 0.08;
uniform bool allow_highlight = false;
uniform bool receive_shadows = true;
// Darken when down a hole (characters, props). Off for sky objects like clouds.
uniform bool use_pit_darkness = true;
// Per-instance hit flash: 0 = none, 1 = full white.
instance uniform float flash = 0.0;
// Per-instance fade into darkness while falling down a hole (0..1, dithered steps).
instance uniform float sink = 0.0;

varying flat int v_pal;
varying vec3 v_world_pos;
varying float v_pit;
varying vec2 v_frag;

void vertex() {
	v_pal = palette_index >= 0 ? palette_index : palette_from_uv(UV2.x);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Pit darkness is decided per object (by its origin) so a falling body darkens as a whole.
	v_pit = use_pit_darkness ? pit_mask(NODE_POSITION_WORLD) : 0.0;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = material_id;
	v_frag = FRAGCOORD.xy;
}

void light() {
	float atten = receive_shadows ? ATTENUATION : 1.0;
	vec3 c = toon_shade(v_pal, NORMAL, LIGHT, atten, v_frag, dither, allow_highlight, v_world_pos, v_pit);
	float k = floor(sink * 4.0 + bayer4(v_frag) * 0.999) / 4.0;
	c = mix(c, palette_color(PAL_INK, 0), k);
	DIFFUSE_LIGHT += mix(c, palette_color(1, 3), flash);
}
