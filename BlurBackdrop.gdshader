shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float blur_radius : hint_range(0.0, 12.0) = 4.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(screen, 0));
	vec4 blurred = vec4(0.0);
	int samples = 0;

	int r = int(blur_radius);
	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			if (abs(x) + abs(y) <= r) {
				blurred += texture(screen, SCREEN_UV + vec2(float(x), float(y)) * texel * blur_radius);
				samples++;
			}
		}
	}
	blurred /= float(samples);
	blurred.rgb *= (1.0 - darken);

	vec4 original = texture(screen, SCREEN_UV);
	original.rgb *= (1.0 - darken);
	COLOR = mix(original, blurred, strength);
}
