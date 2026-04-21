#!/usr/bin/env bash
# markitdown-automator: convert.sh
# Converts files OR URLs to Markdown using markitdown.
#   File usage: convert.sh file1 [file2 ...]   → .md saved alongside each file
#   URL usage:  convert.sh https://...          → .md saved to ~/Downloads/

set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

VENV="$HOME/.markitdown-venv"
LOG="$HOME/Library/Logs/markitdown-automator.log"
mkdir -p "$(dirname "$LOG")"

# ── temp-file tracking ────────────────────────────────────────────────────────
# Registered temp files are removed on EXIT, INT, and TERM so a killed run
# never leaves stray files in source directories or Downloads.

_tmpfiles=()
cleanup() {
    local f
    for f in "${_tmpfiles[@]+"${_tmpfiles[@]}"}"; do
        rm -f "$f" 2>/dev/null || true
    done
}
trap cleanup EXIT INT TERM

# ── output-path collision tracking ───────────────────────────────────────────
# Prevents two inputs that map to the same stem (e.g. "report" and "report.txt"
# both → "report.md") from overwriting each other within a single run.

_outputs_used=""

output_already_used() {
    [ -n "$_outputs_used" ] || return 1
    # -x = whole-line match, -F = fixed string (no regex), -- avoids flag confusion
    printf '%s' "$_outputs_used" | grep -qxF -- "$1"
}

record_output() {
    _outputs_used="${_outputs_used}${1}"$'\n'
}

# ── helpers ───────────────────────────────────────────────────────────────────

notify() {
    # Pass message as AppleScript argv — avoids any string-injection risk
    osascript - "$1" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
    display notification (item 1 of argv) with title "MarkItDown" sound name "Glass"
end run
APPLESCRIPT
}

log() {
    # Collapse newlines/CR to prevent log-injection via crafted file paths
    local msg
    msg=$(printf '%s' "$*" | tr '\n\r' '  ')
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG"
}

is_url() {
    # Case-insensitive: handles HTTPS://, HTTP://, https://, etc.
    local lower
    lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    [[ "$lower" =~ ^https?:// ]]
}

# Derive a filesystem-safe slug from a URL (scheme stripped via parameter
# expansion so BSD sed's lack of /i flag is not an issue).
url_slug() {
    local url="$1"
    local lower no_scheme
    lower=$(printf '%s' "$url" | tr '[:upper:]' '[:lower:]')
    no_scheme="${lower#http://}"
    no_scheme="${no_scheme#https://}"
    printf '%s' "$no_scheme" | sed 's|[^a-zA-Z0-9._-]|-|g' | cut -c1-80
}

# Return the first backup path for $1 that does not yet exist on disk.
unique_backup() {
    local base="$1" stem candidate i=1
    stem="${base%.md}"
    candidate="${stem}.bak.md"
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

    # ── URL ──────────────────────────────────────────────────────────────────
    if is_url "$input"; then
        ((url_seq++)) || true
        slug=$(url_slug "$input")
        ts=$(date '+%Y%m%d-%H%M%S')
        base_name="${slug}-${ts}-${url_seq}"
        output="$HOME/Downloads/${base_name}.md"

        # No-clobber: skip any name that already exists on disk or was used
        # in this run (handles two identical URLs or same-second invocations)
        n=2
        while [ -f "$output" ] || output_already_used "$output"; do
            output="$HOME/Downloads/${base_name}-${n}.md"
            ((n++)) || true
        done

        if ! tmp=$(mktemp "$HOME/Downloads/.markitdown-tmp-XXXXXX" 2>>"$LOG"); then
            log "ERROR: mktemp failed for $input — Downloads may be unwritable or full"
            notify "Cannot create temp file in Downloads — check disk space/permissions"
            ((fail++)) || true
            continue
        fi
        _tmpfiles+=("$tmp")
        log "Converting URL: $input → $output"

        if "$MARKITDOWN" "$input" -o "$tmp" 2>>"$LOG"; then
            mv "$tmp" "$output"
            record_output "$output"
            log "OK: $output"
            ((success++)) || true
        else
            log "FAILED URL: $input"
            ((fail++)) || true
        fi

    # ── directory (unsupported — give a useful message) ───────────────────────
    elif [ -d "$input" ]; then
        log "SKIP (directory — open it and select individual files): $input"
        notify "Skipped folder \"$(basename "$input")\" — select files inside it, not the folder"
        ((fail++)) || true

    # ── regular file ─────────────────────────────────────────────────────────
    elif [ -f "$input" ]; then
        base=$(basename "$input")
        stem="${base%.*}"
        # Dot-files (e.g. .bashrc) produce an empty stem — use the full name
        [ -z "$stem" ] && stem="$base"
        dir=$(dirname "$input")
        output="$dir/$stem.md"

        # Resolve in-run collision: two inputs mapping to the same output path
        # (e.g. "report" and "report.txt") get distinct output filenames.
        if output_already_used "$output"; then
            n=2
            while output_already_used "$dir/${stem}-${n}.md" || [ -f "$dir/${stem}-${n}.md" ]; do
                ((n++)) || true
            done
            output="$dir/${stem}-${n}.md"
        fi

        if ! tmp=$(mktemp "$dir/.markitdown-tmp-XXXXXX" 2>>"$LOG"); then
            log "ERROR: mktemp failed for $input — $(dirname "$input") may be unwritable or full"
            notify "Cannot create temp file in $(dirname "$input") — check permissions"
            ((fail++)) || true
            continue
        fi
        _tmpfiles+=("$tmp")
        log "Converting file: $input → $output"

        if "$MARKITDOWN" "$input" -o "$tmp" 2>>"$LOG"; then
            # Backup any pre-existing output only after conversion succeeds,
            # so a failed conversion never destroys the user's existing file.
            if [ -f "$output" ]; then
                backup=$(unique_backup "$output")
                log "WARN: $output exists — backing up to $backup"
                mv "$output" "$backup"
            fi
            mv "$tmp" "$output"
            record_output "$output"
            log "OK: $output"
            ((success++)) || true
        else
            log "FAILED: $input"
            ((fail++)) || true
        fi

    # ── unrecognized ─────────────────────────────────────────────────────────
    else
        log "SKIP (not a file, folder, or URL): $input"
        ((fail++)) || true
    fi

done

# ── summary notification ──────────────────────────────────────────────────────

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
