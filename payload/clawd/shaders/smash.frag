#version 440
// Clawd's blast KO off a screen edge (ClawdSmash.qml), on his pixel grid, cel-shaded: the contact star, the jet blown
// back into the screen (dark rim, crimson, his effort colour, orange, yellow, white core) with its crackling bolts, the
// fan of spikes, the shock rings, the sparks, then the smoke that lingers once the jet is gone.
// Local frame: u runs from the exit point into the screen (uDir), v across it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;     // px
    vec2 uOrigin;   // exit point, px
    vec2 uDir;      // unit, into the screen
    vec4 uColor;    // his effort colour (or his own orange)
    float uTime;    // s since the blast, < 0 before it
    float uPixel;   // his pixel, px: everything snaps to it
    float uSeed;    // 0..1, a different blast every time
    float uLow;     // reduced motion: a short glint only
    float uScale;   // blast size, 0.3 (just hard enough for a KO) to 1.2 (thrown as hard as it goes)
};

const float PI = 3.14159265;

float hash1(float n) { return fract(sin(n * 127.1 + uSeed * 311.7) * 43758.5453); }
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
    for (int i = 0; i < 3; i++) { v += a * noise(p); p = p * 2.07 + vec2(17.1, 9.2); a *= 0.5; }
    return v / 0.875;
}
float ease(float x) { x = clamp(x, 0.0, 1.0); return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x); }
float fill(float sd) { return clamp(0.5 - sd / max(uPixel, 1.0), 0.0, 1.0); }  // signed distance px -> coverage
void over(inout vec4 acc, vec3 c, float a) { a = clamp(a, 0.0, 1.0); acc = vec4(c * a, a) + acc * (1.0 - a); }
vec2 turn(vec2 d, float a) { float c = cos(a), s = sin(a); return vec2(d.x * c - d.y * s, d.x * s + d.y * c); }
// four-point star (astroid) of radii r, < 0 inside
float star(vec2 q, vec2 r) { return sqrt(abs(q.x) / r.x) + sqrt(abs(q.y) / r.y) - 1.0; }
float segment(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    return length(p - a - ab * clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0));
}
// the jet's half-width at s (0 at the edge, 1 at its tip): flared at the base, then a long taper
float profile(float s) { return pow(max(1.0 - s, 0.0), 0.75) * (1.0 + 0.7 * exp(-s * 6.0)); }

void main() {
    vec2 frag = qt_TexCoord0 * uSize;
    vec2 g = uPixel > 1.0 ? (floor(frag / uPixel) + 0.5) * uPixel : frag;
    float t = uTime;
    vec4 acc = vec4(0.0);
    if (t < 0.0) { fragColor = acc; return; }
    vec2 n = vec2(-uDir.y, uDir.x);
    vec2 p = g - uOrigin;
    float u = dot(p, uDir), v = dot(p, n);
    float S = min(uSize.x, uSize.y);
    float reach = min(S * 0.82, 900.0) * uScale;
    float size = min(130.0, reach * 0.18);
    vec3 white = vec3(1.0, 0.99, 0.93), yellow = vec3(1.0, 0.86, 0.36), orange = vec3(1.0, 0.6, 0.2);
    vec3 crimson = vec3(1.0, 0.17, 0.36), ink = vec3(0.16, 0.05, 0.14);
    vec3 player = mix(vec3(1.0, 0.38, 0.24), uColor.rgb, 0.55);  // slightly altered by his effort colour

    if (uLow > 0.5) {
        float k = t / 0.25;
        if (k < 1.0) {
            float r = size * 0.5 * (1.0 - 0.5 * k);
            if (star(vec2(u - r * 0.3, v), vec2(r, r * 0.7)) < 0.0) over(acc, white, 1.0 - k);
        }
        fragColor = acc * qt_Opacity;
        return;
    }

    // the hit's flash over the whole screen
    over(acc, mix(white, player, 0.3), 0.22 * exp(-t / 0.045));

    // smoke: rolls in after the jet, drifts up and away from the edge, lingers
    for (int i = 0; i < 12; i++) {
        float f = float(i), h1 = hash1(f * 1.37 + 2.0), h2 = hash1(f * 4.11 + 5.0), h3 = hash1(f * 7.73 + 9.0);
        float k = (t - 0.14 - 0.03 * f) / (0.8 + 0.3 * h3);
        if (k <= 0.0 || k >= 1.0) continue;
        float along = reach * (0.03 + 0.3 * h1 * h1) * (0.6 + 0.4 * ease(k));
        vec2 c = uOrigin + uDir * along + n * (h2 - 0.5) * size * 1.8 + vec2(0.0, -size * 0.9 * k);
        float r = size * (0.3 + 0.3 * h3) * (0.5 + 0.7 * ease(k * 1.8)) * (1.0 - 0.6 * k * k * k);
        vec2 q = g - c;
        float body = fill(length(q) - r);
        if (body <= 0.0) continue;
        float shade = length(q - vec2(0.0, r * 0.3)) > r * 0.95 ? 0.0 : 1.0;          // a darker underside...
        float lit = length(q + vec2(r * 0.3, r * 0.38)) < r * 0.55 ? 1.0 : 0.0;       // ...and a lit cap
        vec3 c0 = mix(vec3(0.34, 0.3, 0.38), vec3(0.24, 0.2, 0.28), 1.0 - shade);
        over(acc, mix(c0, vec3(0.62, 0.58, 0.64), lit), body * 0.9 * min(1.0, (1.0 - k) * 2.2));
    }

    // the jet's timing
    float grow = ease(t / 0.085);
    float decay = 1.0 - ease((t - 0.2) / 0.48);
    float L = reach * (0.22 + 0.78 * grow) * (0.5 + 0.5 * decay);
    float B = size * (0.45 + 0.55 * ease(t / 0.05)) * decay;

    // the fan of spikes behind it: shoot out, then their base catches up with their tip
    for (int i = 0; i < 9; i++) {
        float f = float(i), h1 = hash1(f * 3.17 + 1.0), h2 = hash1(f * 5.71 + 3.0);
        float k = (t - 0.012 * f) / (0.34 + 0.16 * h2);
        if (k <= 0.0 || k >= 1.0) continue;
        float a = (f / 8.0 - 0.5) * 2.3 + (h1 - 0.5) * 0.25;
        float len = reach * (0.32 + 0.5 * h2) * (1.0 - 0.45 * abs(a) / 1.3);
        float head = len * ease(k * 2.2), tail = len * ease((k - 0.2) * 1.5);
        vec2 d = turn(uDir, a);
        float ru = dot(p, d), rv = dot(p, vec2(-d.y, d.x));
        if (ru < tail || ru > head || head - tail < 1.0) continue;
        float w = size * (0.15 + 0.08 * h1) * (1.0 - (ru - tail) / (head - tail)) * (1.0 - k * 0.6);
        float rim = fill(abs(rv) - w), core = fill(abs(rv) - w * 0.42);
        over(acc, mod(f, 2.0) < 0.5 ? player : crimson, rim);
        over(acc, mod(f, 3.0) < 0.5 ? yellow : white, core);
    }

    // shock rings, squashed into the screen as if seen on its glass
    for (int i = 0; i < 2; i++) {
        float f = float(i);
        float k = (t - 0.025 - 0.08 * f) / 0.5;
        if (k <= 0.0 || k >= 1.0) continue;
        float r = size * (0.5 + (4.6 + 2.2 * f) * ease(k));
        float e = length(vec2(u * 2.3, v)) - r;
        float w = max(uPixel, size * 0.24 * (1.0 - k));
        over(acc, f < 0.5 ? white : yellow, fill(abs(e) - w * 0.5) * (1.0 - k * k));
    }

    // the jet itself: cel bands from the dark rim in to the white core, each shorter than the last, edges boiling
    if (B > 0.5 && u > -size && u < L) {
        float s = max(u, 0.0) / L;
        float boil = fbm(vec2(s * 6.0 - t * 11.0, v / (B + 1.0) * 0.9 + uSeed * 37.0));
        float glow = exp(-max(abs(v) - B * profile(s), 0.0) / (size * 0.45)) * (1.0 - s);
        over(acc, player, glow * 0.4 * decay);
        vec3 cols[6] = vec3[6](ink, crimson, player, orange, yellow, white);
        float lens[6] = float[6](1.0, 0.96, 0.9, 0.82, 0.74, 0.66);
        float wids[6] = float[6](1.0, 0.88, 0.72, 0.54, 0.38, 0.22);
        for (int j = 0; j < 6; j++) {
            float sl = s / lens[j];
            if (sl >= 1.0) continue;
            float w = B * wids[j] * profile(sl) * (0.72 + 0.56 * boil);
            over(acc, cols[j], fill(abs(v) - w) * (j == 0 ? 0.92 : 1.0));
        }
    }

    // bolts crackling along the jet, re-struck 24 times a second
    float strike = floor(t * 24.0);
    if (t > 0.03 && t < 0.45 && u > 0.0 && u < L * 0.9) {
        for (int i = 0; i < 3; i++) {
            float f = float(i);
            if (hash1(strike * 1.7 + f * 9.0) < 0.3) continue;
            float seg = size * 0.8, x = u / seg, x0 = floor(x);
            float y0 = hash1(x0 * 7.3 + strike * 3.1 + f * 11.0) - 0.5, y1 = hash1((x0 + 1.0) * 7.3 + strike * 3.1 + f * 11.0) - 0.5;
            float amp = B * 0.9, zig = B * 0.3 * (f - 1.0) + mix(y0, y1, fract(x)) * amp;
            float slope = (y1 - y0) * amp / seg;
            float d = abs(v - zig) / sqrt(1.0 + slope * slope);
            float th = max(1.5, uPixel * 0.75) * (1.0 - u / L);
            over(acc, player, fill(d - th * 2.5) * 0.8);
            over(acc, white, fill(d - th));
        }
    }

    // sparks: streaks flying out and falling, every fourth one a twinkling star
    for (int i = 0; i < 26; i++) {
        float f = float(i), h1 = hash1(f * 2.31 + 4.0), h2 = hash1(f * 6.17 + 8.0), h3 = hash1(f * 9.43 + 1.0), h4 = hash1(f * 3.91 + 6.0);
        float k = (t - 0.015 - 0.07 * h3) / (0.4 + 0.45 * h4);
        if (k <= 0.0 || k >= 1.0) continue;
        vec2 d = turn(uDir, (h1 - 0.5) * 2.7 * (0.35 + 0.65 * h2));
        float dist = reach * (0.08 + (0.3 + 0.65 * h2) * ease(k));
        vec2 at = uOrigin + d * dist + vec2(0.0, size * 1.6 * k * k);
        vec3 c = mod(f, 3.0) < 0.5 ? white : mod(f, 3.0) < 1.5 ? yellow : (mod(f, 2.0) < 0.5 ? crimson : player);
        if (mod(f, 4.0) < 0.5) {
            float r = size * (0.22 + 0.2 * h1) * (1.0 - k) * (0.75 + 0.25 * sin(t * 40.0 + f));
            if (r > 0.5 && star(g - at, vec2(r, r * 1.35)) < 0.0) over(acc, white, 1.0);
        } else {
            float len = size * (0.25 + 1.1 * (1.0 - ease(k))) * (0.5 + h2);
            float w = max(uPixel * 0.5, size * 0.07 * (1.0 - k) + 1.0);
            over(acc, c, fill(segment(g, at - d * len, at) - w) * min(1.0, (1.0 - k) * 2.5));
        }
    }

    // the contact star where he went through, on top of everything for its first frames
    if (t < 0.16) {
        float k = t / 0.16, r = size * (1.5 - 0.9 * k);
        vec2 q = vec2(u - size * 0.15, v);
        float a = 1.0 - k * k;
        if (star(q, vec2(r * 0.8, r * 1.15) * 1.18) < 0.0) over(acc, crimson, a);
        if (star(q, vec2(r * 0.8, r * 1.15)) < 0.0) over(acc, white, a);
        if (star(q, vec2(r * 0.36, r * 0.55)) < 0.0) over(acc, yellow, a);
    }

    fragColor = acc * qt_Opacity;
}
