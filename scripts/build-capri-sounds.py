#!/usr/bin/env python3
"""Render Capri's synthesized cues (capri-desktop src/renderer/js/voice.js, Web Audio) to WAV.

QML has no Web Audio, so the same graphs are rendered offline: oscillators and band-passed noise
with exponential envelopes and sweeps, summed into the master gain and its tanh soft clip. Cues
with random parts get a few variants; blips one file per note and mood; throw/crash per power.
Writes payload/capri/sounds/*.wav and payload/capri/js/sounds.mjs (the cue -> files table).
"""
import json
import zlib
import math
import random
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'payload/capri/sounds'
SR = 32000
MASTER = 0.7
BLIP_NOTES = [62, 65, 67, 69, 72, 74, 77, 79]


def midi(n):
    return 440 * 2 ** ((n - 69) / 12)


class Param:
    """An AudioParam's automation: setValueAtTime, exponential and linear ramps."""

    def __init__(self, value):
        self.events = [('set', value, 0.0)]

    def set(self, v, t):
        self.events.append(('set', v, t))
        return self

    def exp(self, v, t):
        self.events.append(('exp', v, t))
        return self

    def lin(self, v, t):
        self.events.append(('lin', v, t))
        return self

    def render(self, n):
        times = np.arange(n) / SR
        out = np.empty(n)
        events = sorted(self.events, key=lambda e: e[2])
        value, at = events[0][1], 0.0
        out[:] = value
        for kind, v, t in events[1:]:
            mask = times >= at
            if kind == 'set':
                out[times >= t] = v
            else:
                seg = mask & (times < t)
                k = np.clip((times[seg] - at) / max(t - at, 1e-9), 0, 1)
                out[seg] = value * (v / value) ** k if kind == 'exp' else value + (v - value) * k
                out[times >= t] = v
            value, at = v, t
        return out


class Voice:
    def __init__(self, seed, length=2.0):
        self.rng = random.Random(seed)
        self.n = int(length * SR)
        self.mix = np.zeros(self.n)
        self.noise = np.random.default_rng(seed).uniform(-1, 1, SR)

    def rand(self, a, b):
        return a + self.rng.random() * (b - a)

    def env(self, t, a, peak, d):
        g = Param(0.0001).set(0.0001, t).exp(peak, t + a).exp(0.0001, t + a + d)
        return g

    def span(self, t, stop):
        return int(t * SR), min(self.n, int(stop * SR))

    def osc(self, kind, freq, t, dur, peak):
        """Returns the frequency param to sweep, then renders on mix() when the cue is done."""
        f = Param(freq).set(freq, t)
        self.pending.append(('osc', kind, f, self.env(t, 0.004, peak, dur), t, t + dur + 0.05))
        return f

    def noise_burst(self, t, dur, peak, f0, f1, q=2.0, gain=None, sweep=None):
        f = sweep or Param(f0).set(f0, t).exp(f1, t + dur)
        g = gain or self.env(t, 0.005, peak, dur)
        self.pending.append(('noise', q, f, g, t, t + dur + 0.05, self.rand(0, 0.5)))

    def render(self):
        for item in self.pending:
            if item[0] == 'osc':
                _, kind, f, g, start, stop = item
                a, b = self.span(start, stop)
                freq = f.render(self.n)[a:b]
                phase = np.cumsum(freq) / SR
                phase -= phase[0] if len(phase) else 0
                x = phase % 1.0
                wave_ = {'sine': np.sin(2 * np.pi * phase), 'square': np.where(x < 0.5, 1.0, -1.0),
                         'sawtooth': 2 * x - 1, 'triangle': 1 - 4 * np.abs(x - 0.5)}[kind]
                self.mix[a:b] += wave_ * g.render(self.n)[a:b]
            else:
                _, q, f, g, start, stop, offset = item
                a, b = self.span(start, stop)
                src = np.roll(self.noise, -int(offset * SR))
                src = np.tile(src, 3)[:b - a]
                freq = f.render(self.n)[a:b]
                y = bandpass(src, freq, q)
                self.mix[a:b] += y * g.render(self.n)[a:b]
        x = np.clip(self.mix * MASTER, -1, 1)
        out = np.tanh(x * 1.6) / math.tanh(1.6)
        loud = np.nonzero(np.abs(out) > 1e-4)[0]
        return out[:loud[-1] + int(0.02 * SR)] if len(loud) else out[:1]


def bandpass(x, freq, q):
    """Web Audio's BiquadFilter 'bandpass' (RBJ, 0 dB peak), coefficients per sample."""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        w0 = 2 * math.pi * min(freq[i], SR / 2 - 1) / SR
        alpha = math.sin(w0) / (2 * q)
        a0 = 1 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2 * math.cos(w0) / a0, (1 - alpha) / a0
        v = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x[i], y1, v
        y[i] = v
    return y


# ---------- the cues, as voice.js plays them ----------

def zap(v, arriving):
    t = 0.0
    o = v.osc('sawtooth', 1600 if arriving else 180, t, 0.22, 0.12)
    o.exp(140 if arriving else 2400, t + 0.2)
    v.noise_burst(t, 0.2, 0.22, 6000 if arriving else 400, 500 if arriving else 7000, 3)
    for i in range(4):
        v.osc('square', v.rand(800, 3200), t + 0.02 + i * 0.035, 0.02, 0.05)
    if arriving:
        v.osc('triangle', 70, t + 0.16, 0.18, 0.3)


def blip(v, note, mood):
    base = note + (5 if mood == 'alert' else -7 if mood == 'error' else 0)
    f = midi(base)
    v.osc('square', f, 0, 0.035, 0.035)
    v.osc('triangle', f * 1.498, 0.004, 0.03, 0.025)
    v.osc('square', f * 0.501, 0.008, 0.03, 0.018)


def tick(v):
    v.noise_burst(0, 0.03, 0.06, 3000, 9000, 8)


def bolt(v, soft):
    k = 0.35 if soft else 1
    o = v.osc('sawtooth', 62, 0, 0.3 * k + 0.05, 0.08 * k)
    o.set(58, 0.05)
    for i in range(3 if soft else 8):
        v.noise_burst(i * v.rand(0.02, 0.045), 0.025, 0.14 * k, v.rand(2500, 6000), v.rand(4000, 9000), 6)


def charge(v):
    f = Param(55).set(55, 0).exp(240, 0.6)
    g = Param(0.0001).set(0.0001, 0).exp(0.07, 0.55).exp(0.0001, 0.66)
    v.pending.append(('osc', 'sawtooth', f, g, 0, 0.7))
    for i in range(6):
        v.noise_burst(0.08 + i * 0.09, 0.02, 0.04 + i * 0.016, 3000, 7000, 6)


def possess(v):
    for i, n in enumerate([79, 76, 72]):
        at = i * 0.11
        v.osc('square', midi(n), at, 0.07, 0.05)
        v.osc('square', midi(n) * 1.012, at + 0.004, 0.06, 0.035)
        v.osc('triangle', midi(n - 12), at + 0.008, 0.07, 0.04)
    v.noise_burst(0, 0.3, 0.05, 1200, 5000, 3)


def rise(v):
    o = v.osc('sawtooth', 160, 0, 0.2, 0.07)
    o.exp(1400, 0.18)
    v.noise_burst(0, 0.18, 0.12, 500, 6000, 2)


def whoosh(v, power):
    k = 0.4 + power * 0.6
    v.noise_burst(0, 0.28, 0.16 * k, 300, 3200 + power * 3000, 1.4)
    o = v.osc('sawtooth', 420 + power * 300, 0, 0.22, 0.05 * k)
    o.exp(90, 0.2)
    for i in range(3):
        v.osc('square', v.rand(1500, 3800), 0.03 + i * 0.03, 0.015, 0.03 * k)


def crash(v, power):
    k = 0.35 + power * 0.65
    o = v.osc('triangle', 130, 0, 0.22, 0.34 * k)
    o.exp(38, 0.2)
    v.noise_burst(0, 0.12, 0.22 * k, 2400, 300, 1.2)
    if power > 0.25:
        for i in range(6):
            v.noise_burst(0.02 + i * v.rand(0.012, 0.03), 0.02, 0.12 * k, v.rand(5000, 9000), v.rand(6000, 10000), 9)
    for i in range(4):
        v.osc('square', v.rand(700, 2600), 0.05 + i * 0.028, 0.018, 0.04 * k)


def remind(v):
    for i, n in enumerate([76, 81, 88]):
        v.osc('triangle', midi(n), i * 0.12, 0.35, 0.08)
        v.osc('sine', midi(n + 12), i * 0.12 + 0.01, 0.25, 0.025)
    v.noise_burst(0.3, 0.4, 0.02, 8000, 12000, 6)


def hiss(v):
    sweep = Param(3500).set(3500, 0).lin(6500, 0.4)
    gain = Param(0.0001).set(0.0001, 0).exp(0.14, 0.08).exp(0.0001, 0.45)
    v.noise_burst(0, 0.45, 0, 0, 0, 1.2, gain=gain, sweep=sweep)
    growl = v.osc('sawtooth', 72, 0, 0.4, 0.07)
    for i in range(1, 9):
        growl.set(64 if i % 2 else 80, i * 0.045)


def land(v):
    o = v.osc('triangle', 150, 0, 0.14, 0.22)
    o.exp(48, 0.12)
    v.noise_burst(0, 0.06, 0.08, 1800, 400, 1.5)


def star(v):
    v.osc('sine', midi(93), 0, 0.9, 0.05)
    v.osc('sine', midi(100), 0.14, 1.2, 0.035)
    v.noise_burst(0.05, 0.6, 0.015, 9000, 12000, 6)


def hello(v):
    for i, n in enumerate([69, 76, 81]):
        v.osc('square', midi(n), i * 0.06, 0.07, 0.06)
    v.noise_burst(0.18, 0.08, 0.06, 2000, 8000, 5)


def done(v):
    for i, n in enumerate([64, 68, 71, 75, 76]):
        v.osc('triangle', midi(n + 12), i * 0.07, 0.28, 0.09)
        v.osc('square', midi(n), i * 0.07, 0.12, 0.035)
    for i in range(7):
        v.osc('square', v.rand(1200, 4200), 0.4 + i * 0.03, 0.018, 0.035)


def alert(v):
    for r in range(2):
        v.osc('square', 988, r * 0.28, 0.09, 0.07)
        v.osc('square', 740, r * 0.28 + 0.11, 0.11, 0.07)


def error(v):
    o = v.osc('sawtooth', 110, 0, 0.32, 0.14)
    o.exp(55, 0.3)
    v.noise_burst(0, 0.25, 0.15, 900, 200, 1.2)
    for i in range(5):
        v.noise_burst(0.05 + i * 0.05, 0.02, 0.12, 4000, 4000, 10)


POWERS = [0.3, 0.6, 1.0]  # throw/crash: power rounded up to the nearest
CUES = {
    'teleport-out': lambda v: zap(v, False), 'teleport-in': lambda v: zap(v, True), 'done': done, 'alert': alert,
    'error': error, 'hello': hello, 'tick': tick, 'star': star, 'land': land, 'rise': rise, 'charge': charge,
    'possess': possess, 'remind': remind, 'jealous': hiss,
    'bolt': lambda v: bolt(v, False), 'bolt:soft': lambda v: bolt(v, True),
    **{f'throw:{i}': (lambda p: lambda v: whoosh(v, p))(p) for i, p in enumerate(POWERS)},
    **{f'crash:{i}': (lambda p: lambda v: crash(v, p))(p) for i, p in enumerate(POWERS)},
    **{f'blip:{m}': None for m in ('talk', 'alert', 'error')},
}


def write(path, samples):
    pcm = (np.clip(samples, -1, 1) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob('*.wav'):
        old.unlink()
    table = {}
    for cue, fn in CUES.items():
        files = []
        if cue.startswith('blip:'):
            renders = [(lambda n, m: lambda v: blip(v, n, m))(n, cue[5:]) for n in BLIP_NOTES]
        else:
            renders = [fn] * 3
        for i, render in enumerate(renders):
            v = Voice(seed=zlib.crc32(f"{cue}:{i}".encode()), length=2.0)
            v.pending = []
            render(v)
            name = f"{cue.replace(':', '-')}-{i}.wav"
            write(OUT / name, v.render())
            files.append(name)
        table[cue] = files
    (ROOT / 'payload/capri/js/sounds.mjs').write_text(
        '// Generated by scripts/build-capri-sounds.py: cue -> rendered variants in ../sounds/.\n'
        'export const SOUNDS = ' + json.dumps(table, indent=1) + ';\n')
    print(f'{sum(len(f) for f in table.values())} files in {OUT}')


if __name__ == '__main__':
    main()
