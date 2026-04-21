#!/usr/bin/env bash
# markitdown-automator: convert.sh
# Converts files OR URLs to Markdown using markitdown.
#   File usage: convert.sh file1 [file2 ...]   → output alongside each file
#   URL usage:  convert.sh https://...          → output to ~/Downloads/

set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

VENV="$HOME/.markitdown-venv"
LOG="$HOME/Library/Logs/markitdown-automator.log"
mkdir -p "$(dirname "$LOG")"

# ── temp-file tracking and cleanup ───────────────────────────────────────────
# Trap ensures temp files are removed even if the script is killed mid-run.

_tmpfiles=()

cleanup() {
    local f
    for f in "${_tmpfiles[@]+"${_tmpfiles[@]}"}"; do
        rm -f "$f" 2>/dev/null || true
    done
}
trap cleanup EXIT INT TERM

# ── helpers ───────────────────────────────────────────────────────────────────

notify() {
    osascript -e "display notification \"$1\" with title \"MarkItDown\" sound name \"Glass\"" 2>/dev/null || true
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

is_url() {
    [[ "$1" =~ ^https?:// ]]
}

# Move src → dst; falls back to cp+rm when src and dst are on different devices.
safe_mv() {
    local src="$1" dst="$2"
    if ! mv "$src" "$dst" 2>/dev/null; then
        cp "$src" "$dst" && rm -f "$src"
    fi
}

# Derive a safe filename from a URL. seq avoids collisions within one run.
url_to_filename() {
    local url="$1" seq="$2"
    local slug
    # -E for extended regex so https? works correctly on BSD sed (macOS)
    slug=$(printf '%s' "$url" | sed -E 's|https?://||' | sed 's|[^a-zA-Z0-9._-]|-|g' | cut -c1-80)
    printf '%s-%s-%s.md\n' "$slug" "$(date '+%Y%m%d-%H%M%S')" "$seq"
}

# Return a unique backup path that does not already exist.
unique_backup() {
    local base="$1"
    local stem="${base%.md}"
    local candidate="${stem}.bak.md"
    local i=1
    while [ -f "$candidate" ]; do
        candidate="${stem}.bak${i}.md"
        ((i++)) || true
    done
    printf '%s\n' "$candidate"
}

# ── locate markitdown ─────────────────────────────────────────────────────────

if [ -f "$VENV/bin/markitdown" ]; then
    MARKITDOWN="$VENV/bin/markitdown"
else
    MARKITDOWN=$(command -v markitdown 2>/dev/null || true)
fi

if [ -z "$MARKITDOWN" ]; then
    msg="markitdown not found. Run setup.sh to install it."
    log "ERROR: $msg"
    notify "$msg"
    exit 1
fi

# ── convert inputs ────────────────────────────────────────────────────────────

if [ "$#" -eq 0 ]; then
    printf 'Usage: convert.sh file-or-url [file-or-url ...]\n' >&2
    exit 1
fi

success=0
fail=0
url_seq=0

for input in "$@"; do
    if is_url "$input"; then
        # URL → save to ~/Downloads/
        ((url_seq++)) || true
        filename=$(url_to_filename "$input" "$url_seq")
        output="$HOME/Downloads/$filename"

        # mktemp template must end in X's (BSD mktemp requirement)
        tmp=$(mktemp "$HOME/Downloads/.markitdown-tmp-XXXXXX")
        _tmpfiles+=("$tmp")
        log "Converting URL: $input → $output"

        if "$MARKITDOWN" "$input" -o "$tmp" 2>>"$LOG"; then
            safe_mv "$tmp" "$output"
            log "OK: $output"
            ((success++)) || true
        else
            log "FAILED URL: $input"
            ((fail++)) || true
        fi

    elif [ -f "$input" ]; then
        # File → save alongside original
        base=$(basename "$input")
        stem="${base%.*}"
        # Dot-files (e.g. .hidden) produce an empty stem — fall back to full name
        [ -z "$stem" ] && stem="$base"
        dir=$(dirname "$input")
        output="$dir/$stem.md"

        # mktemp template must end in X's (BSD mktemp requirement)
        tmp=$(mktemp "$dir/.markitdown-tmp-XXXXXX")
        _tmpfiles+=("$tmp")
        log "Converting file: $input → $output"

        if "$MARKITDOWN" "$input" -o "$tmp" 2>>"$LOG"; then
            # Backup existing output only after conversion succeeds
            if [ -f "$output" ]; then
                backup=$(unique_backup "$output")
                log "WARN: $output exists — backing up to $backup"
                safe_mv "$output" "$backup"
            fi
            safe_mv "$tmp" "$output"
            log "OK: $output"
            ((success++)) || true
        else
            log "FAILED: $input"
            ((fail++)) || true
        fi

    else
        log "SKIP (not a file or URL): $input"
        ((fail++)) || true
    fi
done

# ── notify result ─────────────────────────────────────────────────────────────

if [ "$fail" -eq 0 ]; then
    if [ "$success" -eq 1 ]; then
        notify "Converted 1 item to Markdown"
    else
        notify "Converted $success items to Markdown"
    fi
else
    notify "$success converted, $fail failed — see ~/Library/Logs/markitdown-automator.log"
    exit 1
fi
