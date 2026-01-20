shader_type canvas_item;

uniform float burn : hint_range(0.0, 1.0) = 0.0;     // 0: 正常  1: 全消失
uniform vec4 burn_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float noise_scale = 220.0;
uniform float edge = 0.06;                           // 侵蚀边缘宽度

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

void fragment() {
    vec4 col = texture(TEXTURE, UV) * COLOR;

    float n = hash21(UV * noise_scale);

    // ✅ 关键：burn=0 时阈值在 1.0，几乎不会被切掉 => 完全可见
    // burn 越大，阈值越小，被切掉的区域越多
    float thresh = 1.0 - burn;

    // cut=0 保留，cut=1 切掉
    float cut = smoothstep(thresh - edge, thresh + edge, n);

    // 边缘发黑（可选）
    col.rgb = mix(col.rgb, burn_color.rgb, cut);

    // 透明洞
    col.a *= (1.0 - cut);

    COLOR = col;
}
