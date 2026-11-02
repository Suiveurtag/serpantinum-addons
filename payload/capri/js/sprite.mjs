// capri-desktop src/renderer/js/sprite.js (licence in ../LICENSE): her landmarks. The WebGL
// renderer is CapriPet.qml + ../shaders/sprite.frag here.

import { ALPHA_ROWS } from './alpha.mjs';

export const SPRITE = {
  width: 240, height: 420, pad: 56,
  head: { x: 116, y: 132 },
  feet: { x: 128, y: 418 },
  hip: 232, // where she sits
  // the reaching arm, as in the shader; the right arm is it mirrored around x = mirror / 2
  shoulder: { x: 98, y: 168 },
  hand: { x: 24, y: 212 },
  mirror: 234,
  armL(x, y) {
    if (x > 101 || y > 234) return false;
    const top = 159 + (98 - x) * 0.5;
    const bot = x < 50 ? 234 : 178 + (98 - x) * 0.62;
    return y >= top && y <= bot;
  },
  // her silhouette at rest, mirrored arm included (capri.js buildAlphaMap, alpha > 40)
  opaque(x, y) {
    const runs = ALPHA_ROWS[y];
    if (!runs) return false;
    for (let i = 0; i < runs.length; i += 2) if (x >= runs[i] && x < runs[i + 1]) return true;
    return false;
  },
};
