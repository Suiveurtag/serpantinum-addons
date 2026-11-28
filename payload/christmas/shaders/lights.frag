#version 440
// A string of C9 fairy lights on a sagging wire, drawn in one pass. Sizes are in pixels. Each pixel only looks at
// the three nearest bulbs, so the cost does not grow with the length of the string. The item only redraws when a
// uniform changes: the twinkle clock (about 12 Hz, paused when idle) or the switch-on cascade.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 extent;
    float spacing;   // between bulbs
    float swag;      // between the pins holding the wire
    float sag;       // how far the wire dips between two pins
    float wireY;     // height of the pins from the top
    float bulb;      // bulb half-width
    float phase;     // twinkle clock, seconds
    float twinkle;   // 0 steady .. 1 lively
    float lit;       // switch-on cascade, 0 dark .. 1 every bulb on
    float origin;    // where the cascade starts, 0..1 along the string
    float inward;    // 1: the cascade runs from both ends toward origin
    float lights;    // 0 classic, 1 warm white, 2 candy cane, 3 nordic
    float glow;      // halo strength
    float seed;      // per-string variation
    vec4 wireColor;
};

float hash(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }

vec3 bulbColor(float k) {
    if (lights < 0.5) {
        int i = int(mod(k + floor(seed * 4.0), 4.0));
        return i == 0 ? vec3(1.0, 0.27, 0.22) : i == 1 ? vec3(1.0, 0.74, 0.22) : i == 2 ? vec3(0.22, 0.85, 0.45) : vec3(0.27, 0.62, 1.0);
    }
    if (lights < 1.5) return mix(vec3(1.0, 0.78, 0.45), vec3(1.0, 0.88, 0.66), hash(k * 3.1));
    if (lights < 2.5) return mod(k, 2.0) < 0.5 ? vec3(1.0, 0.2, 0.28) : vec3(1.0, 0.95, 0.92);
    int i = int(mod(k, 3.0));
    return i == 0 ? vec3(0.6, 0.85, 1.0) : i == 1 ? vec3(0.92, 0.96, 1.0) : vec3(1.0, 0.9, 0.68);
}

float wireAt(float x) {
    float t = fract(x / swag);
    return wireY + sag * 4.0 * t * (1.0 - t);
}
float slopeAt(float x) {
    float t = fract(x / swag);
    return sag * 4.0 * (1.0 - 2.0 * t) / swag;
}

// How bright bulb k is right now: its place in the cascade, a flash as it comes on, then its own slow breathing.
float brightness(float k, float cx) {
    float pos = cx / max(extent.x, 1.0);
    float d = abs(pos - origin) / max(max(origin, 1.0 - origin), 0.001);
    if (inward > 0.5) d = 1.0 - d;
    d *= 0.9;
    float on = smoothstep(d, d + 0.1, lit);
    float flash = exp(-pow((lit - d - 0.05) * 16.0, 2.0)) * step(lit, 0.999);
    float h = hash(k);
    float breath = 0.5 + 0.5 * sin(phase * (0.9 + 1.4 * hash(k + 7.0)) + h * 6.2832);
    float dip = twinkle * (0.35 + 0.4 * hash(k + 3.0)) * breath;
    // now and then one bulb catches and sparkles
    float spark = twinkle * pow(max(0.0, sin(phase * 0.37 + h * 40.0)), 60.0) * 0.6;
    return on * (1.0 - dip + spark) + flash * 0.8;
}

void main() {
    vec2 px = qt_TexCoord0 * extent;
    vec4 color = vec4(0.0);

    // halos first, so every bulb and the wire sit on top of them
    float base = floor(px.x / spacing);
    vec3 halo = vec3(0.0);
    float haloA = 0.0;
    for (int j = -1; j <= 1; j++) {
        float k = base + float(j);
        float cx = (k + 0.5) * spacing;
        if (cx < 0.0 || cx > extent.x) continue;
        float b = brightness(k, cx);
        vec2 c = vec2(cx, wireAt(cx) + bulb * 2.4);
        float r = length(px - c);
        // a tight bloom around the glass and a faint wide one
        float g = (exp(-pow(r / (bulb * 2.1), 2.0)) * 0.85 + exp(-r / (bulb * 3.2)) * 0.15) * glow * max(b, 0.0);
        halo += bulbColor(k) * g;
        haloA += g * 0.55;
    }
    color = vec4(halo, min(1.0, haloA));

    // wire
    float wy = wireAt(px.x);
    float wd = abs(px.y - wy) / sqrt(1.0 + pow(slopeAt(px.x), 2.0));
    float wa = (1.0 - smoothstep(0.35, 1.15, wd)) * wireColor.a;
    color = vec4(wireColor.rgb * wa, wa) + color * (1.0 - wa);

    // sockets and bulbs
    for (int j = -1; j <= 1; j++) {
        float k = base + float(j);
        float cx = (k + 0.5) * spacing;
        if (cx < 0.0 || cx > extent.x) continue;
        float tilt = atan(slopeAt(cx)) * 0.7 + (hash(k + 11.0) - 0.5) * 0.5;
        vec2 d = px - vec2(cx, wireAt(cx));
        float cs = cos(tilt), sn = sin(tilt);
        d = vec2(cs * d.x + sn * d.y, -sn * d.x + cs * d.y);

        // socket: a short dark cylinder clipped onto the wire
        float sock = (1.0 - smoothstep(bulb * 0.5, bulb * 0.5 + 0.8, abs(d.x)))
                   * (1.0 - smoothstep(bulb * 1.05, bulb * 1.05 + 0.8, d.y)) * step(-0.6, d.y);
        vec3 sockColor = mix(wireColor.rgb, vec3(0.16, 0.22, 0.17), 0.5) + 0.08 * (1.0 - abs(d.x) / bulb);
        color = vec4(sockColor * sock, sock) + color * (1.0 - sock);

        // glass: a drop, rounder at the top and pointed at the tip
        float ry = bulb * 1.5;
        vec2 c = vec2(0.0, bulb * 1.0 + ry * 0.92);
        vec2 q = d - c;
        float rx = bulb * (1.0 - 0.38 * clamp(q.y / ry, 0.0, 1.0));
        float sd = (length(vec2(q.x / rx, q.y / ry)) - 1.0) * min(rx, ry);
        float body = 1.0 - smoothstep(-0.7, 0.5, sd);
        if (body <= 0.0) continue;
        float b = brightness(k, cx);
        vec3 tint = bulbColor(k);
        float core = exp(-dot(q / vec2(rx, ry), q / vec2(rx, ry)) * 2.2);
        vec3 dark = tint * 0.2 + vec3(0.03, 0.04, 0.04);
        vec3 bright = mix(tint * 1.05, vec3(1.0, 0.98, 0.9), core * 0.6);
        vec3 glass = mix(dark, bright, clamp(b, 0.0, 1.0)) + tint * max(0.0, b - 1.0) * 0.6;
        // a cold highlight on the unlit glass, a hot one on the lit glass
        float spec = exp(-dot(q - vec2(-rx * 0.35, -ry * 0.4), q - vec2(-rx * 0.35, -ry * 0.4)) / (bulb * bulb * 0.08));
        glass += vec3(spec * (0.35 + 0.3 * clamp(b, 0.0, 1.0)));
        color = vec4(glass * body, body) + color * (1.0 - body);
    }

    fragColor = color * qt_Opacity;
}
