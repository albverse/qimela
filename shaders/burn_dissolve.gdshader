shader_type canvas_item;

uniform float burn = 0.0;                 // 0=开始 1=结束（由脚本Tween推动）
uniform float edge_width = 0.10;          // 腐蚀边缘宽度（0.06~0.14）
uniform float grain_scale = 180.0;        // 颗粒尺度（120~260）
uniform float speck_density = 0.90;       // 越接近1越稀疏（0.86~0.94）
uniform float fall_strength = 0.20;       // 下落拖尾强度（0.10~0.28）

uniform float u_max = 1.0;                // 端点处的 UV.x 值（决定“从手到端”归一化）
uniform float front_soft = 0.10;          // 推进前沿软化（0.06~0.18）
uniform float black_spread = 0.12;        // 黑化蔓延的前沿宽度（0.08~0.20）

uniform vec4 sand_color = vec4(0.85, 0.80, 0.66, 1.0);
uniform float darken = 0.85;              // 黑化强度（0.6~1.0）

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
	// 贴图采样用 fract，避免 Tile 模式尾巴拉伸
	vec2 uv = vec2(fract(UV.x), fract(UV.y));
	vec4 base = texture(TEXTURE, uv) * COLOR;

	// 兜底输出
	vec4 out_col = base;

	// 只有非透明部分才做溶解
	if (base.a >= 0.001) {
		float b = clamp(burn, 0.0, 1.0);

		// ✅ 计算“沿链条方向的位置” 0=手端 1=端点
		float umax = max(u_max, 0.001);
		float along = 1.0 - clamp(UV.x / umax, 0.0, 1.0);  // ✅ 矛头=0 -> 手=1

		// ✅ 推进前沿位置：b=0 在手端，b=1 到端点
		float front = b;

		// ✅ 黑化从手端向端点推进（front 附近做软边）
		float black_k = smoothstep(front - black_spread, front + black_spread, along);
		// black_k：0(手端) → 1(端点侧)，我们要“手端先黑”，所以取 1-black_k
		black_k = 1.0 - black_k;
		black_k = clamp(black_k, 0.0, 1.0);

		// ✅ 局部 burn：只有当 front 推进到该片段位置附近才开始溶解
		// local = 0 表示未开始，1 表示已彻底溶解
		float local = (front - along) / max(front_soft, 0.001);
		local = clamp(local, 0.0, 1.0);

		// 溶解噪声（仍用全局UV，让形状稳定）
		float n = noise(UV * grain_scale + vec2(0.0, TIME * 0.6));

		// 用 local 驱动阈值：local越大，阈值越高，吃掉越多
		float threshold = mix(-0.25, 1.25, local);

		// mask：1=保留 0=消失
		float mask = smoothstep(threshold - edge_width, threshold + edge_width, n);

		// dissolving：正在消失的区域强度（受 local 控制）
		float dissolving = (1.0 - mask) * local;

		// 下落拖尾：在消失区做向下取样叠加
		vec2 uv_fall = vec2(uv.x, fract(uv.y + dissolving * fall_strength));
		vec4 tail = texture(TEXTURE, uv_fall) * COLOR;

		// 稀疏沙粒点
		float g = hash21(floor((UV + vec2(TIME * 2.0, TIME * 3.0)) * (grain_scale * 1.8)));
		float speck = step(speck_density, g) * dissolving;

		// 颜色：先按“黑化蔓延”把手端慢慢变黑，再在溶解区混入沙色点
		vec3 col = base.rgb;

		// 手端→端点：黑化推进（black_k 越大越黑）
		col = mix(col, col * (1.0 - darken), black_k);

		// 溶解区沙粒颜色
		col = mix(col, sand_color.rgb, speck * 0.9);

		// alpha：主体按 mask 渐隐；拖尾只在 dissolving 时存在一点点
		float a_main = base.a * mask;
		float a_tail = tail.a * dissolving * 0.35;
		float a = clamp(a_main + a_tail, 0.0, 1.0);

		out_col = vec4(col, a);
	}

	COLOR = out_col;
}
