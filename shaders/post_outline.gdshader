// Full-screen pixel-art post-process, drawn by a quad parented to the camera.
//
// * Outlines: a pixel that is in FRONT of one of its 4 neighbours by more than a
//   slope-aware depth threshold is darkened (one pixel thick, always on the foreground
//   side, so silhouettes never double up).
// * Edge highlights: convex creases (normal discontinuity at similar depth) are lightened on
//   the more oblique side -> crisp lit rims on hole edges, rocks and cliffs.
// * Sky: pixels with no geometry get a dithered, banded gradient.
//
// Adapted from denovodavid's t3ssel8r-style outline shader as ported to Godot by
// Robert-K (MIT): https://github.com/Robert-K/godot-3d-pixel-art
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_rough_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform bool enabled = true;
uniform int debug_view = 0; // 1 = material ids, 2 = normals, 3 = outline/edge mask, 4 = raw roughness byte

group_uniforms outline;
uniform float depth_threshold = 0.18;
uniform float depth_slope_scale = 3.0;
uniform float foliage_threshold = 0.9;
uniform vec3 outline_mul : source_color = vec3(0.42, 0.36, 0.52);
uniform vec3 character_outline_mul : source_color = vec3(0.26, 0.21, 0.34);

group_uniforms edges;
uniform float convex_threshold = 0.5;
// Sun direction (towards the light) in view space, set by PixelCamera. Only creases whose
// surface faces the sun get a highlight, like a lit rim.
uniform vec3 light_dir_view = vec3(0.0, 0.7, 0.7);
uniform float edge_light_min = 0.25;
uniform float edge_strength = 0.38;
uniform vec3 edge_color : source_color = vec3(1.0, 0.96, 0.82);

group_uniforms sky;
uniform vec3 sky_top : source_color = vec3(0.47, 0.72, 0.86);
uniform vec3 sky_bottom : source_color = vec3(0.80, 0.91, 0.90);
uniform float sky_steps = 7.0;

const float ID_NONE = 0.0;
const float ID_GRASS = 1.0;
const float ID_FOLIAGE = 2.0;
const float ID_CHARACTER = 3.0;
const float ID_SOLID = 4.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(floor(frag), 4.0));
	int i = p.x + p.y * 4;
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	                              3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

// Linear distance from the camera plane; huge for sky.
float view_depth(ivec2 px, vec2 size, mat4 inv_proj) {
	float d = texelFetch(depth_tex, px, 0).r;
	if (d <= 0.0) {
		return 1e6;
	}
	vec2 uv = (vec2(px) + 0.5) / size;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

// The normal-roughness buffer stores ROUGHNESS as-is in alpha (verified on Godot 4.7
// Forward+ with the raw debug view), so ids are spaced 0.25 apart.
float material_id(vec4 nr) {
	return round(nr.a * 4.0);
}

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	vec2 size = VIEWPORT_SIZE;
	vec3 color = texelFetch(screen_tex, px, 0).rgb;
	float raw_depth = texelFetch(depth_tex, px, 0).r;

	if (raw_depth <= 0.0) {
		// Sky: banded vertical gradient with ordered dithering between bands.
		float t = clamp(SCREEN_UV.y * 1.15 - 0.05, 0.0, 1.0);
		t = floor(t * sky_steps + bayer4(FRAGCOORD.xy)) / sky_steps;
		ALBEDO = mix(sky_top, sky_bottom, t);
	} else if (!enabled) {
		ALBEDO = color;
	} else {
		vec4 nr = texelFetch(normal_rough_tex, px, 0);
		vec3 n = normalize(nr.xyz * 2.0 - 1.0);
		float id = material_id(nr);
		float d = view_depth(px, size, INV_PROJECTION_MATRIX);

		// Grazing surfaces naturally change depth fast between pixels: raise the threshold there.
		float slope = clamp(1.0 - n.z, 0.0, 1.0);
		float thresh = depth_threshold * (1.0 + slope * depth_slope_scale);

		const ivec2 offsets[4] = ivec2[4](ivec2(0, -1), ivec2(0, 1), ivec2(-1, 0), ivec2(1, 0));
		bool outline = false;
		bool edge = false;
		for (int i = 0; i < 4; i++) {
			ivec2 q = clamp(px + offsets[i], ivec2(0), ivec2(size) - 1);
			float dq = view_depth(q, size, INV_PROJECTION_MATRIX);
			vec4 nrq = texelFetch(normal_rough_tex, q, 0);
			float idq = material_id(nrq);
			float diff = dq - d;

			if (id != ID_GRASS) {
				float t = (id == ID_FOLIAGE && idq == ID_FOLIAGE) ? foliage_threshold : thresh;
				if (diff > t) {
					outline = true;
				}
			}

			if ((id == ID_SOLID || id == ID_CHARACTER) && abs(diff) < thresh && idq == id) {
				vec3 nq = normalize(nrq.xyz * 2.0 - 1.0);
				vec2 dir = vec2(float(offsets[i].x), -float(offsets[i].y));
				float convex = dot(nq.xy - n.xy, dir);
				bool oblique_side = n.z < nq.z - 0.02 || (abs(n.z - nq.z) <= 0.02 && (offsets[i].y > 0 || offsets[i].x > 0));
				if (convex > convex_threshold && oblique_side && dot(n, light_dir_view) > edge_light_min) {
					edge = true;
				}
			}
		}

		if (outline) {
			color *= (id == ID_CHARACTER) ? character_outline_mul : outline_mul;
		} else if (edge) {
			color = mix(color, edge_color, edge_strength);
		}
		ALBEDO = color;

		if (debug_view == 1) {
			ALBEDO = vec3(id == ID_GRASS ? 1.0 : 0.0, id == ID_FOLIAGE ? 1.0 : 0.0, id == ID_CHARACTER ? 1.0 : (id == ID_SOLID ? 0.3 : 0.0));
		} else if (debug_view == 2) {
			ALBEDO = n * 0.5 + 0.5;
		} else if (debug_view == 4) {
			ALBEDO = vec3(nr.a);
		} else if (debug_view == 3) {
			ALBEDO = vec3(outline ? 1.0 : 0.0, edge ? 1.0 : 0.0, 0.0);
		}
	}
}
