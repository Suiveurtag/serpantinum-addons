#version 440
// The final pass of Clawd's singularity (ClawdBlast.qml) over everything else: shake, chromatic split, impact
// negatives, shock refraction, then the black hole (lensing, spiral infall, horizon, photon ring, accretion), the star it
// collapses into, the blackout and the energy pulse that reveals the live desktop again (transparent inside it).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;      // px
    vec2 uCenter;    // px
    vec2 uShake;     // px
    float uTime;
    float uPixel;
    float uChroma;   // px
    float uInvert;   // 0..1
    float uFlash;    // 0..1 white
    float uRipR;     // shock refraction radius, px
    float uRipA;     // its strength, px
    float uHole;     // horizon radius, px
    float uPull;     // 0..1 everything falls in
    float uSwirl;    // radians of differential rotation
    float uAccrete;  // 0..1 accretion disc brightness
    float uStar;     // 0..1 the star it collapses into
    float uBlack;    // 0..1 to black
    float uReveal;   // return pulse radius, px; < 0 before
};
layout(binding = 1) uniform sampler2D uWorld;

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
    for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.07 + vec2(5.3, 1.9); a *= 0.5; }
    return v;
}

// past the screen edge: the void while the hole pulls, the edge pixels while the screen only shakes
vec3 world(vec2 p) {
    vec2 uv = p / uSize;
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec3(0.0);
    return texture(uWorld, uv).rgb;
}
vec3 edge(vec2 p) { return texture(uWorld, clamp(p / uSize, 0.0, 1.0)).rgb; }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// what the screen shows at radius r, angle a around the centre, once bent by the hole
vec3 bent(float r, float a, float split) {
    float hole = uHole;
    float far = length(uSize);
    float rs = r + hole * hole * 1.5 / max(r, 1.0);           // light bent around the horizon
    rs = rs * (1.0 + 3.0 * uPull) + far * 1.25 * uPull;       // and everything falling in
    float ref = 150.0;
    float as = a + uSwirl * ref / (r + ref * 0.4);            // the inner part turns faster: spiral arms
    vec3 c = vec3(0.0);
    // smeared along its orbit
    float smear = 0.012 * uSwirl * ref / (r + ref);
    for (int i = 0; i < 5; i++) {
        float k = float(i) / 4.0 - 0.5;
        float ak = as - k * smear;
        vec2 d = vec2(cos(ak), sin(ak));
        c += vec3(world(uCenter + d * (rs + split)).r, world(uCenter + d * rs).g, world(uCenter + d * (rs - split)).b);
    }
    // matter heats up as it falls in
    return c / 5.0 * (1.0 + 1.6 * exp(-max(r - hole, 0.0) / max(hole * 0.8, 1.0)) * step(0.5, hole));
}

void main() {
    vec2 px = qt_TexCoord0 * uSize;
    vec2 p = px + uShake;
    vec2 v = p - uCenter;
    float r = length(v);
    float a = atan(v.y, v.x);

    if (uRipA > 0.0) {
        float x = r - uRipR;
        r -= uRipA * exp(-x * x / 1600.0) * sin(x * 0.07);
    }

    vec3 col;
    if (uHole > 0.0 || uPull > 0.0 || uSwirl > 0.0) {
        col = bent(r, a, uChroma);
        float h = uHole;
        if (h > 0.0) {
            // accretion disc: hot matter streaming around the horizon
            float spin = uTime * 2.4 * pow(h / max(r, h), 1.5);
            float an = a - spin;
            float rn = r / h;
            float lr = log(max(rn, 1.0));
            // long arcs: coarse around the orbit, fine across it, wound into a spiral; blended across the angle seam
            float u = fract((an + lr * 2.6) / TAU + 0.5);
            vec2 g = vec2(u * 9.0, lr * 13.0 + uTime * 0.15);
            float streaks = mix(fbm(g), fbm(g - vec2(9.0, 0.0)), u);
            streaks = pow(clamp(streaks * 1.25, 0.0, 1.0), 3.0) * 3.0;
            float disc = smoothstep(1.0, 1.15, rn) * exp(-(rn - 1.0) / 0.9);
            vec3 hot = mix(vec3(1.0, 0.92, 0.85), mix(vec3(1.0, 0.45, 0.25), vec3(0.75, 0.3, 1.0), smoothstep(1.6, 2.6, rn)), smoothstep(1.05, 1.8, rn));
            col += hot * disc * streaks * uAccrete * 1.6;
            // faint lensed glow beyond it, photon ring at the edge, nothing inside
            col += vec3(0.6, 0.55, 1.0) * exp(-(rn - 1.0) / 2.5) * smoothstep(1.0, 1.4, rn) * 0.12 * uAccrete;
            col *= smoothstep(h * 0.985, h * 1.015, r);
            col += vec3(1.0, 0.95, 1.0) * exp(-pow((r - h * 1.03) / (1.2 + h * 0.02), 2.0)) * (0.7 + 0.5 * uAccrete);
        }
    } else if (uChroma > 0.0) {
        vec2 d = r > 0.5 ? v / length(v) : vec2(0.0);
        vec2 q = uCenter + d * r;
        col = vec3(edge(q + d * uChroma).r, edge(q).g, edge(q - d * uChroma).b);
    } else {
        col = edge(uCenter + (r > 0.5 ? v / length(v) : vec2(0.0)) * r);
    }

    // the star: a pixel cross with a soft halo, twinkling
    if (uStar > 0.0) {
        vec2 s = (floor(px / uPixel) + 0.5) * uPixel - uCenter;
        float len = uPixel * (3.0 + 7.0 * uStar);
        float tw = 0.8 + 0.2 * sin(uTime * 23.0) * sin(uTime * 7.0);
        float cross_ = (step(abs(s.y), uPixel * 0.5) * exp(-abs(s.x) / len) + step(abs(s.x), uPixel * 0.5) * exp(-abs(s.y) / len));
        vec2 dg = vec2(s.x + s.y, s.x - s.y) * 0.7071;
        float diag = (step(abs(dg.y), uPixel * 0.4) * exp(-abs(dg.x) / (len * 0.35)) + step(abs(dg.x), uPixel * 0.4) * exp(-abs(dg.y) / (len * 0.35))) * 0.6;
        float core = exp(-length(s) / (uPixel * 1.2));
        float halo = exp(-length(s) / (uPixel * 10.0)) * 0.35;
        col += vec3(0.88, 0.95, 1.0) * (cross_ + diag + core * 1.5 + halo) * uStar * tw;
    }

    // impact frames: a hard black-and-white negative, slightly violet
    col = mix(col, vec3(1.0 - smoothstep(0.3, 0.55, luma(col))) * vec3(0.96, 0.94, 1.0), uInvert);
    col = mix(col, vec3(1.0), uFlash);
    col *= 1.0 - uBlack;

    float alpha = 1.0;
    if (uReveal >= 0.0) {
        // the live desktop again inside the pulse, its edge a bright chromatic ring
        float rr = length(px - uCenter);
        float w = 5.0 + uReveal * 0.01;
        vec3 ring = vec3(exp(-pow((rr - uReveal + 5.0) / w, 2.0)), exp(-pow((rr - uReveal) / w, 2.0)), exp(-pow((rr - uReveal - 5.0) / w, 2.0)));
        ring = ring * 1.2 + vec3(0.55, 0.85, 1.0) * exp(-max(rr - uReveal, 0.0) / 40.0) * exp(-max(uReveal - rr, 0.0) / 90.0) * 0.6;
        float inside = 1.0 - smoothstep(uReveal - 2.0, uReveal, rr);
        float glow = clamp(max(ring.r, max(ring.g, ring.b)), 0.0, 1.0);
        alpha = mix(1.0, max(glow, uFlash), inside);
        col = mix(col, ring + vec3(uFlash), inside) + ring * (1.0 - inside);
        col = min(col, vec3(alpha));
    }
    fragColor = vec4(col, alpha) * qt_Opacity;  // premultiplied: inside the pulse col <= alpha
}
