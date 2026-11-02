#version 440
// The light of Clawd's superpowered weekly scene (ClawdSurge.qml), drawn over the live desktop, premultiplied (only the
// darkening has alpha, the light adds itself): the edge lighting bleeding from the top-left corner, the magic orb and its
// tail, the explosion (core, shock rings, rays, sparkles), the violet smoke he inhales, his power pulse and aura, the
// floor he lights up, the six effort beams, the streams converging on him, the final burst. uImpact > 0: an impact frame
// instead (black and white, radial lines; his silhouette is drawn over it).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;      // px
    float uTime;     // seconds
    float uDark;     // 0..1 the screen darkens
    float uEdge;     // 0..1 the edge lighting in the top-left corner
    float uPop;      // seconds since the orb broke through; < 0 before
    vec2 uOrbA;      // the orb's path: a quadratic curve A -> B -> C, px
    vec2 uOrbB;
    vec2 uOrbC;
    float uOrbU;     // 0..1 where the orb is on it; < 0 none
    float uOrbR;     // its radius, px
    vec2 uHit;       // the impact point (his middle), px
    float uBoom;     // seconds since the impact; < 0 before
    float uSmoke;    // 0..1 the smoke and the light it leaves
    float uSuck;     // 0..1 how much of it he has inhaled
    float uPower;    // seconds since his power pulse; < 0 before
    float uAura;     // 0..1 his aura from then on
    vec2 uMe;        // his middle, px
    float uPix;      // one sprite pixel, px
    float uSlam;     // seconds since he struck the floor; < 0 before
    float uFloorY;   // the floor line, px
    float uFloor;    // 0..1 the lit floor
    vec4 uBX0;       // the six helpers' x (low, medium, high, xhigh), px
    vec4 uBX1;       // (max, ultra, -, -)
    vec4 uBL0;       // their beam levels 0..1
    vec4 uBL1;
    vec4 uBK0;       // seconds since each beam struck; < 0 before
    vec4 uBK1;
    float uHead;     // the helpers' head height above the floor, px
    float uStream;   // 0..1 their streams converging on him
    float uFinal;    // seconds since the limit is full; < 0 before
    float uBuild;    // 0..1 the charge about to hit 100 %
    vec4 uAK0;       // seconds since each helper lands (negative: on its way, < -1 not yet)
    vec4 uAK1;
    vec4 uVK0;       // seconds since each helper leaves; < 0 before
    vec4 uVK1;
    float uImpact;   // 0 none, 1 white frame, 2 black frame
    float uZap;      // seconds since lightning struck the ultra helper's seat; < 0 before
    vec2 uHandL;     // the light at the end of his arms, px
    vec2 uHandR;
    float uHands;    // 0..1
    float uWarp;     // seconds since the workspace switch (his dash); < 0 before
    float uDir;      // his dash direction, 1 right, -1 left
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
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(4.1, 7.3); a *= 0.5; }
    return v;
}
vec2 rot(vec2 v, float a) { float c = cos(a), s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }
// the magic: violet, cyan and white
vec3 magic(float k) {
    k = fract(k);
    vec3 a = vec3(0.62, 0.42, 1.0), b = vec3(0.45, 0.95, 1.0), c = vec3(1.0, 0.93, 1.0);
    return k < 0.33 ? mix(a, b, k / 0.33) : k < 0.66 ? mix(b, c, (k - 0.33) / 0.33) : mix(c, a, (k - 0.66) / 0.34);
}
// Claude Code's colours, lighter: the max helper's rainbow
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
vec3 helper(int i, float y) {
    if (i == 0) return vec3(1.0, 0.757, 0.027);
    if (i == 1) return vec3(0.306, 0.729, 0.396);
    if (i == 2) return vec3(0.694, 0.725, 0.976);
    if (i == 3) return vec3(0.686, 0.529, 1.0);
    if (i == 4) return rainbow(y * 0.0012 - uTime * 0.35);
    return vec3(0.608, 0.965, 1.0);
}
float six(vec4 a, vec4 b, int i) { return i == 0 ? a.x : i == 1 ? a.y : i == 2 ? a.z : i == 3 ? a.w : i == 4 ? b.x : b.y; }
vec2 bez(float u) { float v = 1.0 - u; return v * v * uOrbA + 2.0 * v * u * uOrbB + u * u * uOrbC; }
// a jagged vertical bolt at x0 from y0 to y1: distance in px
float bolt(vec2 px, float x0, float y0, float y1, float seed, float amp) {
    if (px.y < min(y0, y1) || px.y > max(y0, y1)) return 1e4;
    float y = px.y * 0.02;
    float off = (noise(vec2(y * 3.0, seed)) - 0.5) * amp + (noise(vec2(y * 11.0, seed + 5.0)) - 0.5) * amp * 0.35;
    return abs(px.x - x0 - off);
}

// a rune circle lying on the floor: hard jagged dashed rim, a counter-rotating tick ring inside, spikes flung outwards,
// glitching in and out; and a cage of light ribs standing on it
vec3 runeRing(vec2 g, float r, float seed, float life, vec3 c, vec3 hot, float kind) {
    if (life <= 0.0 || r < 1.0) return vec3(0.0);
    r *= 0.5 + 0.15 * kind;   // the lower the effort, the smaller the circle (low 0.5 ... ultra 1.25)
    // each effort level draws its circle differently: dashes, ticks, spikes, spin, roughness
    float nD = kind < 0.5 ? 12.0 : kind < 1.5 ? 20.0 : kind < 2.5 ? 30.0 : kind < 3.5 ? 36.0 : kind < 4.5 ? 44.0 : 8.0;     // dashes on the rim
    float nT = kind < 0.5 ? 40.0 : kind < 1.5 ? 56.0 : kind < 2.5 ? 120.0 : kind < 3.5 ? 72.0 : kind < 4.5 ? 90.0 : 32.0;    // ticks on the inner ring
    float nS = kind < 0.5 ? 8.0 : kind < 1.5 ? 26.0 : kind < 2.5 ? 6.0 : kind < 3.5 ? 12.0 : kind < 4.5 ? 20.0 : 5.0;       // spikes
    float spin = kind < 0.5 ? 0.35 : kind < 1.5 ? 0.7 : kind < 2.5 ? 0.5 : kind < 3.5 ? 2.2 : kind < 4.5 ? 1.2 : 0.9;
    float rough = kind < 0.5 ? 0.5 : kind < 1.5 ? 1.5 : kind < 2.5 ? 0.25 : kind < 3.5 ? 0.6 : kind < 4.5 ? 0.9 : 2.0;
    float twist = kind > 2.5 && kind < 3.5 ? 0.04 : 0.0;
    vec2 ge = g * vec2(1.0, 3.4);
    float e = length(ge);
    float a = atan(ge.y, ge.x);
    float jag = (noise(vec2(a * 5.0 + seed * 9.0, uTime * 7.0)) - 0.5) * uPix * 7.0 * rough * life;
    float rr = r + jag;
    float d = abs(e - rr);
    float seg = step(0.38, fract(a / TAU * nD + uTime * spin));
    float glitch = step(0.12, hash(vec2(floor(a * 8.0 + seed), floor(uTime * 22.0))));
    float rim = smoothstep(uPix * 1.7, uPix * 0.55, d);
    vec3 o = hot * rim * (0.4 + 0.9 * seg) * glitch * 1.6;
    o += vec3(1.0) * smoothstep(uPix * 0.7, 0.0, d) * seg * 1.1;
    float inner = smoothstep(uPix * 1.0, uPix * 0.3, abs(e - rr * 0.8)) * step(0.5, fract(a / TAU * nT - uTime * 2.5 * spin));
    o += c * inner * 1.4 * glitch;
    float outer = smoothstep(uPix * 0.8, 0.1 * uPix, abs(e - rr * 1.12)) * step(0.7, fract(a / TAU * 12.0 + uTime));
    o += hot * outer;
    float spikes = pow(abs(cos(a * nS * 0.5 + e * twist + seed * 3.0)), kind > 4.5 ? 60.0 : 30.0) * smoothstep(uPix * (kind > 4.5 ? 70.0 : 34.0), 0.0, e - rr) * step(rr, e);
    o += hot * spikes * 1.3;
    o += c * exp(-d / (uPix * 5.0)) * 0.3;
    if (kind > 1.5 && kind < 2.5) o += hot * smoothstep(uPix * 0.6, 0.0, abs(e - rr * 0.6)) * 0.9 * glitch;
    if (kind > 3.5 && kind < 4.5) o += rainbow(a / TAU - uTime * 0.5) * rim * 1.2;
    // the cage
    if (g.y < 0.0 && abs(g.x) < rr) {
        float ax = acos(clamp(g.x / rr, -1.0, 1.0));
        float line = smoothstep(0.1, 0.0, abs(fract(ax / TAU * 26.0 + 0.5) - 0.5) * 2.0 - 0.0) ;
        float rib = smoothstep(0.07, 0.0, abs(fract(ax / TAU * nD) - 0.5) - 0.40);
        o += mix(c, vec3(1.0), 0.5) * rib * exp(min(g.y, 0.0) / (uPix * (10.0 + 14.0 * life))) * step(0.3, fract(ax / TAU * nD * 0.5)) * life * 0.75;
    }
    return o * life;
}

void main() {
    vec2 px = qt_TexCoord0 * uSize;
    float W = uSize.x, H = uSize.y;

    // ── an impact frame: the whole screen black or white, lines rushing to the impact ─────────────────
    if (uImpact > 0.5) {
        vec2 g = px - uHit;
        float a = atan(g.y, g.x), r = length(g);
        float lines = step(0.72, noise(vec2(a * 38.0, floor(uTime * 30.0)))) * smoothstep(uPix * 10.0, uPix * 40.0, r);
        float ring = smoothstep(uPix * 3.0, 0.0, abs(r - uPix * 18.0 - fract(uTime * 7.0) * uPix * 30.0));
        float ink = max(lines, ring);
        vec3 bw = uImpact < 1.5 ? vec3(1.0 - ink) : vec3(ink);
        fragColor = vec4(bw, 1.0) * qt_Opacity;
        return;
    }

    vec3 light = vec3(0.0);
    vec4 haze = vec4(0.0);   // what is not light: the smoke, premultiplied

    // ── the edge lighting: the left edge catches fire around where it will come in, the light bleeding inwards ──
    if (uEdge > 0.0) {
        vec2 e = uOrbA;
        float dy = px.y - e.y;
        float flow = fbm(vec2(px.y * 0.006 - uTime * 1.3, px.x * 0.004 + uTime * 0.4));
        float flick = 0.85 + 0.15 * sin(uTime * 27.0) * sin(uTime * 9.0);
        float along = exp(-abs(dy) / (H * (0.08 + 0.4 * uEdge)));
        float wid = 14.0 + 70.0 * uEdge * uEdge + 30.0 * flow;
        float bleed = exp(-px.x / wid) * along;
        light += magic(px.y * 0.0015 - uTime * 0.3 + flow * 0.5) * bleed * uEdge * 1.6 * flick;
        // the whole left edge glows a little, a hairline of white on it
        light += magic(0.1 + px.y * 0.001) * exp(-px.x / 10.0) * uEdge * 0.5;
        light += vec3(1.0) * exp(-px.x / 2.0) * (0.3 + along) * uEdge * 0.9;
        // the bloom where it pushes, a horizontal anamorphic streak, rays fanning into the room
        vec2 g = px - e;
        float r = length(g);
        light += vec3(1.0, 0.97, 1.0) * exp(-r / (H * (0.015 + 0.05 * uEdge))) * uEdge * 2.2 * flick;
        light += vec3(0.75, 0.85, 1.0) * exp(-abs(dy) / (3.0 + 6.0 * uEdge)) * exp(-px.x / (W * 0.45 * uEdge + 1.0)) * uEdge * uEdge * 1.4;
        float a = atan(g.y, max(g.x, 0.001));
        float rays = pow(abs(cos(a * 7.0 + uTime * 0.6 + flow)), 26.0) * step(0.0, g.x);
        light += magic(a * 0.3 + uTime * 0.2) * rays * exp(-r / (H * 0.35 * uEdge + 1.0)) * uEdge * uEdge * 1.2;
        // motes drawn towards the entry point
        vec2 cell = floor(px / 5.0);
        float mote = step(0.994, hash(cell + floor(uTime * 8.0))) * exp(-r / (H * 0.3)) * uEdge;
        light += vec3(1.0, 0.95, 1.0) * mote * 1.5;
    }
    // the tear where it broke through, closing again
    if (uPop >= 0.0) {
        float k = exp(-uPop * 2.2);
        float d = length(px - uOrbA);
        light += vec3(1.0, 0.95, 1.0) * exp(-d / (H * 0.05 * (0.4 + k))) * k * 1.4;
        float ring = uPop * H * 1.6;
        light += magic(0.2) * exp(-pow((d - ring) / (30.0 + 80.0 * uPop), 2.0)) * exp(-uPop * 1.5) * 0.6;
        // the break: a blinding core on the corner, a sharp white shockwave, rays flung across the screen, an anamorphic streak
        float k2 = exp(-uPop * 4.0);
        float ang = atan(px.y - uOrbA.y, max(px.x - uOrbA.x, 0.001));
        light += vec3(1.0) * exp(-d / (H * 0.13)) * k2 * 2.4;
        light += vec3(1.0) * exp(-pow((d - uPop * H * 2.4) / (8.0 + 26.0 * uPop), 2.0)) * exp(-uPop * 2.6) * 1.5;
        light += magic(ang * 0.4 + uTime * 0.3) * pow(abs(cos(ang * 9.0 + uPop)), 26.0) * step(0.0, px.x - uOrbA.x) * exp(-d / (H * 0.8)) * k2 * 1.6;
        light += vec3(0.85, 0.92, 1.0) * exp(-abs(px.y - uOrbA.y) / (2.0 + 5.0 * k2)) * exp(-px.x / (W * 0.7)) * k2 * 1.8;
    }

    // ── the orb: a white core, a violet-cyan halo, swirling, its tail along the path ───────────────────
    if (uOrbU >= 0.0) {
        vec2 o = bez(uOrbU);
        vec2 g = px - o;
        float d = length(g);
        float swirl = fbm(rot(g, uTime * 6.0) / uOrbR * 1.5 + uTime * 2.0);
        light += vec3(1.0) * smoothstep(uOrbR * 0.8, uOrbR * 0.25, d) * 2.5;
        light += vec3(0.85, 0.9, 1.0) * exp(-abs(g.y) / 4.0) * exp(-abs(g.x) / (uOrbR * 6.0)) * 1.2;   // anamorphic flare
        light += magic(atan(g.y, g.x) / TAU + uTime) * exp(-d / (uOrbR * (0.7 + 0.5 * swirl))) * 1.4;
        light += magic(0.1) * exp(-d / (uOrbR * 5.0)) * 0.6;
        // the tail: nearest point among samples behind it
        float best = 1e5, bu = 0.0;
        for (int i = 1; i <= 14; i++) {
            float u = uOrbU - float(i) * 0.03;
            if (u < 0.0) break;
            float di = length(px - bez(u));
            if (di < best) { best = di; bu = float(i) / 14.0; }
        }
        float w = uOrbR * (1.0 - bu) * 0.8 + 2.0;
        light += magic(bu + uTime * 0.5) * exp(-best / w) * (1.0 - bu) * 1.2;
        // sparks shed by the orb
        float sp = step(0.985, hash(floor(px / 4.0) + floor(uTime * 20.0))) * exp(-best / (uOrbR * 2.5));
        light += vec3(1.0) * sp * 1.5;
    }

    // ── the explosion: a blinding core, rings, rays, magic sparkles ────────────────────────────────────
    if (uBoom >= 0.0) {
        float b = uBoom;
        vec2 g = px - uHit;
        float r = length(g), a = atan(g.y, g.x);
        light += vec3(1.0) * exp(-r / (H * (0.05 + 0.35 * exp(-b * 3.0)))) * (2.5 * exp(-b * 2.0) + 0.2 * uSmoke);
        for (int j = 0; j < 3; j++) {
            float bj = b - float(j) * 0.12;
            if (bj < 0.0) continue;
            float rad = bj * H * (1.2 - 0.25 * float(j));
            light += magic(float(j) * 0.3 + a / TAU) * exp(-pow((r - rad) / (8.0 + 40.0 * bj), 2.0)) * exp(-bj * 1.6) * 1.4;
        }
        float rays = pow(abs(sin(a * 9.0 + b * 0.8)), 24.0) + 0.6 * pow(abs(sin(a * 14.0 - b * 1.3 + 1.0)), 30.0);
        light += magic(a / TAU * 2.0) * rays * exp(-r / (H * 0.5)) * exp(-b * 1.8) * 1.6;
        float tw = step(0.993, hash(floor(px / 3.0) + floor(uTime * 12.0))) * exp(-r / (H * 0.35)) * smoothstep(3.5, 0.5, b);
        light += vec3(1.0, 0.9, 1.0) * tw * 2.0;
    }

    // ── the smoke and the glowing wisps it leaves; inhaled: it shrinks and spirals into him ────────────
    if (uSmoke > 0.0) {
        float s = uSuck * uSuck;
        vec2 g = px - uHit;
        float r = length(g);
        float R = H * 0.32 * (1.0 - s) + 1.0;
        vec2 q = rot(g, s * 9.0 * (1.0 - clamp(r / (H * 0.4), 0.0, 1.0))) / (1.0 - 0.85 * s);
        float dens = fbm(q * 0.006 + vec2(0.0, uTime * 0.08)) * smoothstep(R, R * 0.2, r);
        dens = smoothstep(0.35, 0.8, dens) * uSmoke;
        float wisp = smoothstep(0.02, 0.0, abs(fbm(q * 0.004 + 9.0 - uTime * 0.05) - 0.5)) * smoothstep(R * 1.1, R * 0.3, r) * uSmoke;
        float sa = clamp(dens * 0.75, 0.0, 0.8);
        haze = vec4(vec3(0.22, 0.16, 0.32) * sa + vec3(0.5, 0.35, 0.8) * dens * 0.25, sa);
        light += magic(fbm(q * 0.003) + uTime * 0.1) * wisp * 1.2;
        light += vec3(0.95, 0.85, 1.0) * exp(-r / (uPix * 6.0)) * s * 1.6 * uSmoke;   // what goes in lights him up
    }

    // ── his power: a pulse ring, bolts around him, then an aura ────────────────────────────────────────
    if (uPower >= 0.0) {
        vec2 g = px - uMe;
        float r = length(g), a = atan(g.y, g.x);
        float p = uPower;
        float ring = exp(-pow((r - p * H * 0.9) / (6.0 + 20.0 * p), 2.0)) * exp(-p * 2.5);
        light += magic(0.15 + a / TAU) * ring * 1.8;
        light += vec3(1.0, 0.95, 1.0) * exp(-r / (uPix * 10.0)) * exp(-p * 4.0) * 2.0;
        // bolts: a few jagged rays from him, flickering
        float n = floor(uTime * 14.0);
        float sec = floor((a / TAU + 0.5) * 9.0);
        float ang = (sec + 0.5) / 9.0 * TAU - TAU * 0.5 + (hash(vec2(sec, n)) - 0.5) * 0.4;
        vec2 dir = vec2(cos(ang), sin(ang));
        float along = dot(g, dir), off = dot(g, vec2(-dir.y, dir.x));
        float len = uPix * (10.0 + 14.0 * hash(vec2(sec, n + 3.0)));
        float jag = (noise(vec2(along * 0.08, sec + n)) - 0.5) * uPix * 4.0;
        float on = step(0.45, hash(vec2(sec * 3.0, n))) * (exp(-p * 1.2) * 0.9 + 0.25 * uAura * step(0.8, hash(vec2(n, 2.0))));
        float bl = smoothstep(2.5, 0.0, abs(off - jag)) * step(uPix * 6.0, along) * step(along, len) * on;
        light += mix(vec3(0.6, 0.95, 1.0), vec3(1.0), 0.5) * bl * 1.8;
    }
    // ── the awakening: what he swallowed detonates inside him. Colossal shockwaves, a pillar through the sky, long lightning
    // storming across the screen, god rays, the edges of the screen flaring ────────────────────────────────────────────
    if (uPower >= 0.0 && uPower < 4.5) {
        float p = uPower;
        float fade = 1.0 - smoothstep(2.2, 4.5, p);
        vec2 g = px - uMe;
        float r = length(g), a = atan(g.y, g.x);
        light += vec3(1.0) * exp(-r / (H * (0.1 + 0.5 * exp(-p * 3.0)))) * 1.8 * exp(-p * 2.2) * fade;
        for (int j = 0; j < 5; j++) {
            float pj = p - float(j) * 0.12;
            if (pj < 0.0) continue;
            float rad = pj * H * 2.0;
            light += magic(a / TAU + float(j) * 0.2 - uTime * 0.4) * exp(-pow((r - rad) / (8.0 + 60.0 * pj), 2.0)) * exp(-pj * 1.1) * 1.6 * fade;
        }
        float pw = uPix * (2.0 + 16.0 * exp(-p * 3.0));
        float colx = abs(g.x);
        light += vec3(1.0) * exp(-colx / pw) * 1.8 * exp(-p * 1.5) * fade;
        light += magic(px.y / H - uTime * 0.7) * exp(-colx / (pw * 3.5)) * 0.8 * exp(-p * 1.4) * fade;
        float rays = pow(abs(cos(a * 14.0 + uTime * 0.7)), 18.0) + 0.5 * pow(abs(cos(a * 5.0 - uTime * 0.4)), 6.0);
        light += magic(a / TAU + uTime * 0.15) * rays * exp(-r / (H * 0.9)) * exp(-p * 0.9) * 1.1 * fade;
        light += vec3(0.85, 0.92, 1.0) * exp(-abs(g.y) / (uPix * 1.5)) * exp(-colx / (W * 0.6)) * exp(-p * 1.8) * 2.0 * fade;
        float de = min(min(px.x, W - px.x), min(px.y, H - px.y));
        light += magic(a / TAU - uTime * 0.5) * exp(-de / (uPix * (3.0 + 8.0 * p))) * smoothstep(0.0, 0.1, p) * exp(-p * 1.1) * 1.5 * fade;
        // the lightning storm: long bolts, each flickering from its own spot
        float n = floor(uTime * 16.0);
        for (int j = 0; j < 7; j++) {
            float fj = float(j);
            float ang = (hash(vec2(fj, n)) - 0.5) * TAU;
            vec2 dir = vec2(cos(ang), sin(ang));
            float along = dot(g, dir), off = dot(g, vec2(-dir.y, dir.x));
            float jag = (noise(vec2(along * 0.025, fj * 5.0 + n)) - 0.5) * uPix * 12.0 + (noise(vec2(along * 0.09, fj + n * 3.0)) - 0.5) * uPix * 4.0;
            float len = H * (0.35 + 0.7 * hash(vec2(fj + 3.0, n)));
            float on = step(0.3, hash(vec2(fj * 7.0, n))) * exp(-p * 0.9);
            float d = abs(off - jag);
            float seg = step(uPix * 8.0, along) * step(along, len);
            light += vec3(1.0) * exp(-pow(d / (uPix * 0.7), 2.0)) * seg * on * 1.6 * fade;
            light += vec3(0.55, 0.9, 1.0) * exp(-d / (uPix * 4.0)) * seg * on * 0.5 * fade;
        }
        vec2 cell = floor(vec2(px.x / 5.0, (px.y + p * 150.0) / 5.0));
        light += magic(hash(cell)) * step(0.992, hash(cell + 2.0)) * exp(-r / (H * 0.7)) * exp(-p * 0.8) * 2.0 * fade;
    }
    if (uAura > 0.0) {
        vec2 g = (px - uMe) / vec2(1.0, 0.8);
        float r = length(g);
        float flame = fbm(vec2(atan(g.y, g.x) * 2.0, r * 0.02 - uTime * 2.5));
        light += magic(flame + uTime * 0.2) * exp(-r / (uPix * (12.0 + 10.0 * flame))) * uAura * 1.0;
    }

    // ── the floor: a colour wave racing away from his fists, then climbing the sides of the screen ────
    if (uSlam >= 0.0) {
        float fy = uFloorY;
        float dx = abs(px.x - uMe.x);
        float front = uSlam * W * 0.9;
        float lit = smoothstep(front + 40.0, front - 40.0, dx);
        float up = max(fy - px.y, 0.0);
        float band = exp(-up / (H * 0.06)) * step(px.y, fy + 30.0) * (1.0 - smoothstep(fy, fy + 30.0, px.y) * 0.6);
        vec3 c = rainbow(px.x / W * 1.2 - uTime * 0.25);
        float wave = exp(-pow((dx - front) / 50.0, 2.0)) * exp(-up / (H * 0.12));
        light += c * band * lit * uFloor * 0.9 + vec3(1.0) * wave * exp(-uSlam * 1.2) * 1.4;
        // the sides: once the wave hits the edges it climbs them
        float edgeT = max(uSlam - W * 0.5 / (W * 0.9), 0.0);
        float climb = (1.0 - exp(-edgeT * 2.0)) * H * 0.55;
        float side = (exp(-px.x / 20.0) + exp(-(W - px.x) / 20.0)) * smoothstep(fy - climb - 60.0, fy - climb + 60.0, px.y) * step(px.y, fy);
        light += rainbow(px.y / H - uTime * 0.3) * side * uFloor * 0.9;
        // cracks of light running across the floor and up the air from his fists, and a dome of force
        vec2 g = px - vec2(uMe.x, fy);
        float r = length(g), a = atan(-g.y, g.x), ac = atan(-g.y * 6.0, abs(g.x));
        float reach = (1.0 - exp(-uSlam * 5.0)) * W * 0.45;
        float crk = abs(fract(ac / 3.1416 * 14.0 + (noise(vec2(r * 0.03, floor(ac / 3.1416 * 14.0))) - 0.5) * 0.6) - 0.5);
        float crack = smoothstep(0.03, 0.0, crk) * step(r, reach) * step(px.y, fy + 2.0) * exp(-uSlam * 0.9) * exp(-(fy - px.y) / (H * 0.05));
        light += mix(vec3(1.0), rainbow(r / W - uTime * 0.4), 0.5) * crack * 1.6;
        float dome = exp(-pow((r - uSlam * H * 1.3) / (10.0 + 50.0 * uSlam), 2.0)) * step(px.y, fy) * exp(-uSlam * 1.6);
        light += mix(vec3(1.0), rainbow(a / 3.1416), 0.6) * dome * 1.6;
        light += vec3(1.0, 0.97, 0.9) * exp(-r / (uPix * 20.0)) * exp(-uSlam * 3.0) * 2.0;
        // the shock line at the moment of the strike
        light += vec3(1.0) * exp(-abs(px.y - fy) / 3.0) * exp(-dx / (W * 0.3)) * exp(-uSlam * 3.0) * 2.0;
    }

    // ── the six beams: one per helper, each stronger than the last ─────────────────────────────────────
    for (int i = 0; i < 6; i++) {
        float lv = six(uBL0, uBL1, i);
        float k = six(uBK0, uBK1, i);
        float bx = six(uBX0, uBX1, i);
        if (lv <= 0.001 && k < 0.0) continue;
        float fi = float(i);
        vec3 c = helper(i, px.y + px.x * 0.3);
        float dx = px.x - bx;
        float strike = k >= 0.0 ? exp(-k * (3.0 - fi * 0.3)) : 0.0;     // the first blast, longer for the strong ones
        float w = uPix * (0.35 + fi * 0.18) * (1.0 + 1.8 * strike);
        float core = exp(-pow(dx / w, 2.0));
        float glow = exp(-abs(dx) / (w * (3.0 + fi * 0.5)));
        float ripple = 0.85 + 0.15 * sin(px.y * 0.05 - uTime * (6.0 + fi * 2.0));
        float amt = lv * (0.35 + 0.1 * fi) + strike * (0.9 + fi * 0.35);
        light += mix(c, vec3(1.0), 0.55) * core * amt * ripple * 1.4 + c * glow * amt * 0.6;
        // medium and up: sparks rising in the beam
        if (i >= 1) {
            float sp = step(0.93 - fi * 0.01, hash(vec2(floor(dx / 3.0), floor((px.y + uTime * (200.0 + fi * 90.0)) / 7.0) + fi * 13.0)));
            light += c * sp * exp(-abs(dx) / (w * 3.0)) * lv * 1.2;
        }
        // a pool of its light on the floor, and a flare along the floor when it strikes
        vec2 pf = (px - vec2(bx, uFloorY)) / vec2(uPix * (14.0 + fi * 3.0), uPix * 2.5);
        light += c * exp(-dot(pf, pf)) * (lv * 0.7 + strike * 1.5);
        light += mix(c, vec3(1.0), 0.5) * exp(-abs(px.y - uFloorY) / 3.0) * exp(-abs(dx) / (W * 0.08 * (1.0 + fi * 0.3))) * strike * 1.2;
        // xhigh and up: a white sweep up the beam now and then
        if (i >= 3) {
            float sweep = fract(uTime * 0.45 + fi * 0.37);
            float sy = H * (1.0 - sweep * 1.3);
            light += vec3(1.0) * core * exp(-pow((px.y - sy) / 40.0, 2.0)) * lv * 0.9;
        }
        // ultra: lightning, around the beam and across the screen when it strikes
        if (i == 5) {
            float n = floor(uTime * 16.0);
            for (int j = 0; j < 3; j++) {
                float fj = float(j);
                float d = bolt(px, bx + (hash(vec2(n, fj)) - 0.5) * uPix * 16.0, 0.0, uFloorY, n * 7.0 + fj * 31.0, uPix * (4.0 + 4.0 * fj));
                float on = step(0.35, hash(vec2(n + fj, 4.0)));
                light += mix(c, vec3(1.0), 0.6) * smoothstep(2.5, 0.0, d) * on * (lv * 0.8 + strike * 1.5);
                light += c * exp(-d / 10.0) * on * (lv * 0.15 + strike * 0.35);
            }
            if (k >= 0.0 && k < 1.2) {
                // horizontal arcs racing from the beam to the screen edges
                for (int j = 0; j < 2; j++) {
                    float fj = float(j);
                    float y0 = H * (0.25 + 0.3 * fj + 0.1 * hash(vec2(n, fj + 9.0)));
                    float yy = (noise(vec2(px.x * 0.02, n * 3.0 + fj)) - 0.5) * 70.0 + y0;
                    float d = abs(px.y - yy);
                    float reach = k * W * 3.0;
                    light += mix(c, vec3(1.0), 0.6) * smoothstep(2.5, 0.0, d) * step(abs(px.x - bx), reach) * exp(-k * 3.0) * 2.0;
                }
            }
        }
    }

    // ── the lightning that brings the ultra helper, and the light in his hands ─────────────────────────
    if (uZap >= 0.0 && uZap < 1.0) {
        float n = floor(uTime * 20.0), z = exp(-uZap * 4.0);
        vec3 c = vec3(0.608, 0.965, 1.0);
        for (int j = 0; j < 3; j++) {
            float d = bolt(px, uBX1.y + (float(j) - 1.0) * uPix * 5.0, 0.0, uFloorY, n * 3.0 + float(j) * 17.0, uPix * (5.0 + 3.0 * float(j)));
            light += mix(c, vec3(1.0), 0.7) * smoothstep(3.0, 0.0, d) * z * 2.2 + c * exp(-d / 16.0) * z * 0.5;
        }
        vec2 f = (px - vec2(uBX1.y, uFloorY)) / vec2(1.0, 0.3);
        light += c * exp(-length(f) / (uPix * 20.0)) * z * 1.5;
    }
    if (uHands > 0.0) {
        for (int j = 0; j < 2; j++) {
            vec2 h = j == 0 ? uHandL : uHandR;
            float d = length(px - h);
            float fl = 0.85 + 0.15 * sin(uTime * 17.0 + float(j) * 2.0);
            light += vec3(1.0) * smoothstep(uPix * 2.2, uPix * 0.8, d) * uHands * 1.5;
            light += magic(uTime * 0.3 + float(j) * 0.5) * exp(-d / (uPix * 5.0 * fl)) * uHands * 1.3;
            float a = atan(px.y - h.y, px.x - h.x);
            light += vec3(1.0, 0.95, 1.0) * pow(abs(cos(a * 2.0 + uTime)), 40.0) * exp(-d / (uPix * 14.0)) * uHands * 0.8;
        }
    }

    // ── the helpers' entrances and exits: landing impacts, one signature each, and a launch into the sky on the way out ──
    for (int i = 0; i < 6; i++) {
        float ak = six(uAK0, uAK1, i);   // seconds since it lands (negative: on its way)
        float vk = six(uVK0, uVK1, i);   // seconds since it leaves; < 0 before
        float sx = six(uBX0, uBX1, i);
        vec3 c = helper(i, px.y + px.x * 0.3);
        vec3 hot = mix(c, vec3(1.0), 0.65);
        vec2 g = px - vec2(sx, uFloorY);
        float colx = abs(g.x);
        // the way in
        if (i == 0 && ak > -0.5 && ak < 0.0) {            // low: a comet from the sky
            float u = 1.0 + ak / 0.5;
            float headY = u * u * uFloorY;
            float dy = px.y - headY;
            light += hot * exp(-colx / (uPix * 2.2)) * step(dy, 0.0) * exp(dy / (H * 0.35)) * 1.5;
            light += vec3(1.0) * exp(-length(vec2(g.x, dy)) / (uPix * 5.0)) * 1.8;
        }
        if (i == 3 && ak > -0.6 && ak < 0.5) {            // xhigh: a sonic streak along the floor, the boom as it stops
            float lane = abs(px.y - (uFloorY - uPix * 14.0));
            float len = W * 0.5 * (1.0 - smoothstep(-0.6, 0.3, ak));
            light += hot * exp(-lane / (uPix * 1.4)) * step(0.0, g.x) * exp(-max(g.x, 0.0) / max(len, 1.0)) * smoothstep(0.5, 0.0, ak) * 1.4;
        }
        if (i == 4 && ak > -0.3 && ak < 0.9) {            // max: the portal, a rainbow disc that opens then slams shut
            vec2 pc = (px - vec2(sx, uFloorY - uPix * 12.0)) / vec2(0.55, 1.0);
            float open = smoothstep(-0.3, 0.1, ak) * (1.0 - smoothstep(0.3, 0.9, ak));
            float rad = uPix * 22.0 * open;
            float a = atan(pc.y, pc.x);
            light += rainbow(a / TAU - uTime * 0.9) * exp(-pow((length(pc) - rad) / (uPix * 2.5), 2.0)) * open * 2.0;
            light += rainbow(a / TAU + length(pc) * 0.02 - uTime * 1.5) * smoothstep(rad, rad * 0.2, length(pc)) * open * 0.7;
        }
        if (i == 1 && ak > -0.1 && ak < 1.0) {            // medium: an eruption through the floor
            float n = fbm(vec2(px.y * 0.02 - uTime * 6.0, g.x * 0.03));
            float w = uPix * (3.0 + 7.0 * exp(-ak * 3.0)) * (0.6 + n);
            light += hot * exp(-colx / w) * step(g.y, 0.0) * exp(min(g.y, 0.0) / (H * 0.45)) * exp(-ak * 2.5) * 2.0;
        }
        if (i == 2 && ak > -0.2 && ak < 0.8) {            // high: a beam from the sky slams down
            light += vec3(1.0) * exp(-colx / (uPix * (2.0 + 18.0 * exp(-ak * 6.0)))) * step(g.y, 0.0) * exp(-ak * 3.0) * 1.7;
        }
        // the landing, for all of them: a flash, a flat shockwave, a burst of light up, sparks
        if (ak >= 0.0 && ak < 1.6) {
            float e = exp(-ak * 3.2);
            light += hot * exp(-length(g * vec2(1.0, 1.7)) / (uPix * (8.0 + 26.0 * ak))) * e * 1.7;
            for (int j = 0; j < 3; j++) {
                float aj = ak - float(j) * 0.11;
                if (aj < 0.0) continue;
                light += runeRing(g, aj * uPix * (130.0 - 18.0 * float(j)), float(i * 3 + j), exp(-aj * (1.6 + 0.6 * float(j))), c, hot, float(i));
            }
            light += c * exp(-colx / (uPix * (2.0 + 8.0 * e))) * step(g.y, 0.0) * exp(min(g.y, 0.0) / (H * 0.3)) * e * 1.2;
            vec2 cell = floor(vec2(g.x / 5.0, (g.y + ak * 260.0) / 5.0));
            light += hot * step(0.985, hash(cell + float(i) * 11.0)) * exp(-length(g * vec2(1.0, 0.6)) / (uPix * 40.0)) * e * 2.2;
        }
        // the way out: it flares white, is flung into the sky in a column of light, a ring pops where it stood
        if (vk >= 0.0 && vk < 1.4) {
            float up = smoothstep(0.0, 0.18, vk);
            float e = exp(-vk * 1.6);
            float w = uPix * (2.0 + 9.0 * (1.0 - smoothstep(0.0, 0.5, vk)));
            light += mix(hot, vec3(1.0), 0.5) * exp(-colx / w) * step(g.y, 0.0) * up * e * 1.9;
            light += c * exp(-colx / (w * 4.0)) * step(g.y, 0.0) * up * e * 0.5;
            vec2 mid = vec2(sx, uFloorY - uPix * 14.0);
            light += vec3(1.0) * exp(-length(px - mid) / (uPix * 12.0)) * exp(-vk * 7.0) * 2.2;
            // a rune circle collapses into him, then two blow outwards
            light += runeRing(g, (1.0 - smoothstep(0.0, 0.24, vk)) * uPix * 70.0 + uPix * 2.0, float(i) + 20.0, 1.0 - smoothstep(0.2, 0.3, vk), c, hot, float(i));
            for (int j = 0; j < 2; j++) {
                float vj = vk - 0.22 - float(j) * 0.1;
                if (vj < 0.0) continue;
                light += runeRing(g, vj * uPix * 170.0, float(i * 2 + j) + 30.0, exp(-vj * 2.4), c, hot, float(i));
            }
            vec2 cell = floor(vec2(g.x / 5.0, (g.y + vk * 500.0) / 5.0));
            light += hot * step(0.983, hash(cell + float(i) * 7.0)) * exp(-colx / (uPix * 14.0)) * step(g.y, 0.0) * e * 2.0;
        }
    }

    // ── the streams: each helper's light arcing up into him, a living cable with beads of light running along it ──
    if (uStream > 0.0) {
        float hot = 1.0 + 0.7 * uBuild;
        for (int i = 0; i < 6; i++) {
            vec2 a = vec2(six(uBX0, uBX1, i), uFloorY - uHead);
            vec2 b = uMe + vec2((float(i) - 2.5) * uPix * 3.6, uPix * 1.0);
            vec2 m = (a + b) * 0.5 + vec2((float(i) - 2.5) * -W * 0.015, -H * (0.16 + 0.025 * float(i < 3 ? i : 5 - i)));
            float best = 1e5, bu = 0.0;
            vec2 prev = a;
            for (int s = 1; s <= 32; s++) {
                float u = float(s) / 32.0;
                float v = 1.0 - u;
                vec2 p = v * v * a + 2.0 * v * u * m + u * u * b;
                vec2 tan = normalize(2.0 * v * (m - a) + 2.0 * u * (b - m));
                float env = sin(u * 3.14159);
                p += vec2(-tan.y, tan.x) * (noise(vec2(u * 7.0 - uTime * 2.5, float(i) * 3.1)) - 0.5) * uPix * 5.0 * env * (1.0 + uBuild);
                vec2 e = p - prev;
                float h = clamp(dot(px - prev, e) / max(dot(e, e), 1e-4), 0.0, 1.0);
                float d = length(px - (prev + e * h));
                if (d < best) { best = d; bu = (float(s - 1) + h) / 32.0; }
                prev = p;
            }
            vec3 c = helper(i, px.y + px.x * 0.3);
            float reach = smoothstep(uStream * 1.4, uStream * 1.4 - 0.2, bu);
            float w = uPix * (0.42 + 0.07 * float(i)) * (1.0 + 0.5 * uBuild);
            float bead = pow(0.5 + 0.5 * sin(bu * 46.0 - uTime * 20.0 + float(i) * 1.7), 7.0);
            float flick = 0.8 + 0.2 * sin(uTime * 31.0 + float(i) * 5.0);
            light += vec3(1.0) * exp(-pow(best / w, 2.0)) * reach * flick * 1.0 * hot;
            light += c * exp(-pow(best / (w * 2.6), 2.0)) * reach * (0.8 + 1.2 * bead) * hot;
            light += c * exp(-best / (w * 6.0)) * reach * 0.22 * hot;
            light += mix(c, vec3(1.0), 0.6) * bead * exp(-best / (w * 1.6)) * reach * 1.1 * hot;
            // the node at its foot and where it lands on him
            float dn = length(px - a);
            light += mix(c, vec3(1.0), 0.5) * exp(-dn / (uPix * 3.5)) * uStream * (0.8 + 0.5 * flick) * hot;
            light += c * exp(-length(px - b) / (uPix * 4.0)) * uStream * reach * 0.8;
        }
        light += vec3(1.0, 0.97, 1.0) * exp(-length(px - uMe) / (uPix * (3.0 + 4.0 * uStream + 6.0 * uBuild))) * uStream * (0.6 + 0.8 * uBuild);
    }

    // ── the last second before 100 %: everything is pulled into him ──────────────────────────────────
    if (uBuild > 0.0) {
        vec2 g = px - uMe;
        float r = length(g), a = atan(g.y, g.x);
        for (int j = 0; j < 3; j++) {
            float q = fract(uTime * (1.2 + uBuild) + float(j) / 3.0);
            float rad = (1.0 - q) * (1.0 - q) * H * 1.1 + uPix * 6.0;
            light += rainbow(q + float(j) * 0.3 + uTime * 0.2) * exp(-pow((r - rad) / (uPix * (2.0 + 5.0 * q)), 2.0)) * q * uBuild * 1.2;
        }
        light += vec3(1.0) * exp(-r / (uPix * (3.0 + 7.0 * uBuild))) * uBuild * uBuild * 1.4;
        light += rainbow(a / TAU + uTime * 0.4) * pow(abs(cos(a * 10.0 - uTime * 7.0)), 24.0) * exp(-r / (H * 0.4)) * uBuild * 0.45;
    }

    // ── the limit is full: a white-out, a pillar of light, shockwaves across the screen, the edges flaring ──
    if (uFinal >= 0.0) {
        vec3 before = light;
        float f = uFinal;
        vec2 g = px - uMe;
        float r = length(g), a = atan(g.y, g.x);
        light += vec3(1.0) * exp(-r / (H * (0.12 + 0.6 * exp(-f * 2.0)))) * 2.4 * exp(-f * 1.1);
        // the pillar, floor to sky, shot through with every colour
        float pw = uPix * (3.0 + 26.0 * exp(-f * 3.0));
        float colx = abs(px.x - uMe.x);
        light += vec3(1.0) * exp(-colx / pw) * 1.8 * exp(-f * 1.6);
        light += rainbow(px.y / H * 1.5 - uTime * 0.8) * exp(-colx / (pw * 3.0)) * 1.3 * exp(-f * 1.0);
        // the shockwaves: round, then flat along the floor
        for (int j = 0; j < 6; j++) {
            float fj = f - float(j) * 0.11;
            if (fj < 0.0) continue;
            float rad = fj * H * 2.1;
            light += rainbow(a / TAU + float(j) * 0.17 - uTime * 0.3) * exp(-pow((r - rad) / (8.0 + 70.0 * fj), 2.0)) * exp(-fj * 0.9) * 1.5;
        }
        float fl = f * W * 1.6;
        light += mix(vec3(1.0), rainbow(px.x / W + uTime * 0.5), 0.5) * exp(-pow((abs(px.x - uMe.x) - fl) / (20.0 + 90.0 * f), 2.0)) * exp(-abs(px.y - uFloorY) / (uPix * (3.0 + 8.0 * f))) * exp(-f * 1.1) * 2.0;
        // god rays, wide and slow to fade, and the anamorphic streak through his heart
        float rays = pow(abs(cos(a * 18.0 + uTime * 0.5)), 14.0) + 0.6 * pow(abs(cos(a * 7.0 - uTime * 0.35)), 8.0);
        light += rainbow(a / TAU + uTime * 0.1) * rays * exp(-r / (H * 1.0)) * exp(-f * 0.6) * 1.1;
        light += mix(vec3(1.0), rainbow(uTime * 0.4), 0.3) * exp(-abs(g.y) / (uPix * 1.6)) * exp(-abs(g.x) / (W * 0.55)) * exp(-f * 1.6) * 2.2;
        // the edges of the screen flare in every colour
        float de = min(min(px.x, W - px.x), min(px.y, H - px.y));
        light += rainbow(a / TAU - uTime * 0.6) * exp(-de / (uPix * (4.0 + 10.0 * f))) * smoothstep(0.0, 0.1, f) * exp(-f * 0.7) * 1.7;
        // a storm of glitter
        vec2 cell = floor(vec2(px.x / 5.0, (px.y - f * 150.0) / 5.0));
        float glit = step(0.99, hash(cell)) * smoothstep(5.0, 1.0, f) * step(0.3, sin(uTime * 9.0 + hash(cell) * 30.0));
        light += rainbow(hash(cell + 3.0)) * glit * 1.8;
        light = before + (light - before) * (1.0 - smoothstep(3.6, 6.2, f));
    }

    // ── the workspace switch: the world tears sideways behind his dash ───────────────────────────────
    if (uWarp >= 0.0 && uWarp < 1.6) {
        float w = uWarp;
        float row = floor(px.y / 3.0);
        float speed = 0.6 + 1.4 * hash(vec2(row, 1.0));
        float head = (w * speed * 3.0 - hash(vec2(row, 2.0))) * W;
        float x = uDir > 0.0 ? px.x : W - px.x;
        float on = step(0.82, hash(vec2(row, 3.0)));
        float streak = on * smoothstep(head - W * 0.5, head, x) * step(x, head) * exp(-w * 2.5);
        light += mix(magic(row * 0.013), vec3(1.0), 0.4) * streak * 1.3;
        vec2 g = (px - uMe) / vec2(1.0, 2.5);
        float r = length(g);
        light += magic(0.2) * exp(-pow((r - w * W) / (20.0 + 120.0 * w), 2.0)) * exp(-w * 2.0) * 1.5;
        light += vec3(1.0) * exp(-abs(px.y - uMe.y) / (8.0 + 60.0 * w)) * exp(-w * 4.0) * 1.2;
    }

    // ── composite: the darkening (alpha), then the light on top ────────────────────────────────────────
    vec2 v = qt_TexCoord0 - 0.5;
    float vign = clamp(uDark * (0.82 + 0.5 * dot(v, v)), 0.0, 0.97);
    vec4 base = haze + vec4(0.0, 0.0, 0.0, vign) * (1.0 - haze.a);
    vec3 col = min(base.rgb + light, vec3(2.0));
    float al = clamp(base.a + max(light.r, max(light.g, light.b)), 0.0, 1.0);
    fragColor = vec4(min(col, vec3(al)), al) * qt_Opacity;
}
