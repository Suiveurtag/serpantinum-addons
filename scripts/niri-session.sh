#!/usr/bin/env bash
set -euo pipefail
binary="$HOME/.local/opt/niri-serpantinum/bin/niri"
[[ -x "$binary" ]] || { echo 'Build Niri with compositor/build-niri.sh first.' >&2; exit 1; }
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
    echo 'Start this session from the login screen or a TTY after leaving the current desktop.' >&2
    exit 1
fi
export PATH="$HOME/.local/bin:$HOME/.local/opt/niri-serpantinum/satellite/usr/bin:$PATH"
export XDG_CURRENT_DESKTOP=niri XDG_SESSION_DESKTOP=niri XDG_SESSION_TYPE=wayland
export NIRI_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
unset HYPRLAND_INSTANCE_SIGNATURE SWAYSOCK MANGO_INSTANCE_SIGNATURE NIRI_SOCKET
"$binary" validate -c "$NIRI_CONFIG"
exec "$binary" --session -c "$NIRI_CONFIG"
