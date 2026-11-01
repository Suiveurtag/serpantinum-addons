#!/usr/bin/env bash
# Serpantinum Addons bootstrap.
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons-v2/main/install/install.sh)"
# Arguments after the script are passed to addons.py, e.g.:
#   bash -c "$(curl -fsSL .../install.sh)" _ update
#   bash -c "$(curl -fsSL .../install.sh)" _ --focus uninstall
# Extra option handled here: --ref <tag|branch> (source version to check out).
set -euo pipefail

REPO_SLUG="Suiveurtag/serpantinum-addons-v2"
REPO_URL="https://github.com/${REPO_SLUG}.git"
API_URL="https://api.github.com/repos/${REPO_SLUG}/releases/latest"
ISSUES_URL="https://github.com/${REPO_SLUG}/issues"
SERPANTINUM_URL="https://github.com/ilyamiro/serpantinum"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SRC="${DATA_HOME}/serpantinum-addons-v2/source"

# ---------------------------------------------------------------- colours
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    case "${COLORTERM:-}" in
        truecolor | 24bit) C_ACC=$'\033[38;2;250;179;135m' ;;
        *) C_ACC=$'\033[38;5;216m' ;;
    esac
    C_DIM=$'\033[38;5;243m'
    C_RED=$'\033[38;5;167m'
    C_RST=$'\033[0m'
else
    C_ACC="" C_DIM="" C_RED="" C_RST=""
fi

tilde() {
    local t='~'
    printf '%s' "${1/#$HOME/$t}"
}

header() {
    local cols
    cols="$(tput cols 2>/dev/null || echo 80)"
    printf '\n' >&2
    if [ "$cols" -ge 36 ]; then
        printf '%s╭────────────────────────────────╮%s\n' "$C_ACC" "$C_RST" >&2
        printf '%s│%s ~~◆ serpantinum addons        %s│%s\n' "$C_ACC" "$C_RST" "$C_ACC" "$C_RST" >&2
        printf '%s│%s %-30s %s│%s\n' "$C_ACC" "$C_DIM" "installer" "$C_ACC" "$C_RST" >&2
        printf '%s╰────────────────────────────────╯%s\n' "$C_ACC" "$C_RST" >&2
    else
        printf '%s~~◆ serpantinum addons%s %sinstaller%s\n' "$C_ACC" "$C_RST" "$C_DIM" "$C_RST" >&2
    fi
    printf '\n' >&2
}

step() { printf '%s◆%s %s\n' "$C_ACC" "$C_RST" "$1" >&2; }
child() { printf '%s  ›  %s%s\n' "$C_ACC" "$C_RST" "$1" >&2; }

# fail "what happened" "why" "what to do"
fail() {
    printf '%s✗ %s%s\n' "$C_RED" "$1" "$C_RST" >&2
    [ -n "${2:-}" ] && printf '  %s\n' "$2" >&2
    [ -n "${3:-}" ] && printf '%s  → %s%s\n' "$C_ACC" "$3" "$C_RST" >&2
    printf '%s  issues: %s%s\n' "$C_DIM" "$ISSUES_URL" "$C_RST" >&2
    exit 1
}

# ---------------------------------------------------------------- arguments
REF=""
ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --ref)
            [ "$#" -ge 2 ] || fail "--ref needs a value" "" "Example: --ref v2.0.0"
            REF="$2"
            shift 2
            ;;
        --ref=*)
            REF="${1#--ref=}"
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

# ---------------------------------------------------------------- environment
if [ "$(id -u)" -eq 0 ]; then
    fail "Do not run this as root" \
        "The addons patch your user's Serpantinum install (in your home directory)." \
        "Run it again as your normal user; sudo is only asked for system packages."
fi

# `bash -c "$(curl ...)"` keeps the pipe-less stdin, but a piped run does not: reattach the terminal.
if [ ! -t 0 ] && [ -e /dev/tty ] && { : </dev/tty; } 2>/dev/null; then
    exec </dev/tty
fi

header

pm_install_line() {
    if command -v pacman >/dev/null 2>&1; then
        echo "sudo pacman -S --needed $*"
    elif command -v dnf >/dev/null 2>&1; then
        echo "sudo dnf install ${*//python/python3}"
    elif command -v xbps-install >/dev/null 2>&1; then
        echo "sudo xbps-install -S ${*//python/python3}"
    else
        echo ""
    fi
}

step "Checking tools"
missing=()
command -v git >/dev/null 2>&1 || missing+=("git")
command -v curl >/dev/null 2>&1 || missing+=("curl")
if ! command -v python3 >/dev/null 2>&1; then
    missing+=("python")
elif ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
    fail "Python 3.10 or newer is required" \
        "Found $(python3 --version 2>&1)." \
        "Update it: $(pm_install_line python || true)"
fi
if [ "${#missing[@]}" -gt 0 ]; then
    cmd="$(pm_install_line "${missing[@]}")"
    fail "Missing tools: ${missing[*]//python/python3}" \
        "These are needed to download and run the installer." \
        "${cmd:-Install them with your package manager (supported: pacman, dnf, xbps-install)}, then run this again"
fi
child "git, curl and python3 found"

step "Checking Serpantinum"
if [ ! -f "${STATE_HOME}/serpantinum/version" ] && [ ! -d "${DATA_HOME}/serpantinum" ]; then
    fail "Serpantinum is not installed" \
        "Neither $(tilde "$STATE_HOME")/serpantinum/version nor $(tilde "$DATA_HOME")/serpantinum exists." \
        "Install Serpantinum first: ${SERPANTINUM_URL}"
fi
child "Serpantinum found"

# ---------------------------------------------------------------- source checkout
step "Fetching Serpantinum Addons"
mkdir -p "$(dirname "$SRC")"
if [ ! -d "$SRC/.git" ]; then
    if [ -e "$SRC" ] && [ -n "$(ls -A "$SRC" 2>/dev/null)" ]; then
        fail "$(tilde "$SRC") exists but is not a git checkout" \
            "The installer will not overwrite it." \
            "Remove it (rm -rf $(tilde "$SRC")) and run this again"
    fi
    git clone --quiet "$REPO_URL" "$SRC" ||
        fail "Could not download the addons" "git clone ${REPO_URL} failed." \
            "Check your connection and retry"
else
    if [ -n "$(git -C "$SRC" status --porcelain 2>/dev/null)" ]; then
        fail "The source checkout has local modifications" \
            "$(tilde "$SRC") contains changes that an update would overwrite." \
            "Discard them: git -C $(tilde "$SRC") reset --hard && git -C $(tilde "$SRC") clean -fd"
    fi
    git -C "$SRC" fetch --quiet --tags --prune origin ||
        fail "Could not fetch updates" "git fetch failed." "Check your connection and retry"
fi

resolve_ref() {
    local cand
    for cand in "refs/tags/$1" "refs/tags/v${1#v}" "origin/$1" "$1"; do
        if git -C "$SRC" rev-parse --verify --quiet "${cand}^{commit}" >/dev/null; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

latest_release_tag() {
    # prints the tag; empty output and status 0 when no release exists; status 1 on API errors
    local body http
    body="$(mktemp)"
    http="$(curl -sSL -o "$body" -w '%{http_code}' -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: serpantinum-addons-v2-installer' "$API_URL" 2>/dev/null || true)"
    case "$http" in
        200) python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tag_name") or "")' "$body" ;;
        404) : ;;
        *)
            rm -f "$body"
            return 1
            ;;
    esac
    rm -f "$body"
}

if [ -n "$REF" ]; then
    target="$(resolve_ref "$REF")" ||
        fail "Unknown version: $REF" "It is neither a release tag nor a branch." \
            "List versions with: git -C $(tilde "$SRC") tag"
    label="$REF"
else
    tag="$(latest_release_tag)" ||
        fail "Could not look up the latest release" \
            "The GitHub API did not answer (offline or rate limited)." \
            "Retry later, or pick a version yourself with --ref main"
    if [ -n "$tag" ]; then
        target="$(resolve_ref "$tag")" ||
            fail "Release $tag is not in the checkout" "The tag was not fetched." "Retry in a minute"
        label="$tag"
    else
        target="origin/main"
        label="main (no release published yet)"
    fi
fi
git -C "$SRC" checkout --quiet --detach "$target" ||
    fail "Could not check out $label" "git checkout failed in $(tilde "$SRC")." \
        "Run: git -C $(tilde "$SRC") status"
child "version: $label"

# ---------------------------------------------------------------- hand over
printf '\n' >&2
exec python3 "$SRC/addons.py" ${ARGS[@]+"${ARGS[@]}"}
