shader_type canvas_item;

uniform float burn = 0.0;          // 0->1
uniform float edge_width = 0.18;   // 边缘柔和程度
uniform float grain_scale = 170.0; // 颗粒大小（越大越细）

float hash21(vec2 p){
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float noise(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment(){
	// Tile 采样防拉伸
	vec2 uv = vec2(fract(UV.x), fract(UV.y));
	vec4 base = texture(TEXTURE, uv) * COLOR;

	// 默认输出：原样
	vec4 out_col = base;

	// 只有在可见像素上做溶解
	float b = clamp(burn, 0.0, 1.0);
	if (base.a >= 0.001){
		float n = noise(UV * grain_scale);

		// burn 越大阈值越高 -> 吃掉越多
		float threshold = mix(-0.35, 1.35, b);
		float mask = smoothstep(threshold - edge_width, threshold + edge_width, n);

		out_col = vec4(base.rgb, base.a * mask);
	}

	COLOR = out_col;
}
