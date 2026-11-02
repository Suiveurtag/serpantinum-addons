#version 440
// Clawd's singularity light (ClawdBlast.qml), drawn on his pixel grid and added over the desktop (alpha 0):
// the light threads he pulls out of the screen and his halo, then the antimatter annihilation: flash, plasma shell,
// shock rings, equatorial ring, gamma rays, particle/antiparticle spiral tracks and sparks.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;     // px
    vec2 uCenter;   // Clawd's centre, px
    vec2 uBody;     // half his size, px
    float uPixel;   // his pixel, px: everything snaps to it
    float uTime;
    float uFlow;    // integrated suction: how far the threads have travelled
    float uSuck;    // 0..1 how many threads, how long, how bright
    float uGlow;    // 0..1 the light he gives off
    float uBlast;   // seconds since the annihilation, < 0 before
    float uStill;   // 0..1 the silence before it: no rays
};
layout(binding = 1) uniform sampler2D uDesk;

const float TAU = 6.2831853;

float hash1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
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
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; }
    return v;
}
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// distance to segment a-b, and where along it (0 at a)
float segment(vec2 p, vec2 a, vec2 b, out float along) {
    vec2 ab = b - a;
    along = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
    return length(p - a - ab * along);
}
float box(vec2 p, vec2 half_) {
    vec2 d = abs(p) - half_;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
vec2 polar(float r, float a) { return vec2(cos(a), sin(a)) * r; }

vec3 threads(vec2 px, float far) {
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 64; i++) {
        float f = float(i);
        float h1 = hash1(f * 1.31 + 0.7), h2 = hash1(f * 7.17 + 3.1), h3 = hash1(f * 3.71 + 11.3);
        if (h3 > uSuck * 1.15) continue;
        float ph = fract(h1 + uFlow * (0.55 + 0.9 * h2));
        float a0 = h2 * TAU;
        float r0 = far * (0.45 + 0.6 * h1);
        float twist = (0.6 + 0.9 * h3) * (h1 > 0.5 ? 1.0 : -1.0);
        float headR = r0 * pow(1.0 - ph, 1.6);
        float tailPh = max(ph - (0.06 + 0.22 * uSuck), 0.0);
        float tailR = r0 * pow(1.0 - tailPh, 1.6);
        vec2 head = uCenter + polar(headR, a0 + twist * ph * ph);
        vec2 tail = uCenter + polar(tailR, a0 + twist * tailPh * tailPh);
        float along;
        float d = segment(px, tail, head, along);
        float width = uPixel * (0.8 + 1.1 * h3 * uSuck);
        float line = 1.0 - smoothstep(width * 0.5, width, d);
        if (line <= 0.0) continue;
        // its colour is the light of the desktop where it was torn from, brightened
        vec3 c = texture(uDesk, clamp((uCenter + polar(r0, a0)) / uSize, 0.0, 1.0)).rgb;
        c = max(mix(vec3(luma(c)), c, 1.6), 0.0) * 1.3 + vec3(0.25, 0.22, 0.3);
        float fade = along * along * smoothstep(0.0, 0.12, ph) * smoothstep(length(uBody) * 0.6, length(uBody) * 1.4, headR);
        acc += c * line * fade * (0.8 + 1.3 * uSuck);
    }
    // motes: single pixels falling in fast
    for (int i = 0; i < 40; i++) {
        float f = float(i);
        float h1 = hash1(f * 2.13 + 41.0), h2 = hash1(f * 5.77 + 13.0);
        if (h2 > uSuck * 1.3) continue;
        float ph = fract(h1 * 3.1 + uFlow * (1.4 + 1.6 * h2));
        float rr = far * (0.15 + 0.85 * h1) * pow(1.0 - ph, 2.2);
        vec2 p = uCenter + polar(rr, h2 * TAU + ph * 1.2);
        vec2 d = abs(px - p);
        if (max(d.x, d.y) < uPixel * 0.6) acc += vec3(0.9, 0.95, 1.0) * smoothstep(0.0, 0.2, ph) * smoothstep(length(uBody), length(uBody) * 1.5, rr);
    }
    return acc;
}

vec3 halo(vec2 px) {
    vec2 v = px - uCenter;
    // a soft ellipse around his body rather than his box
    float d = max(mix(box(v, uBody), (length(v / uBody) - 1.0) * min(uBody.x, uBody.y), 0.6), 0.0);
    float a = atan(v.y, v.x);
    float g = uGlow;
    vec3 warm = mix(vec3(1.0, 0.62, 0.42), vec3(0.95, 0.93, 1.0), smoothstep(0.3, 0.9, g));
    float inner = exp(-d / (6.0 + 26.0 * g));
    float outer = exp(-d / (40.0 + 150.0 * g));
    float flick = 0.85 + 0.15 * noise(vec2(a * 3.0, uTime * 9.0));
    float rays = pow(max(sin(a * 9.0 + 2.0 * noise(vec2(a * 2.0, uTime * 0.7))), 0.0), 14.0)
               + pow(max(sin(a * 5.0 - uTime * 0.6), 0.0), 30.0);
    rays *= exp(-d / (30.0 + 200.0 * g)) * smoothstep(0.55, 1.0, g) * (1.0 - uStill * 0.75);
    // where the threads are swallowed: a ring that pulses with the suction
    float ring = exp(-pow((d - 6.0 * uPixel * (1.0 - 0.5 * fract(uFlow * 3.0))) / (uPixel * 1.5), 2.0)) * uSuck * 0.5;
    return warm * (inner * 1.4 * g + outer * 0.4 * g * g + rays * 0.35 + ring) * flick;
}

vec3 annihilation(vec2 px, float t) {
    vec2 v = px - uCenter;
    float r = length(v);
    float a = atan(v.y, v.x);
    float H = uSize.y, W = uSize.x;
    vec3 acc = vec3(0.0);
    float energy = exp(-t * 0.9);

    // the flash
    acc += vec3(1.0, 0.97, 1.0) * exp(-t * 40.0) * 1.5;

    // plasma shell: a sphere of pure energy, turbulent rim, violet void inside with bright filaments
    float R = H * 0.6 * (1.0 - exp(-t * 2.6)) + 1.0;
    vec2 dir = v / max(r, 1.0);
    float n = fbm(dir * 2.6 + vec2(t * 0.35, -t * 0.2) + r / H * 1.5);
    float edgeR = R * (0.94 + 0.14 * n);
    float shellW = H * 0.012 + R * 0.05;
    float shell = exp(-pow((r - edgeR) / shellW, 2.0));
    vec3 rim = mix(vec3(0.6, 0.98, 1.0), vec3(1.0, 0.32, 0.86), smoothstep(0.35, 0.7, n));
    acc += rim * shell * (0.35 + 1.8 * energy) * smoothstep(5.5, 3.0, t);
    float inside = 1.0 - smoothstep(edgeR * 0.8, edgeR, r);
    float fil = pow(1.0 - abs(fbm(v / (R + 40.0) * 3.2 + vec2(t * 0.5, t * 0.3)) * 2.0 - 1.0), 9.0);
    acc += inside * (vec3(0.32, 0.08, 0.72) * 0.22 + vec3(0.65, 0.92, 1.0) * fil * 1.1) * energy * energy;

    // shock rings: fast white-cyan with a chromatic fringe, slower broken magenta
    float r1 = H * 1.9 * (1.0 - exp(-t * 1.5));
    float w1 = 5.0 + 10.0 * t;
    acc += vec3(exp(-pow((r - r1 - 6.0) / w1, 2.0)), exp(-pow((r - r1) / w1, 2.0)), exp(-pow((r - r1 + 6.0) / w1, 2.0))) * 1.4 * exp(-t * 0.9);
    float r2 = H * 1.15 * (1.0 - exp(-t * 0.9));
    float broken = smoothstep(0.35, 0.6, fbm(dir * 4.0 + t * 0.4));
    acc += vec3(1.0, 0.3, 0.85) * exp(-pow((r - r2) / (12.0 + 18.0 * t), 2.0)) * broken * 0.9 * exp(-t * 0.7);

    // equatorial ring: a flat disc of matter flung sideways
    float e = length(vec2(v.x, v.y / 0.13));
    float re = W * 0.95 * (1.0 - exp(-t * 1.2));
    float sparkle = 0.6 + 0.8 * noise(vec2(a * 40.0, t * 3.0));
    acc += mix(vec3(0.65, 0.95, 1.0), vec3(1.0), 0.4) * exp(-pow((e - re) / (10.0 + 40.0 * t), 2.0)) * sparkle * 1.2 * exp(-t * 1.1);
    acc += vec3(0.5, 0.3, 1.0) * exp(-abs(v.y) / (3.0 + 4.0 * t)) * smoothstep(re * 1.02, re * 0.2, abs(v.x)) * 0.35 * exp(-t * 0.8);

    // gamma rays
    float flick = step(0.35, hash(vec2(floor(a * 4.0), floor(uTime * 24.0))));
    float rays = pow(abs(sin(a * 9.0 + 0.4 * sin(t * 3.0 + a * 5.0))), 260.0) * (0.4 + 0.6 * flick) + pow(abs(sin(a * 5.0 + 1.1 + t * 0.2)), 400.0) * 1.5;
    acc += vec3(0.85, 0.95, 1.0) * rays * exp(-t * 2.2) / (1.0 + r / (H * 0.4)) * 0.9;

    // particle/antiparticle pairs: spiral tracks curling away from the centre, cyan one way, magenta the other
    for (int i = 0; i < 14; i++) {
        float f = float(i);
        float hand = mod(f, 2.0) < 1.0 ? 1.0 : -1.0;
        float A = H * (0.07 + 0.2 * hash1(f * 3.3 + 1.0));
        float th0 = hash1(f * 9.1 + 2.0) * TAU;
        float b = 0.16 + 0.1 * hash1(f * 4.4);
        float start = 0.05 + 0.5 * hash1(f * 6.1 + 5.0);
        float phiMax = 13.0 * (1.0 - exp(-max(t - start * 0.4, 0.0) * 2.2));
        vec2 O = uCenter + polar(H * 0.05 * hash1(f + 7.0), hash1(f + 8.0) * TAU) - polar(A, th0);
        vec2 q = px - O;
        float rho = length(q);
        float ang = mod(hand * (atan(q.y, q.x) - th0), TAU);
        float est = -log(max(rho, 0.5) / A) / b;
        float phi = ang + TAU * floor((est - ang) / TAU + 0.5);
        if (phi < 0.0 || phi > phiMax) continue;
        float d = abs(rho - A * exp(-b * phi));
        float line = 1.0 - smoothstep(uPixel * 0.35, uPixel * 0.9, d);
        vec3 c = hand > 0.0 ? vec3(0.35, 0.95, 1.0) : vec3(1.0, 0.35, 0.9);
        acc += c * line * (0.3 + 0.9 * exp(-(phiMax - phi) * 0.6)) * smoothstep(3.8, 1.5, t);
    }

    // sparks
    for (int i = 0; i < 70; i++) {
        float f = float(i);
        float sp = H * (0.25 + 1.2 * hash1(f * 1.7 + 3.0));
        vec2 p = uCenter + polar(sp * (1.0 - exp(-t * 2.2)), hash1(f * 8.3) * TAU);
        vec2 d = abs(px - p);
        if (max(d.x, d.y) < uPixel * 0.6) {
            vec3 c = mod(f, 3.0) < 1.0 ? vec3(1.0) : mod(f, 3.0) < 2.0 ? vec3(0.4, 0.95, 1.0) : vec3(1.0, 0.4, 0.9);
            acc += c * (0.5 + 0.5 * step(0.5, hash(vec2(f, floor(uTime * 20.0))))) * smoothstep(3.0, 1.0, t);
        }
    }

    // what stays: a violet-magenta nebula where the shell was, for the black hole to take back
    float neb = fbm(v / H * 3.0 + vec2(3.7, 1.3) + t * 0.05);
    float band = exp(-pow((r - H * 0.42) / (H * 0.2), 2.0)) + 0.6 * exp(-r / (H * 0.12));
    acc += mix(vec3(0.3, 0.1, 0.6), vec3(0.9, 0.3, 0.8), neb) * pow(neb, 2.0) * band * 0.75 * smoothstep(0.4, 2.0, t);
    return acc;
}

void main() {
    vec2 px = (floor(qt_TexCoord0 * uSize / uPixel) + 0.5) * uPixel;
    float far = length(max(uCenter, uSize - uCenter));
    vec3 acc = vec3(0.0);
    if (uSuck > 0.0) acc += threads(px, far);
    if (uGlow > 0.0) acc += halo(px);
    if (uBlast >= 0.0) acc += annihilation(px, uBlast);
    fragColor = vec4(acc, 0.0) * qt_Opacity;
}
