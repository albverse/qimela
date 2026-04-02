shader_type canvas_item;

// 立绘闪烁 Shader（对话系统演出用）
// 用法：通过 [#portrait_shader=blink] 在对话中附着到立绘
// 效果：立绘以可调频率和强度进行白色闪烁

uniform float blink_speed : hint_range(1.0, 20.0) = 6.0;
uniform float blink_intensity : hint_range(0.0, 1.0) = 0.4;
uniform vec4 blink_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float blink = (sin(TIME * blink_speed * TAU) + 1.0) * 0.5;
	float blend = blink * blink_intensity;
	COLOR = mix(tex_color, vec4(blink_color.rgb, tex_color.a), blend);
}
