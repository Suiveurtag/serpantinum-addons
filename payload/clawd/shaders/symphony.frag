#version 440
// The concert hall of Clawd's weekly reset (ClawdSymphony.qml), drawn over the live desktop: a dark hall with a wooden
// stage, footlights and an audience of silhouettes, a spotlight on the conductor, a spotlight and a pillar of light per
// musician (one colour per day of the week), the staves of the music being written across the screen, rings of sound,
// the golden finale (beam, shock rings, sunburst) and the red velvet curtains. Premultiplied: the hall is dark with alpha
// (the desktop ghosts through), the light adds itself, the curtains are opaque.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;      // px
    float uTime;     // seconds (stops during the silence)
    float uCurtain;  // 0 open (drawn back to the sides) .. 1 closed
    float uHall;     // 0..1 the hall around the stage
    float uSpot;     // 0..1 the conductor's spotlight
    vec2 uStage;     // x: centre of the stage, y: the floor line, px
    float uGap;      // distance between two musicians, px
    float uBase;     // how high above the stage floor the orchestra stands, px
    float uRise;     // how much higher the middle musician stands, px
    float uPix;      // one sprite pixel of the conductor, px
    float uBeat;     // 1 on a beat, falling to 0
    float uL0; float uL1; float uL2; float uL3; float uL4; float uL5; float uL6;  // each musician's light 0..1
    float uStaff;    // 0..1 how far the staves are written
    float uFury;     // 0..1 the crescendo
    float uFreeze;   // 0..1 the silence: colour drains away
    float uFinale;   // seconds since the final chord; < 0 none
    float uFade;     // 1 -> 0 as the curtains close at the end: the light goes out
    float uFlash;    // 0..1 white flash
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
vec3 day(int i) {   // one colour per day, Monday to Sunday
    if (i == 0) return vec3(1.00, 0.35, 0.37);
    if (i == 1) return vec3(1.00, 0.62, 0.11);
    if (i == 2) return vec3(1.00, 0.84, 0.04);
    if (i == 3) return vec3(0.32, 0.82, 0.49);
    if (i == 4) return vec3(0.15, 0.78, 0.85);
    if (i == 5) return vec3(0.36, 0.49, 1.00);
    return vec3(0.76, 0.36, 1.00);
}
vec2 seat(int i) {  // a musician's centre: a shallow arc, the middle one on a riser
    float d = float(i - 3);
    return vec2(uStage.x + d * uGap, uStage.y - uBase - uRise * (1.0 - d * d / 9.0) - uPix * 2.0);
}
// the staff line k of stave s: y at x, waving more and more with the crescendo
float staffY(float x, float k, float s) {
    float amp = uSize.y * (0.008 + 0.05 * uFury);
    float w = sin(x * 0.011 + uTime * (1.4 + s) + k * 0.35 + s * 2.0) + 0.5 * sin(x * 0.023 - uTime * 1.9 + s);
    return uSize.y * (0.2 + 0.2 * s) + k * uSize.y * 0.02 + w * amp;
}

void main() {
    vec2 px = qt_TexCoord0 * uSize;
    float W = uSize.x, H = uSize.y;
    float floorY = uStage.y;
    float L[7] = float[7](uL0, uL1, uL2, uL3, uL4, uL5, uL6);
    vec3 light = vec3(0.0);

    // ── the hall: a dark red-violet gradient, the wooden stage, footlights, the audience ───────────
    vec3 hall = mix(vec3(0.03, 0.015, 0.05), vec3(0.14, 0.05, 0.08), smoothstep(0.0, floorY, px.y));
    hall += vec3(0.05, 0.03, 0.02) * noise(px * 0.01 + 3.0);
    float onStage = step(floorY, px.y);
    float depth = clamp((px.y - floorY) / max(H - floorY, 1.0), 0.0, 1.0);
    float plank = abs(fract((px.x - uStage.x) / mix(60.0, 110.0, depth) * 1.0) - 0.5);
    vec3 wood = mix(vec3(0.20, 0.11, 0.07), vec3(0.34, 0.2, 0.11), depth) * (0.8 + 0.4 * smoothstep(0.0, 0.08, plank));
    wood *= 0.85 + 0.3 * noise(vec2(px.x * 0.02, px.y * 0.4));
    hall = mix(hall, wood, onStage);
    // the lip of the stage and its footlights
    float lip = smoothstep(2.0, 0.0, abs(px.y - (floorY + 3.0)));
    hall += vec3(0.5, 0.3, 0.15) * lip * 0.5;
    float bulbX = abs(fract(px.x / 56.0) - 0.5) * 56.0;
    float bulb = exp(-(bulbX * bulbX + pow(px.y - (H - 10.0), 2.0)) / 60.0);
    light += vec3(1.0, 0.72, 0.35) * bulb * (0.5 + 0.5 * uBeat) * uHall;
    light += vec3(1.0, 0.6, 0.25) * exp(-abs(px.y - (H - 10.0)) / 40.0) * 0.07 * uHall;
    // the audience: dark heads and shoulders along the bottom, lit from the front
    float cell = floor(px.x / 46.0), cx = (cell + 0.5) * 46.0;
    float head = 15.0 + 8.0 * hash(vec2(cell, 1.0));
    float hy = H + 4.0 - head * 1.2 - 10.0 * hash(vec2(cell, 2.0)) * 0.0;
    vec2 hp = vec2((px.x - cx) / 17.0, (px.y - hy) / head);
    float audience = max(step(dot(hp, hp), 1.0), step(abs(px.x - cx), 21.0) * step(hy + head * 0.8, px.y));
    audience *= step(px.y, H) * step(H - 40.0, px.y);
    float ear = step(length(vec2(abs(px.x - cx) - 19.0, px.y - hy + 2.0)), 5.0) * step(0.45, hash(vec2(cell, 7.0)));
    audience = max(audience, ear);

    // ── the conductor's spotlight: a cone from above, a pool on the stage, dust in the beam ────────────
    float k = clamp(px.y / max(floorY, 1.0), 0.0, 1.0);
    float half_ = mix(uGap * 0.35, uGap * 1.1, k);
    float across = abs(px.x - uStage.x) / half_;
    float cone = pow(clamp(1.0 - across, 0.0, 1.0), 0.8) * step(px.y, floorY + 6.0);
    float mote = step(0.992, hash(floor(px / 3.0) + floor(uTime * 5.0))) * step(px.y, floorY);
    float streak = 0.7 + 0.3 * noise(vec2((px.x - uStage.x) / half_ * 5.0, uTime * 0.3));
    light += vec3(1.0, 0.93, 0.78) * cone * (0.3 * streak + 0.8 * mote) * uSpot;
    vec2 e = (px - vec2(uStage.x, floorY + 6.0)) / vec2(uGap * 1.25, uGap * 0.16);
    light += vec3(1.0, 0.9, 0.7) * exp(-dot(e, e) * 1.3) * 0.55 * uSpot;

    // ── the seven musicians: a spotlight, a pillar of light to the top of the screen, rings of sound ───
    for (int i = 0; i < 7; i++) {
        vec3 c = day(i);
        vec2 m = seat(i);
        float lv = L[i];
        float kk = clamp(px.y / max(m.y, 1.0), 0.0, 1.0);
        float w = mix(uGap * 0.18, uGap * 0.5, kk);
        float a = abs(px.x - m.x) / w;
        float cone_i = pow(clamp(1.0 - a, 0.0, 1.0), 1.2) * step(px.y, m.y + uPix * 6.0);
        float dust = 0.8 + 0.2 * noise(vec2((px.x - m.x) / w * 4.0, px.y * 0.01 - uTime * 1.5 * lv));
        light += c * cone_i * dust * lv * (0.2 + 0.28 * uBeat + 0.25 * uFury) * step(px.y, m.y);
        // the pillar: narrow, blazing, rising sparks, only once he plays
        float pw = uGap * 0.075 * (0.7 + 0.5 * uBeat);
        float pa = exp(-pow((px.x - m.x) / pw, 2.0)) * step(px.y, m.y - uPix * 5.0);
        float sparks = step(0.9, hash(vec2(floor((px.x - m.x) / 4.0) + float(i) * 17.0, floor((px.y + uTime * 260.0) / 9.0))));
        light += mix(c, vec3(1.0), 0.4) * pa * lv * lv * (0.45 + 0.55 * uBeat + 0.4 * sparks + 0.5 * uFury);
        // the pool where he stands
        vec2 q = (px - vec2(m.x, m.y + uPix * 5.0)) / vec2(uGap * 0.5, uGap * 0.07);
        light += c * exp(-dot(q, q) * 1.5) * 0.5 * lv;
        // sound: rings leaving the instrument on every beat
        for (int r = 0; r < 2; r++) {
            float ph = fract(uTime * 1.1 + float(i) * 0.31 + float(r) * 0.5);
            float rad = ph * uGap * 2.2;
            float d = length((px - vec2(m.x, m.y - uPix * 3.0)) * vec2(1.0, 1.25)) - rad;
            light += c * exp(-d * d / 36.0) * (1.0 - ph) * lv * 0.28;
        }
    }

    // ── the staves: five lines written across the sky, notes riding them; more of them with the crescendo ──
    for (int s = 0; s < 3; s++) {
        float fs = float(s);
        float vis = s == 0 ? 1.0 : s == 1 ? smoothstep(0.25, 0.6, uFury) : smoothstep(0.55, 0.9, uFury);
        float reach = uStaff * W;
        float on = step(px.x, reach) * vis;
        float head_ = exp(-pow((px.x - reach) / 40.0, 2.0)) * vis * step(uStaff, 0.999);
        for (int n = 0; n < 5; n++) {
            float y = staffY(px.x, float(n), fs);
            float d = abs(px.y - y);
            float line = exp(-d * d / 2.2) * on;
            light += mix(vec3(1.0, 0.82, 0.42), vec3(1.0, 0.97, 0.88), 0.4 + 0.6 * uBeat) * line * (0.5 + 0.5 * uFury) * 0.75;
            light += vec3(1.0, 0.9, 0.6) * exp(-d * d / 60.0) * head_ * 0.9;
        }
        // notes drifting along: a head on a line of the stave, a stem
        float spacing = 120.0 - 30.0 * uFury;
        float u = (px.x + uTime * (90.0 + 130.0 * uFury) + fs * 57.0) / spacing;
        float nc = floor(u);
        float nx = (nc + 0.5) * spacing - uTime * (90.0 + 130.0 * uFury) - fs * 57.0;
        float line_k = floor(hash(vec2(nc, fs + 3.0)) * 9.0) * 0.5;
        float ny = staffY(nx, line_k, fs);
        vec2 nd = (px - vec2(nx, ny)) / vec2(8.5, 6.5);
        float headN = step(dot(nd, nd), 1.0);
        float stem = step(abs(px.x - (nx + 7.0)), 1.3) * step(ny - 34.0, px.y) * step(px.y, ny);
        float flag = step(abs(px.x - (nx + 11.0) + (ny - px.y) * 0.18), 1.3) * step(ny - 34.0, px.y) * step(px.y, ny - 22.0);
        vec3 nc_ = day(int(mod(nc + fs * 3.0, 7.0)));
        float noteOn = on * step(0.35, hash(vec2(nc, fs))) * step(nx, reach);
        light += mix(nc_, vec3(1.0), 0.35) * max(headN, max(stem, flag)) * noteOn * (0.7 + 0.5 * uBeat);
    }

    // ── the final chord: a golden column from the top of the sky, shock rings, a turning sunburst ───────
    if (uFinale >= 0.0) {
        float f = uFinale;
        vec2 core = vec2(uStage.x, floorY - uPix * 8.0);
        float cw = uGap * (0.35 + 1.6 * exp(-f * 3.0));
        float colm = exp(-pow((px.x - core.x) / cw, 2.0)) * step(px.y, floorY + 8.0);
        float stream = 0.75 + 0.25 * noise(vec2((px.x - core.x) / cw * 3.0, px.y * 0.012 - uTime * 2.2));
        light += vec3(1.0, 0.85, 0.5) * colm * stream * (0.55 * smoothstep(0.0, 0.25, f) + 0.9 * exp(-f * 2.0)) * (1.0 - 0.25 * smoothstep(8.0, 16.0, f));
        vec2 g = px - core;
        float r = length(g);
        for (int j = 0; j < 4; j++) {
            float fj = f - float(j) * 0.22;
            float rad = max(fj, 0.0) * H * 1.3;
            float d = r - rad;
            light += mix(vec3(1.0, 0.9, 0.6), vec3(1.0, 0.97, 0.9), float(j) * 0.3) * exp(-d * d / (90.0 + 400.0 * fj)) * step(0.0, fj) * exp(-fj * 0.9) * 1.1;
        }
        float a = atan(g.y, g.x) + uTime * 0.25;
        float rays = pow(abs(cos(a * 7.0)), 7.0);
        light += mix(vec3(1.0, 0.8, 0.4), vec3(1.0, 0.96, 0.85), rays) * rays * exp(-r / (H * 0.7)) * smoothstep(0.0, 0.3, f) * 0.7;
        light += vec3(1.0, 0.88, 0.6) * exp(-r / (uGap * 0.9)) * (0.4 + 0.9 * exp(-f * 4.0));
    }

    light *= uFade;

    // ── the colour drains in the silence ──────────────────────────────────────────────────────────────
    float lum = dot(light, vec3(0.3, 0.59, 0.11));
    light = mix(light, vec3(lum) * vec3(0.85, 0.92, 1.1), uFreeze * 0.9);
    hall = mix(hall, vec3(dot(hall, vec3(0.3, 0.59, 0.11))), uFreeze * 0.8);
    hall *= 1.0 - audience * 0.9;
    light *= 1.0 - audience * 0.85;
    light += vec3(0.15, 0.1, 0.06) * audience * 0.0;

    // ── composite: the hall (nearly opaque), then the light ──────────────────────────────────────────
    float ha = uHall * 0.975;
    vec3 col = hall * ha + min(light, vec3(2.0));
    float al = clamp(ha + max(light.r, max(light.g, light.b)), 0.0, 1.0);
    col += vec3(1.0) * uFlash * 0.9;
    al = max(al, uFlash);

    // ── the red velvet: curtains drawn to the sides, a valance on top ─────────────────────────────────
    float open_ = mix(0.075, 0.52, uCurtain);   // fraction of the width each curtain covers
    float pull = pow(clamp(px.y / H, 0.0, 1.0), 2.0) * -0.06 * W;      // tied back: the foot is drawn in
    float edgeL = open_ * W + pull * (1.0 - uCurtain) + sin(px.y * 0.012 + 1.0) * 14.0 * (1.0 - uCurtain);
    float edgeR = W - edgeL;
    float inL = step(px.x, edgeL), inR = step(edgeR, px.x);
    float cov = max(inL, inR);
    float dist = min(abs(px.x - edgeL), abs(px.x - edgeR));
    float folds = sin(px.x * 0.085 + 0.9 * sin(px.y * 0.008)) * 0.5 + 0.5;
    vec3 velvet = mix(vec3(0.22, 0.02, 0.05), vec3(0.62, 0.09, 0.13), pow(folds, 1.6));
    velvet *= 0.8 + 0.25 * noise(vec2(px.x * 0.05, px.y * 0.004));
    velvet *= 1.0 - 0.45 * smoothstep(60.0, 0.0, dist) * 0.0;
    velvet = mix(velvet, vec3(0.9, 0.7, 0.2), smoothstep(7.0, 2.0, dist) * 0.9);      // the gold fringe
    float ruffle = 0.0;
    // the valance across the top, scalloped, with a gold trim
    float vh = H * 0.07 + 11.0 * sin(px.x * 0.035) * sin(px.x * 0.035) * uHall;
    float val = step(px.y, vh) * uHall;
    vec3 valc = mix(vec3(0.3, 0.03, 0.07), vec3(0.7, 0.1, 0.15), pow(sin(px.x * 0.06) * 0.5 + 0.5, 1.4));
    valc = mix(valc, vec3(0.92, 0.72, 0.22), smoothstep(5.0, 1.0, abs(px.y - vh)));
    float shadow = smoothstep(26.0, 0.0, px.y - vh) * step(vh, px.y) * uHall * 0.5;
    col *= 1.0 - shadow;
    float covAll = max(cov, val);
    vec3 cloth = val > cov ? valc : velvet;
    col = mix(col, cloth, covAll);
    al = max(al, covAll);
    // the closed curtain swallows everything, the middle seam too
    float seam = smoothstep(3.0, 0.0, abs(px.x - W * 0.5)) * step(0.98, uCurtain);
    col = mix(col, vec3(0.9, 0.7, 0.2), seam * 0.8 * covAll);

    fragColor = vec4(min(col, vec3(1.0)), al) * qt_Opacity;
}
