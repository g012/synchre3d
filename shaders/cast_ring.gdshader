// Ring on the ground around a fighter: a beat pulse (metronome you can see without looking
// away from the fight) and the incantation in progress, one pip per syllable of the chant,
// clockwise from the top: lit in the button's color once validated, faint slots for the rest.
// Unshaded and banded in palette colors; writes the "grass" material id so the outline pass
// leaves it alone.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled, cull_disabled;

#include "res://shaders/include/toon.gdshaderinc"

global uniform float beat_time;

// Fighter color (palette index).
uniform int palette_index = 4;
// Notes validated so far as button bitmasks (bit 0 A, 1 B, 2 X, 3 Y; a chord has several,
// drawn as a pip split in colored sectors), and the number of notes of the chant
// (0 = not chanting).
uniform int pips[12];
uniform int pip_count = 0;
uniform int slot_count = 0;

const float RING = 0.55;
const float PIP_RING = 0.8;
const float PIP_R = 0.13;
// Pulled this far toward the camera (view space) so grass tufts don't hide it, while the
// fighter's body (nearer the camera than the ring's far side) still covers its back.
const float DEPTH_BIAS = 0.35;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.z += DEPTH_BIAS;
	POSITION = PROJECTION_MATRIX * v;
}

int bit_count(int mask) {
	int c = 0;
	for (int b = 0; b < 4; b++) {
		c += (mask >> b) & 1;
	}
	return c;
}

// The `n`-th set button of `mask`.
int nth_button(int mask, int n) {
	int c = 0;
	for (int b = 0; b < 4; b++) {
		if (((mask >> b) & 1) == 1) {
			if (c == n) {
				return b;
			}
			c++;
		}
	}
	return 0;
}

int button_palette(int b) {
	// Xbox face colors from the game palette: A green, B red, X blue, Y yellow.
	return b == 0 ? 22 : (b == 1 ? 4 : (b == 2 ? 31 : 6));
}

void fragment() {
	// Quad spans [-1, 1]: UV.x -> +X, UV.y -> +Z (screen down).
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float dith = bayer4(FRAGCOORD.xy);
	bool has_beat = beat_time >= 0.0;
	float ph = has_beat ? fract(beat_time) : 0.5;
	float hit = has_beat ? pow(1.0 - ph, 3.0) : 0.0;
	bool downbeat = has_beat && mod(floor(beat_time), 4.0) < 0.5;
	vec3 c = vec3(0.0);
	bool on = false;

	// Base ring: thin and dithered between beats, solid and bright on the beat.
	float thick = 0.04 + 0.04 * hit;
	if (abs(r - RING) < thick && dith < 0.6 + 0.4 * hit) {
		c = palette_color(palette_index, hit > 0.35 ? 3 : 2);
		on = true;
	}
	// Pulse: a wave leaving the ring on each beat (wider on the bar's downbeat).
	float wave_r = RING + ph * (downbeat ? 0.42 : 0.28);
	if (has_beat && ph < 0.45 && abs(r - wave_r) < 0.025 && dith < 1.0 - ph * 2.0) {
		c = palette_color(downbeat ? 1 : palette_index, 3);
		on = true;
	}
	// Syllable pips around the ring.
	if (slot_count > 0) {
		float step = TAU / float(max(slot_count, 6));
		float a = atan(p.y, p.x) + PI * 0.5; // 0 at the top, clockwise on screen
		a = mod(a + step * 0.5, TAU);
		int i = int(floor(a / step));
		if (i < slot_count) {
			float ai = float(i) * step - PI * 0.5;
			vec2 centre = vec2(cos(ai), sin(ai)) * PIP_RING;
			float d = length(p - centre);
			if (i < pip_count) {
				if (d < PIP_R) {
					// One sector per button of a chord.
					int n = max(bit_count(pips[i]), 1);
					vec2 q = p - centre;
					int sector = min(int(floor((atan(q.y, q.x) + PI) / TAU * float(n))), n - 1);
					c = palette_color(button_palette(nth_button(pips[i], sector)), d < PIP_R * 0.55 ? 3 : 2);
					on = true;
				} else if (d < PIP_R + 0.03) {
					c = palette_color(0, 1);
					on = true;
				}
			} else if (d < PIP_R * 0.5 && dith < 0.5) {
				c = palette_color(1, 2);
				on = true;
			}
		}
	}
	if (!on) {
		discard;
	}
	ALBEDO = c;
	ROUGHNESS = MAT_GRASS;
}
