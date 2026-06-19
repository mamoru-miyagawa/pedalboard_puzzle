shader_type canvas_item;

uniform sampler2D mask : hint_default_white;

void fragment() {
	float mask_alpha = texture(mask, UV).a;
	if (mask_alpha < 0.5) {
		discard;
	}
}
