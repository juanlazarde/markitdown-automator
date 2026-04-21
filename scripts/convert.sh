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

# Derive a safe filename from a URL (uses domain + path slug + timestamp)
url_to_filename() {
    local url="$1"
    # Strip scheme, replace non-alphanumeric runs with dashes, truncate
    local slug
    slug=$(echo "$url" | sed 's|https\?://||' | sed 's|[^a-zA-Z0-9._-]|-|g' | cut -c1-80)
    echo "${slug}-$(date '+%Y%m%d-%H%M%S').md"
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
    echo "Usage: convert.sh file-or-url [file-or-url ...]" >&2
    exit 1
fi

success=0
fail=0

for input in "$@"; do
    if is_url "$input"; then
        # URL → save to ~/Downloads/
        filename=$(url_to_filename "$input")
        output="$HOME/Downloads/$filename"
        log "Converting URL: $input → $output"

        if "$MARKITDOWN" "$input" -o "$output" 2>>"$LOG"; then
            log "OK: $output"
            ((success++)) || true
        else
            log "FAILED URL: $input"
            ((fail++)) || true
        fi
    elif [ -f "$input" ]; then
        # File → save alongside original
        dir=$(dirname "$input")
        stem=$(basename "${input%.*}")
        output="$dir/$stem.md"
        log "Converting file: $input → $output"

        if "$MARKITDOWN" "$input" -o "$output" 2>>"$LOG"; then
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
fi
