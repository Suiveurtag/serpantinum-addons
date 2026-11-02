#version 440
// Light for Clawd's revival (ClawdRevive.qml), drawn over the live desktop: the screen dims, a spotlight comes down
// on his corpse with dust glittering in it and a pool of light on the floor, a burst when he comes back, and the
// rays of his ta-da behind him. Premultiplied: the dimming is black with alpha, the light adds itself.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;     // px
    float uSpotX;   // the beam's axis, px
    float uFloor;   // where it lands, px
    float uWidth;   // half width of the beam at the floor, px
    float uTime;
    float uDim;     // 0..1 the screen dims around it
    float uBeam;    // 0..1 the beam's leading edge coming down, then its brightness
    vec2 uGlowC;    // his centre, px
    float uGlow;    // 0..1 his halo
    float uBurst;   // burst ring radius, px; < 0 none
    float uRays;    // 0..1 the ta-da sunburst
};

const float TAU = 6.2831853;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main() {
    vec2 px = qt_TexCoord0 * uSize;
    vec3 light = vec3(0.0);

    // the beam: narrow at the top of the screen, wide on the floor, soft edges, slow streaks, glittering motes
    float k = clamp(px.y / max(uFloor, 1.0), 0.0, 1.0);
    float half_ = mix(uWidth * 0.3, uWidth, k);
    float across = abs(px.x - uSpotX) / half_;
    float body = pow(clamp(1.0 - across, 0.0, 1.0), 0.7);
    float edge = clamp((uBeam * 1.25 * uFloor - px.y) / 60.0, 0.0, 1.0);   // the leading edge coming down
    float streak = 0.75 + 0.25 * noise(vec2((px.x - uSpotX) / half_ * 6.0, uTime * 0.4));
    float motes = step(0.985, hash(floor(px / 3.0) + floor(uTime * 6.0))) * step(px.y, uFloor);
    float beam = body * edge * step(px.y, uFloor + 8.0) * min(uBeam * 1.5, 1.0);
    light += vec3(1.0, 0.92, 0.7) * beam * (0.32 * streak + 0.9 * motes);

    // its pool on the floor
    vec2 e = (px - vec2(uSpotX, uFloor)) / vec2(uWidth * 1.15, uWidth * 0.2);
    light += vec3(1.0, 0.88, 0.6) * exp(-dot(e, e) * 1.6) * 0.45 * min(uBeam * 1.5, 1.0) * edge;

    // his halo, the burst ring, the sunburst behind him
    vec2 g = px - uGlowC;
    float r = length(g);
    light += vec3(1.0, 0.9, 0.62) * exp(-r / (uWidth * 0.45)) * uGlow * 0.8;
    if (uBurst >= 0.0) {
        float x = r - uBurst;
        float fade = 1.0 - smoothstep(uWidth * 0.5, uWidth * 4.0, uBurst);
        light += vec3(1.0, 0.95, 0.8) * exp(-x * x / 50.0) * fade * 1.2;
        light += vec3(1.0, 0.9, 0.7) * exp(-r / (uWidth * 0.6)) * fade * 0.9;
    }
    if (uRays > 0.0) {
        float a = atan(g.y, g.x) + uTime * 0.35;
        float rays = pow(abs(cos(a * 6.0)), 6.0);
        light += mix(vec3(1.0, 0.82, 0.4), vec3(1.0, 0.95, 0.85), rays) * rays * exp(-r / (uWidth * 1.1)) * uRays * 0.85;
        light += vec3(1.0, 0.88, 0.55) * exp(-r / (uWidth * 0.5)) * uRays * 0.35;
    }

    // dimmed everywhere the light is not
    float lit = clamp(max(light.r, max(light.g, light.b)), 0.0, 1.0);
    float dim = uDim * 0.6 * (1.0 - lit);
    float a = clamp(dim + lit, 0.0, 1.0);
    fragColor = vec4(min(light, vec3(1.0)), a) * qt_Opacity;
}
