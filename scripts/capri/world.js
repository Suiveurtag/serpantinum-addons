'use strict';
const fs = require('node:fs');

function steamGame(client, readFile = fs.readFileSync) {
  if (!client || !Number.isInteger(client.pid) || client.pid <= 0) return '';
  const direct = /^steam_app_(\d+)$/i.exec(client.class || '');
  let app = direct ? direct[1] : '';
  // Proton/native games inherit SteamAppId. Reading /proc needs no process launch or shell text.
  let pid = client.pid;
  for (let i = 0; !app && pid > 1 && i < 5; i++) {
    try {
      const env = readFile(`/proc/${pid}/environ`, 'utf8');
      app = /(?:^|\0)(?:SteamAppId|SteamGameId)=([1-9]\d*)(?:\0|$)/.exec(env)?.[1] || '';
      if (app) break;
      const status = readFile(`/proc/${pid}/status`, 'utf8');
      pid = Number(/^PPid:\s*(\d+)/m.exec(status)?.[1]) || 0;
    } catch { break; }
  }
  return app && app !== '0' ? String(client.title || `Steam ${app}`).slice(0, 240) : '';
}

module.exports = { steamGame };
