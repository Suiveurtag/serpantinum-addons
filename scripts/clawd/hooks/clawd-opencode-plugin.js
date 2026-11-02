// Clawd session watch. OpenCode V1 and V2 plugin entry point; observe only.
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';

const SOCKET = path.join(process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`, 'serpantinum', 'clawd.sock');
const sessions = new Map();
const started = new Set();
const terminalEvents = new Set();
const hook = (id, event, extra = {}) => {
  if (!id) return;
  const session = sessions.get(id);
  if (session && session.child) emit(id, event, { agent_id: session.child, agent_type: 'subagent', ...extra });
  else emit(id, event, extra);
};
const clean = (value, max = 80) => typeof value === 'string'
  ? value.replace(/[\x00-\x1f\x7f-\x9f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, '').slice(0, max)
  : '';
const base = (value, max = 40) => typeof value === 'string' && value ? clean(path.basename(value), max) : '';
const object = (value) => value && typeof value === 'object' ? value : {};

function ancestors(pid = process.pid) {
  const pids = [];
  while (pid > 1 && pids.length < 16) {
    pids.push(pid);
    try {
      const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
      pid = Number(stat.slice(stat.lastIndexOf(')') + 2).split(' ')[1]);
    } catch { break; }
  }
  return pids;
}

function send(event) {
  if (!event || typeof event.session_id !== 'string' || !event.session_id) return;
  const socket = net.createConnection(SOCKET);
  socket.setTimeout(150, () => socket.destroy());
  socket.on('error', () => {});
  socket.end(JSON.stringify({ agent: 'opencode', pids: ancestors(), ...event }) + '\n');
}

function route(id) {
  const known = sessions.get(id);
  return known || { id, root: id, dir: '', model: '', child: '' };
}

function emit(id, event, extra = {}) {
  if (!id) return;
  const s = route(id);
  send({ session_id: s.root, event, dir: s.dir, model: s.model, ...(s.child ? { agent_id: s.child, agent_type: 'subagent' } : {}), ...extra });
}

function terminal(id, event) {
  if (!id || terminalEvents.has(id)) return;
  terminalEvents.add(id);
  hook(id, event);
}

function remember(info, fallbackDirectory = '') {
  info = object(info);
  const id = clean(info.id);
  if (!id) return null;
  const parentID = clean(info.parentID);
  const parent = parentID ? route(parentID) : null;
  const session = {
    id,
    root: parent ? parent.root : id,
    dir: base(info.directory || fallbackDirectory),
    model: clean(object(info.model).id, 40),
    child: parent ? id : '',
  };
  sessions.set(id, session);
  return session;
}

function start(id, directory = '', model = '') {
  if (!id) return;
  if (!sessions.has(id)) sessions.set(id, { id, root: id, dir: base(directory), model: '', child: '' });
  const s = sessions.get(id);
  if (directory && !s.dir) s.dir = base(directory);
  if (model) s.model = clean(model, 40);
  if (started.has(id)) return;
  started.add(id);
  if (s.child) emit(id, 'SubagentStart', { agent_id: s.child, agent_type: 'subagent' });
  else emit(id, 'SessionStart');
}

function toolName(value) {
  const name = clean(value, 40);
  const lower = name.toLowerCase();
  return ({ read: 'Read', read_file: 'Read', view: 'Read', edit: 'Edit', write: 'Write', write_file: 'Write',
    apply_patch: 'Edit', bash: 'Bash', terminal: 'Bash', shell: 'Bash', grep: 'Grep', search: 'Grep',
    glob: 'Glob', task: 'Task', delegate_task: 'Task', webfetch: 'WebFetch', web_search: 'WebSearch',
    websearch: 'WebSearch', todowrite: 'TodoWrite' })[lower] || name;
}

function program(value) {
  if (typeof value !== 'string') return '';
  const words = value.match(/(?:[^\s'"\\]+|\\.|'[^']*'?|"(?:\\.|[^"\\])*"?)+/g) || [];
  const word = words.find((part) => !/^[A-Za-z_][A-Za-z0-9_]*=/.test(part));
  if (!word) return '';
  const name = path.basename(word.replace(/^['"]|['"]$/g, ''));
  return /^[\w.+@:-]+$/.test(name) ? clean(name, 24) : '';
}

function target(tool, input) {
  input = object(input);
  switch (tool) {
    case 'Read': case 'Edit': case 'Write': return base(input.filePath || input.file_path || input.path || input.filename, 24);
    case 'Bash': return program(input.command || input.cmd);
    case 'Grep': case 'Glob': return clean(input.pattern, 24);
    case 'WebFetch': try { return clean(new URL(input.url).hostname, 24); } catch { return ''; }
    case 'WebSearch': return clean(input.query, 24);
    case 'Task': return clean(input.description || input.task, 24);
    case 'TodoWrite': return '';
    default: return '';
  }
}

function v1Event(event) {
  event = object(event);
  const props = object(event.properties);
  if (event.type === 'session.created') {
    const s = remember(props.info);
    if (!s) return;
    if (s.child) {
      started.add(s.id);
      hook(s.id, 'SubagentStart');
    }
    else start(s.id, s.dir);
  } else if (event.type === 'session.idle') {
    const id = clean(props.sessionID);
    terminal(id, route(id).child ? 'SubagentStop' : 'Stop');
  } else if (event.type === 'session.error') {
    const id = clean(props.sessionID);
    terminal(id, 'StopFailure');
  } else if (event.type === 'session.deleted') {
    const info = object(props.info), id = clean(info.id);
    if (id) {
      const child = route(id).child;
      hook(id, child ? 'SubagentStop' : 'SessionEnd');
      sessions.delete(id);
      started.delete(id);
      terminalEvents.delete(id);
    }
  } else if (event.type === 'permission.updated') {
    const id = clean(props.sessionID);
    if (id) emit(id, 'Notification', { notification_type: 'permission_prompt' });
  } else if (event.type === 'session.tool.failed') {
    const id = clean(props.sessionID), part = object(props.part), tool = toolName(part.tool || part.name);
    if (id) hook(id, 'PostToolUseFailure', { tool_name: tool });
  }
}

function server(ctx) {
  return {
    event: async ({ event }) => v1Event(event),
    'chat.message': async (input) => {
      const id = clean(input.sessionID);
      const model = object(input.model);
      start(id, ctx.directory, model.modelID);
      terminalEvents.delete(id);
      hook(id, 'UserPromptSubmit', { model: clean(model.modelID, 40) });
    },
    'tool.execute.before': async (input, output) => {
      const id = clean(input.sessionID), tool = toolName(input.tool), args = object(output.args);
      start(id, ctx.directory);
      hook(id, 'PreToolUse', { tool_name: tool, target: target(tool, args) });
    },
    'tool.execute.after': async (input) => {
      const id = clean(input.sessionID), tool = toolName(input.tool);
      hook(id, 'PostToolUse', { tool_name: tool });
    },
  };
}

function v2Event(event) {
  event = object(event);
  // V2 SDK event payloads use `data`; some plugin hosts expose encoded
  // events with `properties`, so accept both shapes.
  const props = object(event.data || event.properties);
  if (event.type === 'session.created') {
    const info = object(props.info);
    const s = remember({ ...info, id: info.id || props.sessionID }, base(object(event.location).directory));
    if (s && !s.child) start(s.id, s.dir);
    else if (s) {
      started.add(s.id);
      hook(s.id, 'SubagentStart');
    }
    return;
  }
  const id = clean(props.sessionID || object(props.info).id);
  if (event.type === 'session.next.prompt.admitted') {
    if (!id) return;
    terminalEvents.delete(id);
    start(id, '', object(props.model).id);
    const model = clean(object(props.model).id, 40) || route(id).model;
    hook(id, 'UserPromptSubmit', model ? { model } : {});
  } else if (event.type === 'session.next.step.started') {
    start(id, '', object(props.model).id);
  } else if (event.type === 'session.idle') terminal(id, route(id).child ? 'SubagentStop' : 'Stop');
  else if (event.type === 'session.next.step.failed' || event.type === 'session.error') terminal(id, 'StopFailure');
  else if (event.type === 'session.deleted') {
    hook(id, route(id).child ? 'SubagentStop' : 'SessionEnd');
    sessions.delete(id);
    started.delete(id);
    terminalEvents.delete(id);
  } else if (event.type === 'permission.asked' || event.type === 'permission.v2.asked') {
    hook(id, 'Notification', { notification_type: 'permission_prompt' });
  } else if (event.type === 'question.asked' || event.type === 'question.v2.asked') {
    hook(id, 'Notification', { notification_type: 'agent_needs_input' });
  }
}

async function setup(ctx) {
  const controller = new AbortController();
  const registrations = [];
  void (async () => {
    for await (const event of ctx.event.subscribe({
      types: ['session.created', 'session.error', 'session.deleted', 'session.idle', 'session.next.prompt.admitted',
        'session.next.step.started', 'session.next.step.failed', 'permission.asked', 'permission.v2.asked',
        'question.asked', 'question.v2.asked'],
      signal: controller.signal,
    })) v2Event(event);
  })().catch(() => {});
  registrations.push(await ctx.tool.hook('execute.before', (event) => {
    const id = clean(event.sessionID), tool = toolName(event.tool);
    start(id, ctx.location && ctx.location.directory);
    hook(id, 'PreToolUse', { tool_name: tool, target: target(tool, event.input) });
  }));
  registrations.push(await ctx.tool.hook('execute.after', (event) => {
    const id = clean(event.sessionID), tool = toolName(event.tool);
    hook(id, event.status === 'error' ? 'PostToolUseFailure' : 'PostToolUse', { tool_name: tool });
  }));
  return async () => {
    controller.abort();
    await Promise.all(registrations.map((registration) => registration.dispose()));
  };
}

const plugin = { id: 'serpantinum.clawd.session-watch', server, setup };
export { server };
export default plugin;
