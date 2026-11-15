#!/usr/bin/env bash
# Rebuild the pinned local Niri compatibility build without changing system packages.
set -euo pipefail
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
revision=73a04441fccc78294c3899af8f8cdd2a1e38fa33
source_dir=${SERPANTINUM_NIRI_SOURCE:-"${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-addons-v2/niri-source"}
prefix=${SERPANTINUM_NIRI_PREFIX:-"$HOME/.local/opt/niri-serpantinum"}
if [[ ! -d "$source_dir/.git" ]]; then
    mkdir -p "$source_dir"
    git -C "$source_dir" init -q
    git -C "$source_dir" fetch --depth=1 https://github.com/niri-wm/niri.git "$revision"
    git -C "$source_dir" checkout --detach FETCH_HEAD
fi
[[ $(git -C "$source_dir" rev-parse HEAD) == "$revision" ]] || { echo 'Unexpected Niri source revision; preserved.' >&2; exit 1; }
if git -C "$source_dir" apply --reverse --check "$here/niri-serpantinum.patch" 2>/dev/null; then
    : # Patch already present.
else
    [[ -z $(git -C "$source_dir" status --porcelain) ]] || { echo 'Modified Niri source; preserved.' >&2; exit 1; }
    git -C "$source_dir" apply --check "$here/niri-serpantinum.patch"
    git -C "$source_dir" apply "$here/niri-serpantinum.patch"
fi
cargo build --manifest-path "$source_dir/Cargo.toml" --release --locked -j "${SERPANTINUM_NIRI_JOBS:-6}"
mkdir -p "$prefix/bin"
install -s -m 755 "$source_dir/target/release/niri" "$prefix/bin/.niri.new"
mv "$prefix/bin/.niri.new" "$prefix/bin/niri"
python3 - "$prefix" "$revision" "$here/niri-serpantinum.patch" <<'PY'
import hashlib, json, sys
from pathlib import Path
prefix, revision, patch = sys.argv[1:]
(Path(prefix)/'BUILD.json').write_text(json.dumps(dict(upstream=revision, addonApi=1,
    patchSha256=hashlib.sha256(Path(patch).read_bytes()).hexdigest()), indent=2)+'\n')
PY
"$prefix/bin/niri" --version
