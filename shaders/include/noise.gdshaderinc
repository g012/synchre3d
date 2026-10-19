#ifndef NOISE_INC
#define NOISE_INC
// Small deterministic noise helpers shared by terrain, grass and foliage.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise in [-1, 1].
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

float fbm2(vec2 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.13 + 17.0) * 0.35;
}

// Lawn color: mostly one green, with a sparse dithered sprinkle of the lighter green in
// a few soft areas so open lawn never reads as a flat fill.
int grass_palette_index(vec2 xz, float scale, float dither01) {
	float n = fbm2(xz * scale);
	if (n > 0.35 && dither01 < (n - 0.35) * 0.5) {
		return 22; // leaf_light
	}
	return 23; // grass
}
#endif
