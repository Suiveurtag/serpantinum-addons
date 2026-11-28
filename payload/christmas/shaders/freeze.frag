#version 440
// A panel freezing over: faceted plates of ice crystallise one by one from the four corners and along a thin rim.
// Each plate is a Voronoi cell with its own slant of light and a bright seam; some carry a glint. No texture or time
// uniform: the item only redraws while `grow` animates.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float grow;          // 0..1
    float cornerRadius;
    float unit;          // one scaled pixel
    vec2 extent;
};

vec2 hash2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// How far into the ice a point lies: 0 at a corner or the rim, 1 and beyond stays clear.
float depth(vec2 px) {
    vec2 near = min(px, extent - px);
    float corner = length(near) / (210.0 * unit);
    float rim = min(near.x, near.y) / (26.0 * unit);
    return min(corner, rim);
}

void main() {
    vec2 px = qt_TexCoord0 * extent;
    float size = 24.0 * unit;
    vec2 p = px / size, base = floor(p);
    float first = 9.0, second = 9.0;
    vec2 cell = vec2(0), site = vec2(0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = base + vec2(i, j);
            vec2 at = id + 0.1 + 0.8 * hash2(id);
            float d = length(p - at);
            if (d < first) { second = first; first = d; cell = id; site = at; }
            else if (d < second) second = d;
        }
    }
    vec2 h = hash2(cell + 17.3);
    float reach = depth(clamp(site * size, vec2(0), extent)) + (h.x - 0.5) * 0.35;
    float formed = clamp((grow * 1.25 - reach) / 0.16, 0.0, 1.0);
    float body = formed * (1.0 - smoothstep(0.35, 1.0, reach));

    float turn = h.y * 6.2831853;
    float slant = clamp(dot(p - site, vec2(cos(turn), sin(turn))) + 0.5, 0.0, 1.0);
    float plate = 0.05 + 0.26 * h.x * slant;
    float seam = (1.0 - smoothstep(0.0, 1.5 * unit, (second - first) * size)) * 0.55;
    float flash = formed * (1.0 - formed) * 1.6;      // brightest as the plate sets
    vec2 q = abs(p - site) * size / unit;
    float glint = step(0.8, h.y) * (exp(-q.x * 1.6 - q.y * 0.28) + exp(-q.y * 1.6 - q.x * 0.28));

    vec2 halfSize = extent * 0.5;
    float r = min(cornerRadius, min(halfSize.x, halfSize.y));
    vec2 sq = abs(px - halfSize) - halfSize + vec2(r);
    float dist = length(max(sq, vec2(0))) + min(max(sq.x, sq.y), 0.0) - r;
    float inside = 1.0 - smoothstep(-1.0, 0.0, dist);

    float alpha = clamp((plate + seam + flash * 0.5 + glint * 0.8) * body, 0.0, 0.85) * inside * qt_Opacity;
    vec3 colour = mix(vec3(0.55, 0.78, 1.0), vec3(0.97, 0.99, 1.0), clamp(seam + glint + flash + slant * h.x * 0.6, 0.0, 1.0));
    fragColor = vec4(colour * alpha, alpha);
}
