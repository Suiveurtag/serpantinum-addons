// Port of capri-desktop reminders.js; upstream licence in ../LICENSE.
import { setInterval } from './util.mjs';
export class Reminders {
  constructor({
    host,
    list = []
  }) {
    this.host = host;
    this.list = Array.isArray(list) ? list : [];
    this.onDue = null;
    this.firing = new Set(); // ids being shown right now
    setInterval(() => this.check(), 5000);
  }

  // the list as saved (after one was cancelled from her menu)
  sync(list) {
    if (Array.isArray(list)) this.list = list;
  }
  get upcoming() {
    return [...this.list].sort((a, b) => a.at - b.at);
  }
  add(at, text) {
    const r = {
      id: `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`,
      at,
      text,
      made: Date.now()
    };
    this.list = [...this.list, r];
    this.save();
    return r;
  }
  remove(id) {
    this.firing.delete(id);
    this.list = this.list.filter(r => r.id !== id);
    this.save();
  }
  snooze(id, ms) {
    this.firing.delete(id);
    this.list = this.list.map(r => r.id === id ? Object.assign({}, r, {
      at: Date.now() + ms
    }) : r);
    this.save();
  }
  save() {
    this.host.setConfig({
      reminders: this.list
    });
  }
  check() {
    if (this.firing.size || !this.onDue) return;
    const due = this.upcoming.find(r => r.at <= Date.now());
    if (!due) return;
    this.firing.add(due.id);
    this.onDue(due);
  }
}
