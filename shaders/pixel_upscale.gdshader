// Crisp pixel-art upscaling for the low-res game image.
// At integer scales and with no sub-pixel offset this is identical to nearest filtering;
// at fractional scales / offsets it anti-aliases only the one-texel seam between pixels,
// so pixels keep a uniform size and smooth sub-pixel camera motion does not shimmer.
// Based on code by t3ssel8r (https://youtu.be/d6tp43wZqps), Godot port by denovodavid.
shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 box_size = clamp(fwidth(UV) / TEXTURE_PIXEL_SIZE, 1e-5, 1.0);
	vec2 tx = UV / TEXTURE_PIXEL_SIZE - 0.5 * box_size;
	vec2 tx_offset = smoothstep(vec2(1.0) - box_size, vec2(1.0), fract(tx));
	vec2 uv = (floor(tx) + 0.5 + tx_offset) * TEXTURE_PIXEL_SIZE;
	COLOR = textureGrad(TEXTURE, uv, dFdx(UV), dFdy(UV));
}
