"""Clawd session watch for Hermes Agent. Only short, display-safe activity leaves this plugin."""

from __future__ import annotations

import json
import os
import re
import shlex
import socket
from pathlib import Path

SOCKET = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "serpantinum" / "clawd.sock"
_CHILDREN: dict[str, tuple[str, str, str]] = {}
_STARTED: set[str] = set()
_DIRS: dict[str, str] = {}


def _clean(value, limit=80):
    if not isinstance(value, str):
        return ""
    return re.sub(r"[\x00-\x1f\x7f-\x9f\u200e\u200f\u202a-\u202e\u2066-\u2069]", "", value)[:limit]


def _basename(value, limit=40):
    return _clean(Path(value).name, limit) if isinstance(value, str) and value else ""


def _pids():
    pids, pid = [], os.getpid()
    while pid > 1 and len(pids) < 16:
        pids.append(pid)
        try:
            stat = Path(f"/proc/{pid}/stat").read_text()
            pid = int(stat[stat.rfind(")") + 2:].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return pids


def _send(event, **values):
    session_id = _clean(values.pop("session_id", ""))
    if not session_id or event not in {
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "Notification", "SubagentStart", "SubagentStop", "Stop", "StopFailure", "Interrupt", "SessionEnd",
    }:
        return
    payload = {"agent": "hermes", "event": event, "session_id": session_id, "pids": _pids(), **values}
    try:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(0.05)
        connection.connect(str(SOCKET))
        connection.sendall((json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode())
        connection.close()
    except OSError:
        pass


def _route(session_id):
    session_id = _clean(session_id)
    root, child, role, directory = _CHILDREN.get(session_id, (session_id, "", "", ""))
    return root, child, role, directory


def _directory(session_id, cwd=""):
    session_id = _clean(session_id)
    directory = _DIRS.get(session_id, "")
    if not directory:
        try:
            from agent.runtime_cwd import resolve_agent_cwd
            cwd = cwd or str(resolve_agent_cwd())
        except (ImportError, OSError):
            pass
        directory = _basename(cwd)
        if directory:
            _DIRS[session_id] = directory
    return directory


def _base(session_id, **values):
    root, child, role, directory = _route(session_id)
    payload = {"session_id": root, "dir": directory or _directory(session_id, values.pop("cwd", ""))}
    if child:
        payload.update(agent_id=_clean(child), agent_type=_clean(role or "subagent", 40))
    if model := _clean(values.pop("model", ""), 40):
        payload["model"] = model
    payload.update(values)
    return payload


def _tool_name(value):
    name = _clean(value, 40)
    return {
        "terminal": "Bash", "shell": "Bash", "read_file": "Read", "write_file": "Write",
        "patch": "Edit", "search_files": "Grep", "web_search": "WebSearch", "web_fetch": "WebFetch", "delegate_task": "Task",
    }.get(name.lower(), name)


def _program(value):
    if not isinstance(value, str):
        return ""
    try:
        words = shlex.split(value, posix=True)
    except ValueError:
        return ""
    word = next((part for part in words if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", part)), "")
    name = Path(word).name
    return _clean(name, 24) if re.fullmatch(r"[\w.+@:-]+", name) else ""


def _target(tool, args):
    if not isinstance(args, dict):
        return ""
    if tool in {"Read", "Write", "Edit"}:
        return _basename(args.get("path") or args.get("file_path") or args.get("file"), 24)
    if tool == "Bash":
        return _program(args.get("command") or args.get("cmd"))
    if tool in {"Grep", "Glob", "WebSearch"}:
        return _clean(args.get("pattern") or args.get("query"), 24)
    if tool == "WebFetch":
        try:
            from urllib.parse import urlsplit
            return _clean(urlsplit(args.get("url", "")).hostname, 24)
        except (TypeError, ValueError):
            return ""
    return ""


def _on_session_start(session_id="", model="", cwd="", **kwargs):
    session_id = _clean(session_id)
    if not session_id or session_id in _STARTED:
        return
    _STARTED.add(session_id)
    if not _route(session_id)[1]:
        _send("SessionStart", **_base(session_id, model=model, cwd=cwd))


def _on_prompt(session_id="", model="", cwd="", **kwargs):
    if session_id:
        _send("UserPromptSubmit", **_base(session_id, model=model, cwd=cwd))


def _pre_tool_call(tool_name="", args=None, session_id="", model="", cwd="", **kwargs):
    tool = _tool_name(tool_name)
    if session_id:
        _send("PreToolUse", **_base(session_id, model=model, cwd=cwd, tool_name=tool, target=_target(tool, args)))


def _post_tool_call(tool_name="", args=None, session_id="", model="", status="", cwd="", **kwargs):
    if not session_id:
        return
    tool = _tool_name(tool_name)
    event = "PostToolUseFailure" if status in {"error", "failed", "blocked", "cancelled"} else "PostToolUse"
    _send(event, **_base(session_id, model=model, cwd=cwd, tool_name=tool))


def _on_session_end(session_id="", model="", completed=True, interrupted=False, **kwargs):
    if not session_id or _route(session_id)[1]:
        return
    event = "Interrupt" if interrupted else "Stop" if completed else "StopFailure"
    _send(event, **_base(session_id, model=model))


def _on_session_delete(session_id="", **kwargs):
    if session_id and not _route(session_id)[1]:
        _send("SessionEnd", **_base(session_id))
        _DIRS.pop(_clean(session_id), None)
        _STARTED.discard(_clean(session_id))


def _on_session_reset(old_session_id="", **kwargs):
    if old_session_id and not _route(old_session_id)[1]:
        _send("SessionEnd", **_base(old_session_id))
        _DIRS.pop(_clean(old_session_id), None)
        _STARTED.discard(_clean(old_session_id))


def _subagent_start(parent_session_id="", child_session_id="", child_subagent_id="", child_role="subagent", **kwargs):
    if not parent_session_id or not child_session_id or not child_subagent_id:
        return
    root, parent_child, _, directory = _route(parent_session_id)
    directory = directory or _directory(parent_session_id)
    child = _clean(child_subagent_id)
    _CHILDREN[_clean(child_session_id)] = (root, child, _clean(child_role, 40) or "subagent", directory)
    _send("SubagentStart", **_base(parent_session_id, agent_id=child, agent_type=_clean(child_role, 40) or "subagent"))


def _subagent_stop(parent_session_id="", child_session_id="", child_subagent_id="", **kwargs):
    if not parent_session_id or not child_session_id:
        return
    _send("SubagentStop", **_base(child_session_id, agent_id=_clean(child_subagent_id)))
    _CHILDREN.pop(_clean(child_session_id), None)
    _DIRS.pop(_clean(child_session_id), None)


def register(ctx):
    ctx.register_hook("on_session_start", _on_session_start)
    ctx.register_hook("pre_llm_call", _on_prompt)
    ctx.register_hook("pre_tool_call", _pre_tool_call)
    ctx.register_hook("post_tool_call", _post_tool_call)
    ctx.register_hook("on_session_end", _on_session_end)
    ctx.register_hook("on_session_delete", _on_session_delete)
    ctx.register_hook("on_session_reset", _on_session_reset)
    ctx.register_hook("subagent_start", _subagent_start)
    ctx.register_hook("subagent_stop", _subagent_stop)

    def on_human_input_request(kind="", session_id="", **kwargs):
        if session_id:
            event = "agent_needs_input" if kind == "clarify" else "permission_prompt"
            _send("Notification", **_base(session_id, notification_type=event))

    ctx.register_hook("on_human_input_request", on_human_input_request)
