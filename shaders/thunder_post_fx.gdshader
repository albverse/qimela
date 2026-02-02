shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// 主强度：0=无效果，1=最强
uniform float amount : hint_range(0.0, 1.0) = 0.0;

// 闪电“瞬间白闪”（独立控制，比 amount 更像雷）
uniform float flash : hint_range(0.0, 1.0) = 0.0;

// 对比度（只作用在亮度上）
uniform float contrast : hint_range(1.0, 4.0) = 2.4;

// 深灰压色范围：越低越“黑”，越高越“灰亮”
uniform float gray_low  : hint_range(0.0, 1.0) = 0.10;
uniform float gray_high : hint_range(0.0, 1.0) = 0.62;

// 保留一点原始颜色（建议 0.03~0.10；越大越“彩”）
uniform float color_retain : hint_range(0.0, 0.25) = 0.06;

// 白闪强度（建议 0.10~0.25，太大就刺眼且发白）
uniform float flash_strength : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	vec4 src = textureLod(screen_texture, SCREEN_UV, 0.0);

	// 亮度（灰度基准）
	float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));

	// 只对亮度做对比度增强（避免把颜色“艳起来”）
	float l = clamp((luma - 0.5) * contrast + 0.5, 0.0, 1.0);

	// 把亮度映射到“深灰范围”（压色核心）
	vec3 deep_gray = mix(vec3(gray_low), vec3(gray_high), l);

	// 只保留少量原始颜色，避免全彩
	vec3 muted = mix(deep_gray, src.rgb, color_retain);

	// amount 控制从原画面过渡到 muted
	vec3 col = mix(src.rgb, muted, amount);

	// 闪电瞬间白闪（只短促出现，不会让整体变艳）
	col = mix(col, vec3(1.0), flash * flash_strength);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}