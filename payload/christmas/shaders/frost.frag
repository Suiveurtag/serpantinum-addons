#version 440
// Frost that grows in from one edge of a rounded rectangle. Sizes are in
// pixels, so the crystals keep their scale on any row size. No texture, blur
// or time uniform: the item only redraws while `energy` animates.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float intensity;
    float energy;        // how far the frost has grown, 0..1
    float direction;     // origin: 1 left, -1 right, 2 bottom, 0 every edge
    float cornerRadius;
    vec2 extent;
    vec4 tint;
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float ridge(vec2 p) { return 1.0 - abs(noise(p) * 2.0 - 1.0); }

float frost(vec2 px) {
    float d, span;
    if (direction > 1.5) { d = extent.y - px.y; span = extent.y; }
    else if (direction > 0.5) { d = px.x; span = extent.x; }
    else if (direction < -0.5) { d = extent.x - px.x; span = extent.x; }
    else { d = min(min(px.x, extent.x - px.x), min(px.y, extent.y - px.y)); span = min(extent.x, extent.y) * 0.5; }
    // From a side edge, the frost also creeps a little faster along the top and bottom borders.
    if (abs(direction) > 0.5 && direction < 1.5)
        d *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 9.0, min(px.y, extent.y - px.y)));
    float front = energy * max(60.0, span * 0.62) - d + (noise(px / 9.0) - 0.5) * 26.0 + (noise(px / 3.1) - 0.5) * 8.0;
    float cover = smoothstep(0.0, 18.0, front);
    vec2 p = px / 14.0;
    float vein = pow(ridge(p), 7.0) * 0.7 + pow(ridge(p * 2.3 + 4.1), 9.0) * 0.5 + pow(ridge(p * 4.7 + 1.3), 11.0) * 0.35;
    float haze = 0.14 + 0.2 * exp(-d / 26.0);
    float frontier = exp(-pow(front / 5.0, 2.0)) * 0.35 * step(0.001, energy);
    return (vein + haze) * cover + frontier;
}

void main() {
    vec2 px = qt_TexCoord0 * extent;
    vec2 halfSize = extent * 0.5;
    float r = min(cornerRadius, min(halfSize.x, halfSize.y));
    vec2 sq = abs(px - halfSize) - halfSize + vec2(r);
    float dist = length(max(sq, vec2(0))) + min(max(sq.x, sq.y), 0.0) - r;
    float border = smoothstep(-9.0, -3.0, dist) * (1.0 - smoothstep(-1.0, 0.0, dist));
    float alpha = clamp(frost(px) * intensity, 0.0, 1.0) * border * qt_Opacity;
    fragColor = vec4(tint.rgb * alpha, alpha);
}
