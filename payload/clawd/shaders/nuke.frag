#version 440
// The frozen desktop behind Clawd's nuclear variant (ClawdNuke.qml): a red alarm while he panics, the slow-motion grade
// (grey, cold, a camera push toward him, heartbeats), the black-and-white impact frames, then the desktop lit by the
// fireball, scorched, rippling in its heat, crossed by the shock front.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;     // px
    vec2 uClawd;    // his centre, px
    vec2 uFireC;    // the fireball's centre, px
    vec2 uGround;   // ground zero, px
    float uTime;
    float uAlarm;   // 0..1 red alarm
    float uSlow;    // 0..1 slow-motion grade
    float uPush;    // 0..1 camera push toward him
    float uBeat;    // 0..1 a heartbeat
    float uImpact;  // 0 none, 1 white with black spokes, 2 black with white spokes
    float uFire;    // fireball light, > 1 is blinding
    float uBurn;    // 0..1 scorched grade
    float uShock;   // shock front radius, px; < 0 none
    float uHaze;    // 0..1 heat shimmer
};
layout(binding = 1) uniform sampler2D uDesk;

const float TAU = 6.2831853;

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 desk(vec2 px) { return texture(uDesk, clamp(px / uSize, vec2(0.0), vec2(1.0))).rgb; }

void main() {
    vec2 px = qt_TexCoord0 * uSize;
    vec2 uv = px / uSize - 0.5;
    float vig = length(uv * vec2(1.25, 1.0));

    if (uImpact > 0.5) {
        // impact frames: spokes bursting from him, hard two-tone
        vec2 v = px - uClawd;
        float a = atan(v.y, v.x) / TAU + 0.5;
        float seg = floor(a * 90.0);
        float n = hash(seg + floor(uImpact) * 13.0);
        float spoke = step(0.58, n) * step(uSize.y * (0.08 + 0.25 * hash(seg + 7.0)), length(v));
        float ink = uImpact < 1.5 ? spoke : 1.0 - spoke;
        fragColor = vec4(vec3(1.0 - ink), 1.0) * qt_Opacity;
        return;
    }

    // camera push toward him, heat shimmer above the fire
    vec2 sp = uClawd + (px - uClawd) / (1.0 + 0.08 * uPush);
    if (uHaze > 0.0) {
        float k = exp(-length((px - uFireC) * vec2(1.6, 0.8)) / (uSize.y * 0.45)) * uHaze;
        sp += vec2(sin(px.y * 0.045 + uTime * 9.0) * 4.0, cos(px.x * 0.03 + uTime * 6.5) * 2.5) * k;
    }
    vec3 col = desk(sp);
    float l = luma(col);

    // the alarm: red pulsing in from the edges
    if (uAlarm > 0.0) {
        float pulse = 0.5 + 0.5 * sin(uTime * 13.0);
        float edge = smoothstep(0.25, 0.8, vig);
        col = mix(col, col * vec3(1.0, 0.45, 0.4), uAlarm * 0.35);
        col += vec3(0.75, 0.04, 0.04) * edge * pulse * uAlarm * 0.6;
    }

    // slow motion: the world goes grey and cold, the edges close in, each heartbeat squeezes them
    if (uSlow > 0.0) {
        col = mix(col, vec3(l) * vec3(0.86, 0.93, 1.08), 0.88 * uSlow);
        col *= 1.0 - uSlow * (0.25 + 0.6 * smoothstep(0.15, 0.85, vig));
        col *= 1.0 - uBeat * 0.55 * smoothstep(0.05, 0.6, vig);
    }

    // the fireball: scorched, lit by it, white-hot at first then orange and red
    if (uFire > 0.0 || uBurn > 0.0) {
        vec3 burnt = mix(col, vec3(l) * vec3(1.1, 0.72, 0.45), 0.65 * uBurn) * (1.0 - 0.4 * uBurn * smoothstep(0.1, 0.8, vig));
        float d = length((px - uFireC) / uSize.y);
        float light = uFire / (1.0 + d * d * 14.0);
        vec3 lc = mix(vec3(1.0, 0.38, 0.12), vec3(1.0, 0.93, 0.78), clamp(uFire - 0.5, 0.0, 1.0));
        col = burnt + lc * light * (0.45 + 0.8 * l);
    }

    // the shock front: a thin bright shell, darker just behind it
    if (uShock > 0.0) {
        float r = length(px - uGround);
        float x = r - uShock;
        float fade = 1.0 - smoothstep(uSize.y * 0.6, uSize.y * 1.9, uShock);
        col += vec3(1.0, 0.92, 0.82) * exp(-x * x / 30.0) * 0.55 * fade;
        col *= 1.0 - 0.25 * exp(-(x + 40.0) * (x + 40.0) / 900.0) * fade;
    }
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
