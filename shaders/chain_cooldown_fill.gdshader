shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (UV.y < 1.0 - progress) {
		tex.a = 0.0;
	}
	COLOR = tex * COLOR;
}
