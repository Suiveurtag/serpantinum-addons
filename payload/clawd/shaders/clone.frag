#version 440
// Recolours a white-bodied sprite (clone.png, or a surge.png pose) on its own pixel grid (ClawdSurge.qml): the helpers'
// effort colours. Mode 0 flat colour; 1 xhigh: a white glint sweeping across now and then; 2 max: Claude Code's light
// colours flowing through him; 3 ultra: electric cyan, crackling white; 4 silhouette: every opaque pixel uColor.
// uReveal < 1: only the rows above it are there yet, a scanline at the edge (materialising).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uColor;
    float uMode;
    float uTime;
    float uReveal;   // 0..1 from the top
    vec2 uGrid;      // the sprite's size in its own pixels
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
// no arrays indexed at run time: some GL drivers drop the whole shader
vec3 tone(float i) {
    if (i < 0.5) return vec3(1.0, 0.62, 0.48);
    if (i < 1.5) return vec3(1.0, 0.85, 0.40);
    if (i < 2.5) return vec3(0.56, 0.89, 0.63);
    if (i < 3.5) return vec3(0.61, 0.83, 1.0);
    if (i < 4.5) return vec3(0.79, 0.71, 1.0);
    return vec3(1.0, 0.61, 0.69);
}
vec3 rainbow(float k) {
    k = fract(k) * 6.0;
    float i = floor(k);
    return mix(tone(i), tone(mod(i + 1.0, 6.0)), smoothstep(0.0, 1.0, fract(k)));
}

void main() {
    vec2 cell = floor(qt_TexCoord0 * uGrid);
    vec2 uv = (cell + 0.5) / uGrid;
    vec4 s = texture(source, uv);
    if (s.a < 0.01) { fragColor = vec4(0.0); return; }
    vec3 rgb = s.rgb / s.a;
    bool body = min(rgb.r, min(rgb.g, rgb.b)) > 0.985;
    vec3 c = rgb;
    if (uMode > 3.5) c = uColor.rgb;
    else if (body) {
        c = uColor.rgb;
        if (uMode > 0.5 && uMode < 1.5) {
            float sweep = fract(uTime * 0.33);
            float band = abs((cell.x + cell.y * 0.6) / (uGrid.x * 1.6) - sweep * 1.6 + 0.3);
            c = mix(c, vec3(1.0), smoothstep(0.08, 0.0, band) * 0.9);
        } else if (uMode > 1.5 && uMode < 2.5) {
            c = rainbow((cell.x + cell.y) / 22.0 - uTime * 0.6);
        } else if (uMode > 2.5) {
            float n = floor(uTime * 18.0);
            float crack = step(0.93, hash(cell + n));
            c = mix(c, vec3(1.0), crack) * (0.9 + 0.2 * step(0.5, hash(vec2(n, 1.0))));
        }
    }
    float a = s.a;
    if (uReveal < 1.0) {
        float row = cell.y / uGrid.y;
        float edge = step(row, uReveal + 0.08) * step(uReveal - 0.001, row);
        a *= step(row, uReveal);
        c = mix(c, vec3(1.0), edge);
        a = max(a, edge * s.a * step(0.4, hash(cell + floor(uTime * 30.0))));
    }
    fragColor = vec4(c * a, a) * qt_Opacity;
}
