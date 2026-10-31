// Beat / BPM detector, pure. Fed with one level per sample (mean of Cava's low bars, ~every 50 ms): onsets are peaks well above the recent
// average; the tempo is the median gap between onsets (folded into 70-170 BPM) and only counts while the gaps agree. Silence and noise give 0.
export const WINDOW_MS = 1600;   // level history for the adaptive threshold
export const MIN_GAP_MS = 250;   // refractory time between two onsets (240 BPM)
export const KEEP = 16;          // onsets remembered
export const NEED = 6;           // onsets needed before there is a tempo

export function create() { return { hist: [], onsets: [], last: -1e9, bpm: 0 }; }

function stats(hist) {
  const n = hist.length, mean = hist.reduce((a, h) => a + h.v, 0) / n;
  return { mean, sd: Math.sqrt(hist.reduce((a, h) => a + (h.v - mean) ** 2, 0) / n) };
}

function fold(ms) { while (ms < 60000 / 170) ms *= 2; while (ms > 60000 / 70) ms /= 2; return ms; }

export function tempo(onsets) {
  if (onsets.length < NEED) return 0;
  const gaps = onsets.slice(1).map((t, i) => t - onsets[i]);
  const span = (onsets[onsets.length - 1] - onsets[0]) / 1000;
  if (gaps.length / span > 4) return 0;                     // noise: far too many onsets
  const raw = gaps.slice().sort((a, b) => a - b), rmed = raw[Math.floor(raw.length / 2)];
  const steady = gaps.filter(g => Math.abs(g - rmed) <= rmed * 0.12);
  if (steady.length / gaps.length < 0.7) return 0;
  return Math.round(60000 / fold(steady.reduce((a, g) => a + g, 0) / steady.length));
}

// push(state, level 0..1, now ms) -> new state; state.bpm = 0 while there is no steady beat.
export function push(state, level, now) {
  const v = Number.isFinite(level) ? Math.max(0, Math.min(1, level)) : 0;
  const prev = state.hist.length ? state.hist[state.hist.length - 1].v : 0;
  const hist = state.hist.filter(h => now - h.t < WINDOW_MS).concat([{ t: now, v }]);
  let { onsets, last } = state;
  const { mean, sd } = stats(hist);
  // a rising sample clearly above the average, and at least a little in absolute terms
  if (v > prev && v > mean + 1.4 * sd && v > 0.12 && now - last >= MIN_GAP_MS && hist.length > 8) { onsets = onsets.concat([now]).slice(-KEEP); last = now; }
  if (onsets.length && now - onsets[onsets.length - 1] > 3000) onsets = [];   // the music stopped
  return { hist, onsets, last, bpm: tempo(onsets) };
}
