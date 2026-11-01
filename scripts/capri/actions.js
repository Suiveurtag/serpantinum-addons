'use strict';

// Arguments are always an argv array. Model/user text never becomes shell source.
const fs = require('node:fs'),
  fsp = fs.promises,
  path = require('node:path'),
  os = require('node:os');
const {
  execFile
} = require('node:child_process');
const run = (cmd, args, timeout = 8000) => new Promise((resolve, reject) => execFile(cmd, args, {
  timeout,
  maxBuffer: 4 * 1024 * 1024
}, (e, out) => e ? reject(e) : resolve(out.trim())));
const fold = s => String(s || '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
const filler = new Set('player launcher app the for windows desktop client x64 x86 beta music musique media audio video videos open launch start run ouvre ouvrir lance demarre capri stp please moi le la les un une de du des my mon ma'.split(' '));
function score(query, name) {
  const words = fold(query).split(' ').filter(w => w.length >= 2 && !filler.has(w)),
    n = fold(name);
  if (!words.length) return 0;
  const hit = words.filter(w => n.includes(w));
  return hit.length >= Math.ceil(words.length / 2) && hit.some(w => w.length >= 3 || w === n) ? hit.length / words.length * 10 + n.length / 100 : 0;
}
const blocked = /(^|[-_/ .])(quickshell|hyprland|capri|claude|codex|ollama)([-_/ .]|$)/i;
const riskyExt = /\.(exe|bat|cmd|ps1|vbs|vbe|js|jse|wsf|wsh|msi|msp|reg|scr|com|jar|hta|cpl|pif|sh|run|appimage|desktop|py|pl|rb|so)$/i;
function isPrivateHost(hostname) {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, '').replace(/\.$/, '');
  if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return true;
  if (host.startsWith('::ffff:')) return isPrivateHost(host.slice(7));
  const v4 = host.split('.');
  if (v4.length === 4 && v4.every((part) => /^\d{1,3}$/.test(part) && Number(part) <= 255)) {
    const [a, b] = v4.map(Number);
    return a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) || a >= 224;
  }
  return host.includes(':') && (host === '::1' || host === '::' || host.startsWith('fe80:') || host.startsWith('fc') || host.startsWith('fd') || host.startsWith('ff'));
}

function webUrl(address) {
  const u = new URL(/^https?:\/\//i.test(address) ? address : `https://${address}`);
  if (!['http:', 'https:'].includes(u.protocol) || !u.hostname.includes('.') || u.username || u.password || isPrivateHost(u.hostname)) throw new Error('Invalid web address');
  return u.href;
}
class Actions {
  constructor() {
    this.allowed = new Map();
    this.shown = new Set();
    this.appCache = null;
    this.cacheAt = 0;
  }
  async clients() {
    return JSON.parse(await run('hyprctl', ['clients', '-j']));
  }
  async openApps() {
    const apps = new Map();
    for (const c of await this.clients()) {
      const name = String(c.class || c.initialClass || '');
      if (!name || blocked.test(name) || !Number.isInteger(c.pid) || c.pid <= 1) continue;
      if (!apps.has(name)) apps.set(name, {
        name,
        label: c.initialClass || name
      });
    }
    return [...apps.values()];
  }
  async findApp(name) {
    return (await this.openApps()).map(a => ({
      a,
      s: score(name, a.name + ' ' + a.label)
    })).sort((a, b) => b.s - a.s).find(a => a.s > 0)?.a || null;
  }
  async closeApp(name, force) {
    const app = await this.findApp(name);
    if (!app) return {
      running: false
    };
    const clients = (await this.clients()).filter(c => c.class === app.name && !blocked.test(c.class) && c.pid > 1);
    for (const c of clients) {
      if (force) process.kill(c.pid, 'SIGKILL');else await run('hyprctl', ['dispatch', 'closewindow', `pid:${c.pid}`]);
    }
    await new Promise(r => setTimeout(r, force ? 600 : 2500));
    return {
      running: (await this.clients()).some(c => c.class === app.name)
    };
  }
  async xdg(kind) {
    try {
      return await run('xdg-user-dir', [kind]);
    } catch {
      return path.join(os.homedir(), {
        DESKTOP: 'Desktop',
        DOWNLOAD: 'Downloads',
        DOCUMENTS: 'Documents',
        PICTURES: 'Pictures',
        MUSIC: 'Music',
        VIDEOS: 'Videos'
      }[kind] || '');
    }
  }
  async file(p) {
    const real = await fsp.realpath(p),
      st = await fsp.stat(real);
    return {
      kind: 'file',
      path: real,
      name: path.basename(real),
      folder: path.basename(path.dirname(real)),
      risky: st.isFile() && (riskyExt.test(real) || !!(st.mode & 0o111)),
      mtime: st.mtimeMs
    };
  }
  allow(item) {
    const id = require('node:crypto').randomUUID();
    const value = {
      ...item,
      id
    };
    this.allowed.set(id, value);
    if (this.allowed.size > 512) this.allowed.delete(this.allowed.keys().next().value);
    return value;
  }
  async launchables() {
    if (this.appCache && Date.now() - this.cacheAt < 600000) return this.appCache;
    const items = [],
      seen = new Set();
    const dirs = [path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local/share'), 'applications'), ...(process.env.XDG_DATA_DIRS || '/usr/local/share:/usr/share').split(':').map(p => path.join(p, 'applications'))];
    for (const dir of dirs) {
      let names = [];
      try {
        names = await fsp.readdir(dir);
      } catch {}
      for (const id of names) {
        if (!id.endsWith('.desktop') || seen.has(id)) continue;
        seen.add(id);
        let text;
        try {
          text = await fsp.readFile(path.join(dir, id), 'utf8');
        } catch {
          continue;
        }
        const section = text.split('[Desktop Entry]')[1]?.split(/\n\[/)[0] || '';
        if (/^(NoDisplay|Hidden)=true$/m.test(section)) continue;
        const name = /^Name=(.+)$/m.exec(section)?.[1];
        if (name && /^Type=Application$/m.test(section) && !blocked.test(name)) items.push(this.allow({
          kind: 'app',
          name,
          desktop: id
        }));
      }
    }
    const steam = path.join(os.homedir(), '.local/share/Steam');
    let libraries = [steam];
    try {
      const v = await fsp.readFile(path.join(steam, 'steamapps/libraryfolders.vdf'), 'utf8');
      libraries = [...new Set([...libraries, ...[...v.matchAll(/"path"\s+"([^"]+)"/g)].map(m => m[1])])];
    } catch {}
    for (const lib of libraries) {
      let files = [];
      try {
        files = await fsp.readdir(path.join(lib, 'steamapps'));
      } catch {}
      for (const file of files.filter(f => /^appmanifest_\d+\.acf$/.test(f))) {
        try {
          const v = await fsp.readFile(path.join(lib, 'steamapps', file), 'utf8'),
            id = /"appid"\s+"(\d+)"/.exec(v)?.[1],
            name = /"name"\s+"([^"]+)"/.exec(v)?.[1];
          if (id && name && !/redistributable|dedicated server|steamworks/i.test(name)) items.push(this.allow({
            kind: 'steam',
            name,
            steam: id
          }));
        } catch {}
      }
    }
    const desktop = await this.xdg('DESKTOP');
    try {
      for (const name of await fsp.readdir(desktop)) try {
        items.push(this.allow(await this.file(path.join(desktop, name))));
      } catch {}
    } catch {}
    this.appCache = items;
    this.cacheAt = Date.now();
    return items;
  }
  async findLaunch(text) {
    const folders = {
      downloads: 'DOWNLOAD',
      telechargements: 'DOWNLOAD',
      desktop: 'DESKTOP',
      bureau: 'DESKTOP',
      documents: 'DOCUMENTS',
      pictures: 'PICTURES',
      images: 'PICTURES',
      music: 'MUSIC',
      musique: 'MUSIC',
      videos: 'VIDEOS',
      explorer: 'HOME',
      files: 'HOME',
      fichiers: 'HOME',
      trash: 'TRASH',
      corbeille: 'TRASH'
    };
    const terms = fold(text).split(' ');
    for (const [word, id] of Object.entries(folders)) if (terms.includes(word)) {
      const p = id === 'TRASH' ? 'trash:///' : id === 'HOME' ? os.homedir() : await this.xdg(id);
      return this.allow({
        kind: 'known',
        id: word,
        name: word,
        path: p
      });
    }
    return (await this.launchables()).map(a => ({
      a,
      s: score(text, a.name)
    })).sort((a, b) => b.s - a.s).find(a => a.s > 0)?.a || null;
  }
  async launch(candidate) {
    const item = this.allowed.get(candidate?.id);
    if (!item) throw new Error('This item is no longer available');
    if (item.kind === 'app') await run('gtk-launch', [item.desktop]);else if (item.kind === 'steam') await run('xdg-open', [`steam://rungameid/${item.steam}`]);else await run('xdg-open', [item.path]);
    return {
      ok: true
    };
  }
  async openSite(address) {
    await run('xdg-open', [webUrl(address)]);
    return true;
  }
  async media(action) {
    const map = {
      pause: ['playerctl', ['pause']],
      play: ['playerctl', ['play']],
      next: ['playerctl', ['next']],
      previous: ['playerctl', ['previous']],
      volup: ['wpctl', ['set-volume', '-l', '1.0', '@DEFAULT_AUDIO_SINK@', '10%+']],
      voldown: ['wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', '10%-']],
      mute: ['wpctl', ['set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle']]
    };
    const cmd = map[action];
    if (!cmd) throw new Error('Invalid media action');
    await run(...cmd);
    return true;
  }
  async music(song) {
    let handler = '';
    try {
      handler = await run('xdg-mime', ['query', 'default', 'x-scheme-handler/spotify']);
    } catch {}
    await run('xdg-open', [handler ? `spotify:search:${encodeURIComponent(song)}` : `https://open.spotify.com/search/${encodeURIComponent(song)}`]);
    return true;
  }
  async youtube(song) {
    let title = '',
      url = `https://www.youtube.com/results?search_query=${encodeURIComponent(song)}`;
    try {
      const res = await fetch(url, {
        headers: {
          'user-agent': 'Mozilla/5.0',
          'accept-language': 'en',
          cookie: 'CONSENT=YES+1; SOCS=CAI'
        },
        signal: AbortSignal.timeout(8000)
      });
      const page = await res.text(),
        m = /"videoRenderer":\{"videoId":"([\w-]{11})"[\s\S]*?"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"/.exec(page);
      if (m) {
        url = `https://www.youtube.com/watch?v=${m[1]}`;
        title = JSON.parse('"' + m[2] + '"');
      }
    } catch {}
    await run('xdg-open', [url]);
    return {
      title
    };
  }
  async roblox(game) {
    const q = `https://apis.roblox.com/search-api/omni-search?searchQuery=${encodeURIComponent(game)}&pageType=all&sessionId=${require('node:crypto').randomUUID()}`;
    const res = await fetch(q, {
        signal: AbortSignal.timeout(8000)
      }),
      body = await res.json();
    const found = body.searchResults?.find(g => g.contentGroupType === 'Game')?.contents?.[0];
    const id = String(found?.rootPlaceId || found?.placeId || '');
    if (!/^\d+$/.test(id)) return {};
    let handler = '';
    try {
      handler = await run('xdg-mime', ['query', 'default', 'x-scheme-handler/roblox']);
    } catch {}
    await run('xdg-open', [handler ? `roblox://experiences/start?placeId=${id}` : `https://www.roblox.com/games/${id}`]);
    return {
      name: String(found.name || game).replace(/\[[^\]]*\]|\p{Emoji_Presentation}/gu, '').trim(),
      app: !!handler
    };
  }
  async webSearch(query) {
    await run('xdg-open', [`https://www.google.com/search?q=${encodeURIComponent(query.slice(0, 300))}`]);
    return true;
  }
  async searchFiles({
    query,
    exts = []
  }) {
    const terms = fold(query).split(' ').filter(Boolean),
      home = os.homedir();
    let files = [];
    try {
      files = (await run('plocate', ['-i', '-l', '200', '-b', '--', terms[0] || '.'])).split('\n');
    } catch {
      const dirs = await Promise.all(['DESKTOP', 'DOCUMENTS', 'DOWNLOAD', 'PICTURES', 'MUSIC', 'VIDEOS'].map(k => this.xdg(k)));
      const queue = dirs.map(p => [p, 0]);
      let entries = 0;
      while (queue.length && entries < 40000) {
        const [dir, depth] = queue.shift();
        let kids = [];
        try {
          kids = await fsp.readdir(dir, {
            withFileTypes: true
          });
        } catch {}
        for (const kid of kids) {
          if (++entries > 40000) break;
          if (kid.name.startsWith('.') || kid.name === 'node_modules') continue;
          const p = path.join(dir, kid.name);
          if (kid.isDirectory() && depth < 5) queue.push([p, depth + 1]);else if (kid.isFile()) files.push(p);
        }
      }
    }
    const found = [];
    for (const p of [...new Set(files)]) {
      if (!p.startsWith(home + path.sep) || /\/(node_modules|\.git|\.cache)\/|\/\.local\/share\/Trash\//.test(p) || !terms.every(w => fold(path.basename(p)).includes(w)) || exts.length && !exts.includes(path.extname(p).slice(1).toLowerCase())) continue;
      try {
        const f = await this.file(p);
        if (f.path.startsWith(home + path.sep)) found.push(f);
      } catch {}
    }
    return found.sort((a, b) => b.mtime - a.mtime).slice(0, 8).map(f => {
      this.shown.add(f.path);
      return f;
    });
  }
  async openFile(file, reveal = false) {
    const p = await fsp.realpath(file);
    if (!this.shown.has(p)) throw new Error('Only files shown in chat may be opened');
    if (reveal) {
      try {
        await run('dbus-send', ['--session', '--dest=org.freedesktop.FileManager1', '--type=method_call', '/org/freedesktop/FileManager1', 'org.freedesktop.FileManager1.ShowItems', `array:string:${require('node:url').pathToFileURL(p).href}`, 'string:']);
      } catch {
        await run('xdg-open', [path.dirname(p)]);
      }
    } else await run('xdg-open', [p]);
    return true;
  }
  async screenshot(output) {
    if (output && !/^[\w.-]+$/.test(output)) throw new Error('Invalid output');
    const dir = path.join(await this.xdg('PICTURES'), 'Screenshots');
    await fsp.mkdir(dir, {
      recursive: true
    });
    const p = path.join(dir, `Capri ${new Date().toISOString().replace(/[:.]/g, '-')}.png`);
    await run('grim', [...(output ? ['-o', output] : []), p]);
    this.shown.add(p);
    return this.file(p);
  }
}
module.exports = {
  Actions,
  run,
  score,
  webUrl
};
