#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=${1:-"${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-addons-v2/beamer"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
protocol=/usr/share/wayland-protocols/staging/ext-data-control/ext-data-control-v1.xml
wayland-scanner client-header < "$protocol" > "$tmp/ext-data-control-v1-client-protocol.h"
wayland-scanner private-code < "$protocol" > "$tmp/protocol.c"
cc -std=c11 -Wall -Wextra -Werror -O2 $(pkg-config --cflags wayland-client) -I "$tmp" "$here/clipboard_offer.c" "$tmp/protocol.c" $(pkg-config --libs wayland-client) -o "$tmp/clipboard-offer"
mkdir -p "$output"
install -m 755 "$tmp/clipboard-offer" "$output/clipboard-offer"
install -m 755 "$(command -v wl-paste)" "$output/wl-paste"
