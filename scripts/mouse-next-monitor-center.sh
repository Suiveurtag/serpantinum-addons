#!/usr/bin/env bash
# Focus the next monitor and move the mouse to the centre of that monitor.
# Bound to Super+Tab by serpantinum-addons-v2 (window switching).
set -euo pipefail

for tool in hyprctl jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "mouse-next-monitor-center: '$tool' is required" >&2; exit 1; }
done

hyprctl dispatch 'hl.dsp.focus({ monitor = "+1" })' >/dev/null

hyprctl -j monitors \
    | jq -r '.[] | select(.focused) | "\(.x + (.width / .scale / 2 | floor)) \(.y + (.height / .scale / 2 | floor))"' \
    | while read -r x y; do
        hyprctl dispatch "hl.dsp.cursor.move({ x = $x, y = $y })" >/dev/null
    done
