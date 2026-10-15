shader_type canvas_item;

uniform vec4 color_top : source_color = vec4(0.14, 0.19, 0.29, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.10, 0.13, 0.20, 1.0);
uniform float radius = 22.0;
uniform vec2 rect_size = vec2(400.0, 200.0);
uniform float shadow_blur = 18.0;
uniform float shadow_alpha = 0.22;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float border_width = 3.0;
uniform vec4 border_color : source_color = vec4(1.0, 0.82, 0.38, 0.8);

float rounded_box_sd(vec2 p, vec2 size, float r) {
    vec2 d = abs(p) - size + vec2(r);
    return length(max(d, vec2(0.0))) - r + min(max(d.x, d.y), 0.0);
}

void fragment() {
    vec2 uv = UV * rect_size;
    vec2 center = rect_size * 0.5;
    vec2 p = uv - center;
    vec2 half_size = center;
    
    float sd = rounded_box_sd(p, half_size, radius);
    
    if (sd > 0.5) {
        // 圆角外 - 柔和阴影
        float shadow_dist = max(sd, 0.0);
        float shadow_fade = 1.0 - smoothstep(0.0, shadow_blur, shadow_dist);
        COLOR = vec4(shadow_color.rgb, shadow_alpha * shadow_fade);
    } else if (sd > -(border_width - 0.5)) {
        // 边框区域
        COLOR = border_color;
    } else {
        // 内部 - 渐变
        float t = clamp(uv.y / rect_size.y, 0.0, 1.0);
        vec3 col = mix(color_top.rgb, color_bottom.rgb, t);
        COLOR = vec4(col, 1.0);
    }
}