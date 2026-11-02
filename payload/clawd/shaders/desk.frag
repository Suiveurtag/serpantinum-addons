#version 440
// The frozen desktop behind Clawd's singularity (ClawdBlast.qml): a freeze tear, then its light streaks toward him and
// drains away from the edges in; after the blast it comes back lit by the explosion, negative behind the shock front.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;     // px
    vec2 uCenter;   // Clawd's centre, px
    float uTime;
    float uFreeze;  // 0..1 tear when the screen freezes
    float uDrain;   // 0..1 light drained out of the screen
    float uPull;    // 0..1 how hard the light streams toward him
    float uLit;     // 0..1 the desktop lit again by the blast
    float uNeg;     // 0..1 negative behind the shock front
    float uFront;   // shock front radius, px
};
layout(binding = 1) uniform sampler2D uDesk;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec3 desk(vec2 px) {
    vec2 uv = px / uSize;
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec3(0.0);
    return texture(uDesk, uv).rgb;
}

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
    vec2 px = qt_TexCoord0 * uSize;

    // freeze: a few torn scanline bands for an instant
    if (uFreeze > 0.0) {
        float band = floor(px.y / 7.0);
        float on = step(1.0 - uFreeze * 0.3, hash(vec2(band, floor(uTime * 40.0))));
        px.x += on * (hash(vec2(band, 3.7)) - 0.5) * 40.0 * uFreeze;
    }

    vec2 toward = uCenter - px;
    float r = length(toward);
    float far = length(max(uCenter, uSize - uCenter));

    // light streaming in: samples taken farther out, so everything smears toward him
    vec3 col = vec3(0.0);
    float total = 0.0;
    for (int i = 0; i < 8; i++) {
        float k = float(i) / 7.0;
        float w = 1.0 - k * 0.6;
        col += desk(px - toward * k * uPull * 0.07) * w;
        total += w;
    }
    col /= total;

    if (uLit <= 0.0) {
        // drained from the edges inward, greyer and colder as it goes
        float edge = clamp(r / far, 0.0, 1.0);
        float d = smoothstep(0.0, 1.0, uDrain * 1.55 - (1.0 - edge) * 0.55);
        col = mix(col, vec3(luma(col)), d * 0.8) * mix(vec3(1.0), vec3(0.7, 0.78, 1.15), d);
        col *= pow(1.0 - d, 1.4);
    } else {
        // behind the shock front: lit again, first as a violet negative
        float inside = 1.0 - smoothstep(uFront - 60.0, uFront, r);
        vec3 neg = (1.0 - col) * vec3(0.78, 0.62, 1.0) + vec3(0.06, 0.0, 0.12);
        col = mix(col, neg, uNeg);
        col *= uLit * inside;
    }
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
