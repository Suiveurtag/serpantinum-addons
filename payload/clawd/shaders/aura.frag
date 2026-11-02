#version 440
// What floats around Clawd while an agent works at the top efforts (ClawdOverlay.qml), drawn on his pixel grid over a
// rectangle that extends his sprite by a margin. Mode 3 electric: jagged lightning bolts leaping from his body, flying sparks;
// 4 gold: four-point glints popping on and around him, golden dust rising; 5 space: twinkling stars of two sizes,
// drifting dust, a shooting star. uBody = his sprite's cells inside the grid (x, y, w, h); uColor = the look's colour.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uColor;
    vec4 uBody;
    float uMode;
    float uTime;
    vec2 uGrid;
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// a cell on a glint: a plus of arm length l, with diagonal sparkle at the full size
float plusAt(vec2 d, float l) {
    float on = 0.0;
    if (d.x == 0.0 && abs(d.y) <= l) on = 1.0;
    if (d.y == 0.0 && abs(d.x) <= l) on = 1.0;
    
    return on;
}

vec4 electric(vec2 cell) {
    vec2 ctr = uBody.xy + uBody.zw * 0.5;
    vec2 hext = uBody.zw * 0.5;
    vec3 white = mix(uColor.rgb, vec3(1.0), 0.85);
    float core = 0.0;
    float glow = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float slot = floor(uTime * 11.0 + fi * 3.0);          // each bolt re-forms about 11 times a second, staggered
        if (hash(vec2(fi, slot)) < 0.35) continue;              // and some slots are dark: it flickers
        float a = hash(vec2(fi * 5.0, slot * 0.37)) * 6.2831853;
        vec2 dir = vec2(cos(a), sin(a));
        vec2 stepv = abs(dir.x) > abs(dir.y) ? vec2(sign(dir.x), 0.0) : vec2(0.0, sign(dir.y));
        vec2 side = vec2(abs(stepv.y), abs(stepv.x));
        vec2 pos = floor(ctr + dir * hext * 0.8);
        float len = 3.0 + floor(hash(vec2(slot, fi + 9.0)) * 4.0);
        for (int s = 0; s < 8; s++) {
            if (float(s) > len) break;
            vec2 d = abs(cell - pos);
            float dist = max(d.x, d.y);
            if (dist < 0.5) core = 1.0;
            else if (dist < 1.5) glow = max(glow, step(0.82, hash(cell + slot)));
            pos += stepv;
            pos += side * (floor(hash(vec2(fi * 13.0 + float(s), slot)) * 3.0) - 1.0);
            // a short fork off the middle of the bolt
            if (float(s) == floor(len * 0.5)) {
                vec2 fork = pos;
                for (int f = 0; f < 2; f++) {
                    fork += side * (hash(vec2(slot, fi)) < 0.5 ? 1.0 : -1.0) + stepv * step(0.4, hash(vec2(float(f), slot + fi)));
                    vec2 e = abs(cell - fork);
                    if (max(e.x, e.y) < 0.5) core = 1.0;
                }
            }
        }
        // a spark thrown off by the bolt
        float sp = fract(uTime * 4.0 + fi * 0.37);
        vec2 spark = floor(ctr + dir * (hext * 0.8 + vec2(1.0) + sp * 5.0));
        if (spark == cell) core = max(core, 1.0 - sp);
    }
    vec3 rgb = white * core + mix(uColor.rgb, vec3(1.0), 0.3) * glow * (1.0 - core);
    float a = max(core, glow * 0.9);
    return vec4(rgb * a, a);
}

vec4 gold(vec2 cell) {
    vec3 gold = vec3(1.0, 0.83, 0.30);
    vec3 pale = vec3(1.0, 0.95, 0.70);
    vec3 col = vec3(0.0);
    float a = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float cyc = uTime * 0.85 + hash(vec2(fi, 1.0)) * 7.0;
        float slot = floor(cyc);
        float p = fract(cyc);
        vec2 pos = floor(uBody.xy + vec2(hash(vec2(fi, slot)) * uBody.z, hash(vec2(slot, fi + 4.0)) * uBody.w));
        float l = floor(sin(p * 3.14159) * 1.99);
        vec2 d = cell - pos;
        if (plusAt(d, l) > 0.5) {
            col = (d.x == 0.0 && d.y == 0.0) ? vec3(1.0) : gold;
            a = 1.0;
        }
    }
    for (int j = 0; j < 7; j++) {
        float fj = float(j);
        float k = fract(uTime * (0.25 + 0.2 * hash(vec2(fj, 2.0))) + hash(vec2(fj, 3.0)));
        vec2 dust = floor(vec2(uBody.x + hash(vec2(fj, 4.0)) * uBody.z, uBody.y + uBody.w * 1.0 - k * uBody.w * 1.2));
        if (dust == cell) { col = mod(fj, 2.0) < 1.0 ? gold : pale; a = 1.0; }
    }
    return vec4(col * a, a);
}

vec4 space(vec2 cell) {
    vec3 col = vec3(0.0);
    float a = 0.0;
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        vec2 pos = floor(vec2(hash(vec2(fi, 5.0)), hash(vec2(fi, 6.0))) * uGrid);
        float ph = fract(uTime * (0.3 + 0.4 * hash(vec2(fi, 7.0))) + hash(vec2(fi, 8.0)));
        if (ph > 0.75) continue;                                   // dark part of its twinkle
        float big = step(0.25, ph) * step(ph, 0.45) * step(0.75, hash(vec2(fi, 9.0)));
        vec2 d = cell - pos;
        float on = (d.x == 0.0 && d.y == 0.0) ? 1.0 : 0.0;
        if (big > 0.5 && abs(d.x) + abs(d.y) == 1.0) on = 1.0;
        if (on > 0.5) {
            float c = hash(vec2(fi, 10.0));
            col = c < 0.4 ? vec3(1.0) : c < 0.7 ? vec3(0.62, 0.85, 1.0) : vec3(0.72, 0.61, 1.0);
            a = 1.0;
        }
    }
    // a shooting star across the whole rectangle every few seconds
    float cyc = uTime * 0.33;
    float slot = floor(cyc);
    float p = fract(cyc) * 2.2;
    if (p < 1.0) {
        float top = floor(hash(vec2(slot, 1.0)) * uGrid.y * 0.4);
        vec2 head = vec2(p * (uGrid.x + 8.0) - 4.0, top + p * (uGrid.x + 8.0) * 0.45);
        vec2 t = head - cell;
        if (t.x >= 0.0 && t.x < 4.0 && abs(t.y - t.x * 0.45) < 0.55) {
            float f = 1.0 - t.x / 4.0;
            col = mix(vec3(0.62, 0.7, 1.0), vec3(1.0), f);
            a = f;
        }
    }
    return vec4(col * a, a);
}

void main() {
    vec2 cell = floor(qt_TexCoord0 * uGrid);
    vec4 o = vec4(0.0);
    if (uMode > 4.5) o = space(cell);
    else if (uMode > 3.5) o = gold(cell);
    else if (uMode > 2.5) o = electric(cell);
    fragColor = o * qt_Opacity;
}
