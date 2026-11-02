// pc.js's thresholds and reactions, fed by shell services instead of browser/Windows APIs.
// Text and sound belong to the brain/UI lot; onReaction carries the same semantic events there.
export class Pc {
  constructor(capri, onReaction = () => {}) {
    this.capri = capri;
    this.onReaction = onReaction;
    this.hotSince = null;
    this.hot = false;
    this.hotAt = -Infinity;
    this.charging = null;
    this.chargerAt = -Infinity;
    this.warned = 1;
    this.offSince = null;
    this.cutOff = false;
    this.plugAt = -Infinity;
    this.game = null;
    this.pending = [];
  }

  react(kind, data = {}) { this.onReaction(kind, data); }
  whenFree(action, now) { this.pending.push({ action, until: now + 6000 }); }

  sample({ cpu = null, battery = null, online = null, game = null }, now = Date.now(), quiet = true) {
    const c = this.capri;
    if (cpu !== null) {
      if (cpu < 85) {
        this.hotSince = null;
        if (this.hot && cpu < 55) { this.hot = false; if (quiet) this.react('cool'); }
      } else {
        if (this.hotSince === null) this.hotSince = now;
        if (!this.hot && now - this.hotSince >= 15000 && now - this.hotAt >= 1800000 && quiet) {
          this.hot = true; this.hotAt = now;
          c.wake(); this.react('hot', { cpu });
          this.whenFree(() => c.perform('overheat'), now);
        }
      }
    }
    if (battery) {
      const { level, charging } = battery;
      if (this.charging === null) this.charging = charging;
      if (charging !== this.charging) {
        this.charging = charging;
        if (now - this.chargerAt >= 60000) {
          this.chargerAt = now;
          if (charging) this.warned = 1;
          if (quiet) { this.react(charging ? 'charging' : 'unplugged'); if (charging) c.recharge(); }
        }
      }
      const at = level <= 0.05 ? 0.05 : level <= 0.15 ? 0.15 : 1;
      if (!charging && at < this.warned && quiet) {
        this.warned = at; c.wake(); this.react(at === 0.05 ? 'critical' : 'low', { level });
        this.whenFree(() => c.drain(), now);
      }
    }
    if (online === false) {
      if (this.offSince === null) this.offSince = now;
      if (!this.cutOff && now - this.offSince >= 4000 && quiet) {
        this.cutOff = true; this.react('offline'); c.hurt();
      }
    } else if (online === true) {
      this.offSince = null;
      if (this.cutOff) { this.cutOff = false; if (quiet) { this.react('online'); if (c.free) c.perform('hop'); } }
    }
    const g = this.game;
    if (game) {
      if (g && g.name === game) g.gone = null;
      else this.game = { name: game, since: now, gone: null, said: false, put: !!(g && g.put) };
    } else if (g && g.gone === null) g.gone = now;
    const current = this.game;
    if (current) {
      if (!current.said && current.gone === null && now - current.since >= 6000 && quiet && !c.stowed) {
        current.said = true; current.stowAt = now + 2600;
        c.wake(); this.react('game', { game: current.name });
      }
      if (current.stowAt && current.gone === null && now >= current.stowAt && !c.stowed && quiet && c.free) {
        current.stowAt = null; current.put = true; c.stow();
      }
      if (current.gone !== null && now - current.gone >= 8000) {
        this.game = null;
        if (current.put && c.stowed) { c.unstow(); if (quiet) this.react('gameBack'); }
      }
    }
    const pending = this.pending;
    this.pending = [];
    for (const p of pending) {
      if (now > p.until) continue;
      if (quiet && c.free) p.action();
      else this.pending.push(p);
    }
  }

  device(plug, now = Date.now(), quiet = true) {
    if (!quiet) return;
    const c = this.capri;
    if (plug.kind === 'drive') {
      this.react(plug.in ? 'usb' : 'usbOut', plug);
      if (plug.in) { c.wake(); this.whenFree(() => c.visit({ x: c.view.w - 140, y: c.view.h - 6 }), now); }
      return;
    }
    if (now - this.plugAt < 15000) return;
    this.plugAt = now;
    c.wake();
    if (plug.in && c.free) c.zap(c.view.w - 140, c.view.h - 10);
    this.react(plug.in ? 'plugIn' : 'plugOut', plug);
  }
}
