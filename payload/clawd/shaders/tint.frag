#version 440
// Recolours Clawd's own body (the exact #D97757 of his sprites) on the sprite's pixel grid while an agent works
// (ClawdOverlay.qml): everything else (eyes, props, hearts, blanket...) passes through untouched, so it works on every
// animation without a recoloured copy. Mode 0 flat colour; 1 white glint sweeping across; 2 Claude Code's light colours
// flowing through him; 3 electric: crackling white, a bolt sweeping through him, flashes; 4 gold with sparkles; 5 space: a
// violet-blue nebula with parallax stars and a shooting star. What floats around him is aura.frag.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uColor;
    float uMode;
    float uTime;
    vec2 uGrid;      // the sprite's size in its own pixels
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
// no arrays indexed at run time: some GL drivers drop the whole shader
vec3 tone(float i) {
    if (i < 0.5) return vec3(1.0, 0.62, 0.48);
    if (i < 1.5) return vec3(1.0, 0.85, 0.40);
    if (i < 2.5) return vec3(0.56, 0.89, 0.63);
    if (i < 3.5) return vec3(0.61, 0.83, 1.0);
    if (i < 4.5) return vec3(0.79, 0.71, 1.0);
    return vec3(1.0, 0.61, 0.69);
}
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 rainbow(float k) {
    k = fract(k) * 6.0;
    float i = floor(k);
    return mix(tone(i), tone(mod(i + 1.0, 6.0)), smoothstep(0.0, 1.0, fract(k)));
}

void main() {
    vec2 cell = floor(qt_TexCoord0 * uGrid);
    vec4 s = texture(source, qt_TexCoord0);
    if (s.a < 0.01) { fragColor = vec4(0.0); return; }
    vec3 rgb = s.rgb / s.a;
    // his body only: the sprite pixels are exact, the margin just absorbs filtering
    bool body = distance(rgb, vec3(0.851, 0.467, 0.341)) < 0.1;
    vec3 c = rgb;
    if (body) {
        c = uColor.rgb;
        if (uMode > 0.5 && uMode < 1.5) {
            float sweep = fract(uTime * 0.33);
            float band = abs((cell.x + cell.y * 0.6) / (uGrid.x * 1.6) - sweep * 1.6 + 0.3);
            c = mix(c, vec3(1.0), smoothstep(0.08, 0.0, band) * 0.9);
        } else if (uMode > 1.5 && uMode < 2.5) {
            c = rainbow((cell.x + cell.y) / 22.0 - uTime * 0.6);
        } else if (uMode > 2.5 && uMode < 3.5) {
            float n = floor(uTime * 18.0);
            float crack = step(0.93, hash(cell + n));
            c = mix(c, vec3(1.0), crack) * (0.9 + 0.2 * step(0.5, hash(vec2(n, 1.0))));
            // a jagged bolt running through his body, and a flash now and then
            float sweep = fract(uTime * 0.8) * (uGrid.x + 6.0) - 3.0;
            float jag = floor(hash(vec2(cell.y, n)) * 3.0) - 1.0;
            c = mix(c, vec3(1.0), step(abs(cell.x - sweep - jag), 0.5));
            c = mix(c, vec3(1.0), 0.55 * step(0.965, hash(vec2(floor(uTime * 10.0), 5.0))));
        } else if (uMode > 3.5 && uMode < 4.5) {
            float sweep = fract(uTime * 0.4);
            float band = abs((cell.x + cell.y * 0.8) / (uGrid.x * 1.8) - sweep * 1.8 + 0.3);
            c = mix(c * (0.86 + 0.14 * sin(uTime * 3.0 + cell.x * 0.6)), vec3(1.0, 0.96, 0.78), smoothstep(0.1, 0.0, band) * 0.8);
            c = mix(c, vec3(1.0), step(0.955, hash(cell + floor(uTime * 12.0))));
        } else if (uMode > 4.5) {
            vec2 uv = (cell + 0.5) / uGrid;
            // the nebula: two slow layers of noise, posterised so it stays pixel art
            float n1 = vnoise(cell * 0.23 + vec2(uTime * 0.35, uTime * 0.12));
            float n2 = vnoise(cell * 0.55 - vec2(uTime * 0.2, 4.0));
            float q = floor((n1 * 0.65 + n2 * 0.35) * 4.0) / 4.0;
            vec3 sky = mix(vec3(0.09, 0.07, 0.34), vec3(0.30, 0.13, 0.64), uv.y);
            vec3 cloud = mix(vec3(0.20, 0.42, 1.0), vec3(0.74, 0.38, 1.0), vnoise(cell * 0.3 + 7.0));
            c = mix(sky, cloud, q * 0.9);
            // stars drifting at two speeds, the brighter ones twinkling
            float far = step(0.93, hash(vec2(cell.x + floor(uTime * 1.2), cell.y)));
            float near = step(0.965, hash(vec2(cell.x + floor(uTime * 3.0), cell.y + 31.0)));
            float tw = step(0.35, hash(vec2(floor(uTime * 4.0), cell.x * 7.0 + cell.y)));
            c = mix(c, vec3(0.78, 0.82, 1.0), far * 0.7);
            c = mix(c, vec3(1.0), near * tw);
            // a shooting star across him every few seconds
            float cyc = uTime * 0.36;
            float p = fract(cyc) * 1.7;
            if (p < 1.0) {
                vec2 head = vec2(p * (uGrid.x + 10.0) - 5.0, hash(vec2(floor(cyc), 2.0)) * uGrid.y * 0.4 + p * (uGrid.x + 10.0) * 0.45);
                vec2 t = head - cell;
                if (t.x >= 0.0 && t.x < 6.0 && abs(t.y - t.x * 0.45) < 0.55) c = mix(vec3(0.62, 0.72, 1.0), vec3(1.0), 1.0 - t.x / 6.0);
            }
        }
    }
    fragColor = vec4(c * s.a, s.a) * qt_Opacity;
}
