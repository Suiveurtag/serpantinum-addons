#version 440
// Post-process of the whole dream scene host (ClawdDream.qml), applied as layer.effect.
// uMood 0 dream: gentle wobble, soft glow, pastel violet vignette, twinkling stars behind the content.
// uMood 1 nightmare: black-red vignette, frame flicker, film grain, desaturation, faster jitter.
// uOpen: iris radius opening from uCenter (head, in uv); outside it nothing is drawn. uFade: overall fade. uWobble 0 = reduced motion.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uFade;
    float uMood;
    float uWobble;
    vec2 uCenter;
    float uOpen;
    float uAspect;   // width / height
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float night = clamp(uMood, 0.0, 1.0);
    float t = uTime;
    float frame = floor(t * 24.0);

    // wobble: slow sine in the dream, quick jitter in the nightmare
    vec2 w = vec2(sin(uv.y * 14.0 + t * 1.3), cos(uv.x * 11.0 + t * 1.1)) * 0.0035;
    float jit = (hash(vec2(frame, floor(uv.y * 40.0))) - 0.5) * 0.012 * step(0.82, hash(vec2(frame, 7.0)));
    vec2 suv = uv + uWobble * (mix(w, w * 1.6 + vec2(jit, 0.0), night));
    suv = clamp(suv, vec2(0.0), vec2(1.0));

    vec4 s = texture(source, suv);

    // soft 4-tap glow (premultiplied), stronger in the dream
    vec2 px = vec2(0.006 / uAspect, 0.006);
    vec4 g = texture(source, clamp(suv + vec2(px.x, 0.0), 0.0, 1.0)) + texture(source, clamp(suv - vec2(px.x, 0.0), 0.0, 1.0))
           + texture(source, clamp(suv + vec2(0.0, px.y), 0.0, 1.0)) + texture(source, clamp(suv - vec2(0.0, px.y), 0.0, 1.0));
    g *= 0.25;
    vec4 c = s + g * (0.35 - 0.2 * night) * (1.0 - s.a);
    c.rgb += g.rgb * (0.18 - 0.1 * night);
    c.a = clamp(c.a, 0.0, 1.0);

    // vignette
    vec2 d = (uv - 0.5) * vec2(uAspect, 1.0);
    float v = smoothstep(0.25, 0.85, length(d));
    vec3 dreamTint = vec3(0.42, 0.30, 0.78);
    vec3 nightTint = vec3(0.10, 0.0, 0.01);
    vec3 tint = mix(dreamTint, nightTint, night);
    float vigA = v * mix(0.65, 0.9, night);

    // nightmare grading: desaturation, flicker, grain
    float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    c.rgb = mix(c.rgb, vec3(luma) * vec3(1.05, 0.85, 0.85), 0.35 * night);
    float flick = 1.0 - night * 0.22 * step(0.7, hash(vec2(frame, 3.0))) * (0.5 + hash(vec2(frame, 9.0)));
    c.rgb *= flick;
    c *= 1.0;

    // dream background: soft base haze + twinkling stars where the content is empty
    vec3 bg = vec3(0.0);
    float bgA = 0.0;
    if (night < 0.5) {
        vec2 grid = vec2(48.0, 27.0);
        vec2 cell = floor(uv * grid);
        vec2 f = fract(uv * grid) - 0.5;
        float h = hash(cell);
        float star = step(0.86, h);
        vec2 off = (vec2(hash(cell + 1.7), hash(cell + 5.3)) - 0.5) * 0.4;
        float dist = length((f - off) * vec2(1.0, 1.0));
        float tw = 0.5 + 0.5 * sin(t * (1.5 + h * 3.0) * (0.4 + 0.6 * uWobble) + h * 40.0);
        float sp = star * smoothstep(0.30, 0.0, dist) * (0.35 + 0.65 * tw);
        vec3 starCol = mix(vec3(1.0, 0.93, 0.98), vec3(0.78, 0.85, 1.0), hash(cell + 3.1));
        bgA = sp * (1.0 - night);
        bg = starCol * bgA;
        // faint haze so the host reads as a place
        float haze = 0.10 * (1.0 - v);
        bg += dreamTint * haze;
        bgA += haze;
    }
    c.rgb += bg * (1.0 - c.a);
    c.a += bgA * (1.0 - c.a);

    // vignette over everything (premultiplied "over")
    vec3 vigRgb = tint * vigA;
    c.rgb = vigRgb + c.rgb * (1.0 - vigA);
    c.a = vigA + c.a * (1.0 - vigA);

    // film grain (nightmare)
    float grain = (hash(uv * 900.0 + frame) - 0.5) * 0.16 * night;
    c.rgb += grain * c.a;

    // iris from the head, soft edge
    float r = length((uv - uCenter) * vec2(uAspect, 1.0));
    float maxR = length(vec2(max(uCenter.x, 1.0 - uCenter.x) * uAspect, max(uCenter.y, 1.0 - uCenter.y))) + 0.1;
    float rad = uOpen * maxR;
    float iris = 1.0 - smoothstep(rad - 0.06, rad + 0.01, r);
    iris *= step(0.0001, uOpen);

    c = clamp(c, 0.0, 1.0);
    c.rgb = min(c.rgb, vec3(c.a));
    fragColor = c * (iris * uFade * qt_Opacity);
}
