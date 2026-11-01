#version 440
// The "evil" Gemini drawing: opaque paper (white background) made sinister. Low uIntensity keeps the drawing recognisable
// (a faint red cast and vignette); high uIntensity adds glitch slices, RGB split, scanlines, glowing red eyes and flashes.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uIntensity;  // 0..1 overall
    float uSlice;      // glitch slice probability 0..1
    float uAberr;      // chromatic aberration, in uv
    float uEyes;       // eye glow 0..1
    vec2 uEyeL;        // eye centres, uv
    vec2 uEyeR;
    float uFlicker;    // 0..1
    float uInvert;     // 0..1 invert flash
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float k = clamp(uIntensity, 0.0, 1.0);
    float step24 = floor(uTime * 14.0);

    // horizontal glitch bands
    float band = floor(uv.y * 28.0);
    float bh = hash(vec2(band, step24));
    float on = step(1.0 - uSlice * k, bh);
    float shift = (hash(vec2(band, step24 + 11.0)) - 0.5) * 0.18 * on;
    // slow wobble of the whole sheet at high intensity
    shift += sin(uv.y * 40.0 + uTime * 9.0) * 0.002 * k;
    vec2 suv = vec2(uv.x + shift, uv.y);

    // chromatic aberration (stronger inside glitch bands)
    float ab = uAberr * (0.4 + 1.6 * on) * (0.3 + 0.7 * k);
    vec3 col;
    col.r = texture(source, vec2(suv.x + ab, suv.y)).r;
    col.g = texture(source, suv).g;
    col.b = texture(source, vec2(suv.x - ab, suv.y)).b;

    // darken the paper and push it red
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    vec3 paper = vec3(0.86, 0.50, 0.46);                      // dirty red-tinted paper
    vec3 ink = col * vec3(0.55, 0.20, 0.20);                  // lines turn dark blood
    vec3 graded = mix(ink, paper * (0.35 + 0.65 * luma), smoothstep(0.15, 0.9, luma));
    graded = mix(col, graded, 0.15 + 0.85 * k);

    // scanlines
    float scan = 0.5 + 0.5 * sin(uv.y * 520.0 + uTime * 6.0);
    graded *= 1.0 - 0.18 * k * scan;

    // vignette: dark edges
    vec2 d = uv - 0.5;
    float vig = smoothstep(0.25, 0.75, length(d * vec2(1.0, 0.85)));
    graded *= 1.0 - vig * (0.35 + 0.6 * k);

    // glowing red eyes
    float eyes = clamp(uEyes, 0.0, 1.0);
    vec2 asp = vec2(1.0, 503.0 / 270.0);  // gemini.png is 270x503
    float dl = length((uv - uEyeL) * asp);
    float dr = length((uv - uEyeR) * asp);
    float r = 0.045;
    float glow = exp(-dl * dl / (r * r)) + exp(-dr * dr / (r * r));
    float halo = exp(-dl * dl / (r * r * 6.0)) + exp(-dr * dr / (r * r * 6.0));
    float darkness = 1.0 - smoothstep(0.25, 0.6, luma);
    float near = clamp(glow * 1.2, 0.0, 1.0);
    graded = mix(graded, vec3(0.9, 0.02, 0.02), near * darkness * eyes);
    graded += vec3(1.0, 0.08, 0.04) * glow * eyes * 0.9;
    graded += vec3(0.5, 0.0, 0.0) * halo * eyes * 0.35;
    graded += vec3(1.0, 0.6, 0.5) * exp(-dl * dl / (r * r * 0.08)) * eyes * 0.5;
    graded += vec3(1.0, 0.6, 0.5) * exp(-dr * dr / (r * r * 0.08)) * eyes * 0.5;

    // flicker
    float f = hash(vec2(floor(uTime * 24.0), 2.0));
    graded *= 1.0 - uFlicker * (0.55 * step(0.6, f) * (0.4 + 0.6 * hash(vec2(f, 5.0))) + 0.08 * f);

    // grain
    graded += (hash(uv * 700.0 + floor(uTime * 24.0)) - 0.5) * 0.10 * k;

    // invert flash
    graded = mix(graded, vec3(1.0) - graded.gbr * vec3(0.9, 1.0, 1.0), clamp(uInvert, 0.0, 1.0));

    graded = clamp(graded, 0.0, 1.0);
    float a = texture(source, uv).a;
    fragColor = vec4(graded * a, a) * qt_Opacity;
}
