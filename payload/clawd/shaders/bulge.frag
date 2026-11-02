#version 440
// Something pushing into the screen from outside (ClawdSurge.qml): the desktop captured at the start of the scene is
// stretched into a trembling dome from the top-left corner, lit along its rim, cracking with light; then it tears and a
// ripple runs across the whole screen. Transparent outside what it bends (the live desktop shows through).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;      // px
    float uTime;     // seconds
    vec2 uCorner;    // where it pushes in from, px (just outside the corner)
    float uBulge;    // 0..1 how far it pushes in
    float uCrack;    // 0..1 the cracks of light
    float uPop;      // seconds since it tore; < 0 before
};
layout(binding = 1) uniform sampler2D uDesk;

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
    for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + vec2(4.1, 7.3); a *= 0.5; }
    return v;
}
vec2 rot(vec2 v, float a) { float c = cos(a), s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }
// the magic: violet, cyan and white
vec3 magic(float k) {
    k = fract(k);
    vec3 a = vec3(0.62, 0.42, 1.0), b = vec3(0.45, 0.95, 1.0), c = vec3(1.0, 0.93, 1.0);
    return k < 0.33 ? mix(a, b, k / 0.33) : k < 0.66 ? mix(b, c, (k - 0.33) / 0.33) : mix(c, a, (k - 0.66) / 0.34);
}
// shards: jittered cells; returns the cell id, its feature point (cell units) and how near the edge to a neighbour it is
vec2 shardCell(vec2 cs, out vec2 fp, out float edge) {
    vec2 ci = floor(cs);
    float d1 = 1e9, d2 = 1e9;
    vec2 id1 = vec2(0.0);
    fp = vec2(0.0);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        vec2 id = ci + vec2(float(i), float(j));
        vec2 p = id + 0.15 + 0.7 * vec2(hash(id), hash(id + 7.7));
        float d = length(cs - p);
        if (d < d1) { d2 = d1; d1 = d; id1 = id; fp = p; }
        else if (d < d2) d2 = d;
    }
    edge = d2 - d1;
    return id1;
}
// the capture mirrored at its edges: pushing the image outwards never smears the border pixels
vec2 mirror(vec2 p) {
    p = abs(p);
    p = uSize - abs(uSize - p);
    return abs(p);
}
vec3 desk(vec2 p) { return texture(uDesk, clamp(mirror(p) / uSize, 0.0, 1.0)).rgb; }

void main() {
    vec2 px = qt_TexCoord0 * uSize;
    float H = uSize.y;
    vec2 g = px - uCorner;
    float d = length(g);
    vec2 dir = g / max(d, 1e-3);
    float a = atan(g.y, g.x);
    vec3 col = vec3(0.0);
    float al = 0.0;

    if (uPop < 0.0) {
        // the dome: radius grows and trembles; the desktop is refracted through it, and under it a rift of light opens
        float tremble = (noise(vec2(a * 4.0, uTime * 18.0)) - 0.5) * 0.12 * uBulge + sin(uTime * 41.0) * 0.015 * uBulge;
        float R = H * (0.12 + 0.42 * uBulge) * (1.0 + tremble);
        float k = clamp(1.0 - d / R, 0.0, 1.0);
        float h = k * k * (3.0 - 2.0 * k);                  // the dome's height 0..1
        float push = h * R * (0.25 + 0.45 * uBulge);       // px each pixel is pushed away from the corner
        vec2 src = px - dir * push;
        // refraction with a little chromatic split, strongest on the slope
        float split = k * (1.0 - k) * 4.0 * uBulge * 9.0;
        vec3 img = vec3(desk(src - dir * split).r, desk(src).g, desk(src + dir * split).b);
        // the rift: a plasma of violet, cyan and white swirling about the corner, brighter towards it
        float depth = pow(h, 0.6) * (0.5 + 0.5 * uBulge);
        vec2 q = rot(g, d * 0.004 - uTime * 0.9) * 0.012;
        float plasma = fbm(q + vec2(uTime * 0.5, 0.0));
        float veins = smoothstep(0.1, 0.0, abs(fbm(q * 1.7 - uTime * 0.35 + 5.0) - 0.5));
        vec3 rift = magic(plasma * 1.4 + d * 0.0015 - uTime * 0.25) * (0.7 + 1.1 * plasma);
        rift += vec3(1.0, 0.95, 1.0) * veins * 0.9;
        rift += vec3(1.0, 0.97, 1.0) * exp(-d / (R * 0.28)) * 1.6;
        col = mix(img, rift, clamp(depth * 1.5, 0.0, 0.96));
        // the rim catches the light: a hot thin ring and a soft glow outside it
        float rim = exp(-pow((d - R) / (R * 0.035 + 2.0), 2.0));
        float slope = k * (1.0 - k) * 4.0;
        col += mix(vec3(0.75, 0.6, 1.0), vec3(1.0), rim) * (slope * 0.35 + rim * 1.3) * uBulge;
        // cracks: thin lines radiating from the corner, more of them as it gives way
        float seg = noise(vec2(a * 22.0, 3.0));
        float line = abs(fract(a * 7.0 + (noise(vec2(d * 0.03, a * 5.0)) - 0.5) * 0.6) - 0.5);
        float crack = smoothstep(0.035, 0.0, line) * step(1.0 - uCrack, seg) * step(d, R * (0.3 + 0.7 * uCrack));
        col += vec3(0.95, 0.9, 1.0) * crack * 1.4 * uCrack;
        // the pressure: light seeps out through the cracks (a wide glow along them) and the whole dome heaves
        float seep = smoothstep(0.16, 0.0, line) * step(1.0 - uCrack, seg) * step(d, R * (0.3 + 0.7 * uCrack));
        col += magic(a * 0.3 + uTime * 0.4) * seep * uCrack * uCrack * 1.6;
        col += vec3(1.0) * pow(uCrack, 3.0) * h * (0.35 + 0.35 * sin(uTime * 38.0)) * 0.8;
        al = max(smoothstep(0.0, 0.08, k), rim * 0.8 * uBulge);
    } else {
        // torn: the dome shatters into shards of desktop that fly off the corner over a rift of white light, and a
        // shockwave runs across the whole screen bending what it passes
        float t = uPop;
        float ring = t * H * 2.0;
        float w = 26.0 + 70.0 * t;
        float x = (d - ring) / w;
        float amp = 46.0 * exp(-t * 1.5);
        float bend = exp(-x * x) * sin(x * 3.1416) * amp;
        vec3 rc = vec3(desk(px - dir * (bend * 1.2)).r, desk(px - dir * bend).g, desk(px - dir * (bend * 0.8)).b);
        col = rc + vec3(0.8, 0.7, 1.0) * exp(-x * x) * amp / 46.0 * 0.5;
        al = smoothstep(0.02, 0.2, exp(-x * x) * amp / 46.0);
        // the rift left behind where the dome stood: white-hot, then violet and cyan, receding into the corner
        float R0 = H * 0.56;
        float edgeRift = R0 * (1.0 + 0.5 * t);
        float rk = smoothstep(edgeRift, edgeRift * 0.2, d);
        vec2 q = rot(g, d * 0.004 - uTime * 2.0) * 0.012;
        float plasma = fbm(q + vec2(uTime, 0.0));
        vec3 rift = magic(plasma * 1.6 + uTime * 0.5) * (0.9 + 1.3 * plasma) + vec3(1.0) * exp(-d / (R0 * 0.3)) * 2.2;
        float riftA = rk * exp(-t * 1.3);
        col = mix(col, rift, riftA);
        al = max(al, riftA);
        // the shards
        float cell = H * 0.075;
        vec2 fp; float edge;
        vec2 id = shardCell(g / cell, fp, edge);
        vec2 fpx = fp * cell;
        float rr = length(fpx);
        if (rr < R0 * 1.02) {
            vec2 sdir = fpx / max(rr, 1.0);
            float spd = 0.55 + 1.1 * hash(id + 3.1);
            float travel = (1.0 - exp(-t * 2.6)) * H * 0.55 * spd * (1.1 - 0.6 * rr / R0) + t * t * H * 0.05;
            vec2 qg = g - sdir * travel;
            vec2 fp2; float edge2;
            vec2 id2 = shardCell(qg / cell, fp2, edge2);
            if (id2 == id) {
                float life = 1.0 - smoothstep(0.35 + 0.5 * hash(id + 9.0), 1.25, t);
                vec2 srcp = uCorner + qg;
                vec3 sc = vec3(desk(srcp - sdir * 3.0).r, desk(srcp).g, desk(srcp + sdir * 3.0).b);
                float eg = smoothstep(0.1, 0.0, edge2);
                sc += vec3(0.85, 0.9, 1.0) * eg * 1.3 * exp(-t * 1.5);
                sc *= 1.0 - 0.35 * smoothstep(0.0, 0.8, t);
                col = mix(col, sc, life);
                al = max(al, life);
            }
        }
    }
    fragColor = vec4(col * al, al) * qt_Opacity;
}
