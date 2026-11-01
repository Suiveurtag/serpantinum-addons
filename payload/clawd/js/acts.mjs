// Clawd's idle specials (the animations reproduced from reference videos), pure: plan() gives the steps of one, pick() chooses which.
// step = { clip, ms? } a loop clip held for ms, or a one-shot played to its end; { clip, go: { min, max, v: [calm, normal, active] } }
// a loop clip while he walks min..max px across the floor at v px/s (the strips face right: the pet mirrors them going left).
export const NAMES = ['book', 'joy', 'bike', 'carry', 'broom', 'row', 'fish', 'campfire', 'binoc', 'photo', 'nap'];
const WEIGHT = { book: 3, joy: 3, bike: 2, carry: 2, broom: 1.5, row: 2, fish: 2, campfire: 1.5, binoc: 1, photo: 1, nap: 1 };

const between = (rnd, a, b) => Math.round(a + rnd() * (b - a));
const times = (n, f) => { const out = []; for (let i = 0; i < n; i++) out.push(...f(i)); return out; };  // plain loop: Qt's JS engine lacks some Array statics

export function plan(name, rnd) {
  const hold = (clip, a, b) => ({ clip, ms: between(rnd, a, b) }), once = clip => ({ clip });
  switch (name) {
    case 'book':   // reads, blinks now and then (3.6 s then ~5.3 s in the video)
      return [...times(between(rnd, 1, 3), () => [hold('book_idle', 3000, 5500), once('book_blink')]), hold('book_idle', 2500, 4000)];
    case 'joy':    // sits happy, stretches every few seconds
      return [...times(between(rnd, 10, 16), () => [hold('content_idle', 2500, 5000), once('content_bounce')]), hold('content_idle', 1200, 2000)];
    case 'bike': return [{ clip: 'bike_ride', go: { min: 250, max: 700, v: [100, 150, 220] } }];
    case 'carry': return [{ clip: 'carry_walk', go: { min: 200, max: 500, v: [30, 60, 100] } }];
    case 'broom': return [{ clip: 'broom_fly', go: { min: 400, max: 900, v: [150, 220, 300] } }];
    case 'row': return [hold('boat_idle', 2000, 3500), once('boat_row_in'), { clip: 'boat_row', go: { min: 35, max: 60, v: [0.75, 1, 1.25] } }, once('boat_row_out'), hold('boat_idle', 1500, 2500)];
    case 'fish': return [hold('boat_idle', 1500, 2500), once('boat_fish_in'), hold('boat_fish_wait', 4000, 7000), once('boat_fish_catch'), hold('boat_fish_wait', 3000, 5000),
                         once('boat_fish_out'), once('boat_bino'), once('boat_row_brief'), hold('boat_idle', 1200, 2000)];
    case 'campfire': return [hold('camp_stand', 1000, 1500), once('camp_fire_build'), hold('camp_fire_burn', 7000, 12000), once('camp_fire_die'), hold('camp_stand', 1000, 1500)];
    case 'binoc': return [hold('camp_stand', 800, 1200), once('camp_binoc_raise'), hold('camp_binoc_look_right', 3000, 5000), once('camp_binoc_flip_left'),
                          hold('camp_binoc_look_left', 3000, 5000), once('camp_binoc_lower'), hold('camp_stand', 600, 1000)];
    case 'photo': return [hold('camp_stand', 800, 1200), once('camp_camera_raise'), once('camp_camera_shoot'), once('camp_camera_away'), hold('camp_stand', 800, 1200)];
    case 'nap': return [hold('camp_stand', 800, 1200), once('camp_lie_down'), hold('camp_lie_idle', 7000, 14000), once('camp_stand_up'), hold('camp_stand', 1000, 1500)];
    default: return [];
  }
}

// A random special that is not `prev` (weighted); `ok(name)` filters out those whose strips the manifest lacks.
export function pick(prev, rnd, ok) {
  const names = NAMES.filter(n => n !== prev && (!ok || ok(n)));
  const total = names.reduce((a, n) => a + WEIGHT[n], 0);
  let r = rnd() * total;
  for (const n of names) { r -= WEIGHT[n]; if (r < 0) return n; }
  return names.length ? names[names.length - 1] : '';
}
