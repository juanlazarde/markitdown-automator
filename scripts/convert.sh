#!/usr/bin/env bash
# markitdown-automator: convert.sh
# Converts files OR URLs to Markdown using markitdown.
#   File usage: convert.sh [--llm [auto|openai|anthropic]] file1 [file2 ...]
#   URL usage:  convert.sh https://...          → .md saved to ~/Downloads/
#
# Three-tier pipeline for image-heavy files (PDF, JPEG, PNG, GIF, etc.):
#   Tier 1 (always):   markitdown — fast, handles text-based files
#   Tier 2 (auto):     Apple Vision OCR — triggers when Tier 1 output is blank
#   Tier 3 (--llm):    LLM vision API — triggered explicitly via --llm flag

set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

VENV="$HOME/.markitdown-venv"
INSTALL_DIR="$HOME/.markitdown-automator"
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
# EXIT trap runs cleanup on normal exit AND after the INT/TERM handlers below.
trap cleanup EXIT
# Re-raise the signal after cleanup so the parent sees the correct exit code
# (130 for SIGINT, 143 for SIGTERM) rather than 0 or a misleading non-zero.
trap 'exit 130' INT
trap 'exit 143' TERM

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

# Retrieve an API key from macOS Keychain; returns empty string if not set.
# MARKITDOWN_SECURITY_CMD overrides the 'security' binary path for testing.
get_keychain_key() {
    ${MARKITDOWN_SECURITY_CMD:-security} find-generic-password -s "$1" -a api-key -w 2>/dev/null || true
}

# Resolve which LLM provider to use for a given mode (auto|openai|anthropic).
# On success sets RESOLVED_PROVIDER and RESOLVED_KEY, returns 0.
# On failure (no key available) returns 1.
resolve_llm_provider() {
    local mode="$1"
    local openai_key anthropic_key preferred

    openai_key=$(get_keychain_key "markitdown-openai")
    anthropic_key=$(get_keychain_key "markitdown-anthropic")

    preferred=""
    if [ -f "$INSTALL_DIR/config" ]; then
        preferred=$(grep -m1 '^PREFERRED_LLM_PROVIDER=' "$INSTALL_DIR/config" \
            | cut -d= -f2 | tr -d '[:space:]')
    fi

    case "$mode" in
        openai)
            if [ -n "$openai_key" ]; then
                RESOLVED_PROVIDER="openai"; RESOLVED_KEY="$openai_key"; return 0
            fi
            ;;
        anthropic)
            if [ -n "$anthropic_key" ]; then
                RESOLVED_PROVIDER="anthropic"; RESOLVED_KEY="$anthropic_key"; return 0
            fi
            ;;
        auto)
            if [ "$preferred" = "openai" ] && [ -n "$openai_key" ]; then
                RESOLVED_PROVIDER="openai"; RESOLVED_KEY="$openai_key"; return 0
            elif [ "$preferred" = "anthropic" ] && [ -n "$anthropic_key" ]; then
                RESOLVED_PROVIDER="anthropic"; RESOLVED_KEY="$anthropic_key"; return 0
            elif [ -n "$openai_key" ]; then
                RESOLVED_PROVIDER="openai"; RESOLVED_KEY="$openai_key"; return 0
            elif [ -n "$anthropic_key" ]; then
                RESOLVED_PROVIDER="anthropic"; RESOLVED_KEY="$anthropic_key"; return 0
            fi
            ;;
    esac
    RESOLVED_PROVIDER=""; RESOLVED_KEY=""
    return 1
}

# Returns 0 (true) if a file is blank or contains < 50 non-whitespace characters.
# Used to decide whether to trigger Tier 2 Vision OCR after Tier 1 markitdown.
is_blank_output() {
    local f="$1"
    [ ! -s "$f" ] && return 0
    local count
    count=$(awk '{gsub(/[[:space:]]/, ""); sum += length($0)} END {print sum+0}' "$f")
    [ "$count" -lt 50 ]
}

is_vision_ocr_supported() {
    local input="$1" ext
    ext="${input##*.}"
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
        pdf|jpg|jpeg|png|gif|tiff|tif|heic|heif|webp|bmp) return 0 ;;
        *) return 1 ;;
    esac
}

# Run Apple Vision OCR (Tier 2) on a file, writing recognized text to $2.
# Supports: PDF, JPEG, PNG, GIF (first frame), TIFF, HEIC, WebP, BMP.
run_vision_ocr() {
    local input="$1" output="$2"
    local ocr_bin="$INSTALL_DIR/scripts/vision_ocr"

    if [ ! -x "$ocr_bin" ]; then
        log "WARN: vision_ocr binary not found at $ocr_bin — Tier 2 unavailable (run setup.sh)"
        return 1
    fi

    log "Tier 2: Vision OCR → $input"
    if "$ocr_bin" "$input" > "$output" 2>>"$LOG"; then
        return 0
    else
        log "WARN: Vision OCR failed for $input"
        return 1
    fi
}

# Run LLM vision conversion (Tier 3) on a file, writing markdown to $2.
# Reads provider and key from macOS Keychain via resolve_llm_provider().
run_llm_convert() {
    local input="$1" output="$2"
    local llm_script="$INSTALL_DIR/scripts/llm_convert.py"

    if [ ! -f "$llm_script" ]; then
        log "ERROR: llm_convert.py not found — run setup.sh to reinstall"
        notify "AI conversion script missing — run setup.sh"
        return 1
    fi

    RESOLVED_PROVIDER=""; RESOLVED_KEY=""
    if ! resolve_llm_provider "${LLM_MODE:-auto}"; then
        log "WARN: No LLM API key configured (mode=${LLM_MODE:-auto})"
        notify "No AI API key configured — run: bash setup.sh --configure-keys"
        return 1
    fi

    log "Tier 3: LLM ($RESOLVED_PROVIDER) → $input"
    if "$VENV/bin/python" "$llm_script" \
            --provider "$RESOLVED_PROVIDER" \
            --api-key  "$RESOLVED_KEY" \
            "$input" "$output" \
            2>>"$LOG"; then
        return 0
    else
        log "WARN: LLM conversion failed for $input (provider=$RESOLVED_PROVIDER)"
        return 1
    fi
}

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

# ── locate markitdown lazily ──────────────────────────────────────────────────

MARKITDOWN=""
ensure_markitdown() {
    if [ -n "$MARKITDOWN" ]; then
        return 0
    fi

    if [ -x "$VENV/bin/markitdown" ]; then
        MARKITDOWN="$VENV/bin/markitdown"
    else
        MARKITDOWN=$(command -v markitdown 2>/dev/null || true)
    fi

    if [ -z "$MARKITDOWN" ]; then
        local msg="markitdown not found. Run setup.sh to install it."
        log "ERROR: $msg"
        notify "$msg"
        return 1
    fi
    return 0
}

# ── parse --llm flag ──────────────────────────────────────────────────────────
# Optional: --llm [auto|openai|anthropic]
#   Skips blank-detection and goes straight to Tier 3 LLM conversion.
#   Must appear before any file/URL arguments.

LLM_MODE=""
if [ "${1:-}" = "--llm" ]; then
    shift
    case "${1:-}" in
        auto|openai|anthropic)
            LLM_MODE="$1"; shift ;;
        -*)
            # Next arg is another flag, treat mode as "auto"
            LLM_MODE="auto" ;;
        *)
            # No valid mode given — default to "auto"; leave $1 as the file argument
            LLM_MODE="auto" ;;
    esac
fi

# ── convert inputs ────────────────────────────────────────────────────────────

if [ "$#" -eq 0 ]; then
    printf 'Usage: convert.sh [--llm [auto|openai|anthropic]] file-or-url [file-or-url ...]\n' >&2
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

        if ! ensure_markitdown; then
            ((fail++)) || true
            continue
        fi
        if "$MARKITDOWN" "$input" -o "$tmp" 2>>"$LOG"; then
            if ! mv "$tmp" "$output" 2>>"$LOG"; then
                log "ERROR: mv failed placing URL output at $output"
                notify "File placement failed for $(basename "$output") — check logs"
                ((fail++)) || true
                continue
            fi
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

        # ── Tier 3: LLM (when explicitly requested via --llm flag) ────────────
        # Runs directly on the source file. Explicit AI conversion must not be
        # blocked by Tier 1 failing to understand the input format.
        if [ -n "$LLM_MODE" ]; then
            if ! run_llm_convert "$input" "$tmp"; then
                log "FAILED (LLM Tier 3): $input"
                ((fail++)) || true
                continue
            fi

        else
            if ! ensure_markitdown; then
                ((fail++)) || true
                continue
            fi

            if "$MARKITDOWN" "$input" -o "$tmp" 2>>"$LOG"; then
                # ── Tier 2: Vision OCR (auto, when Tier 1 output is blank) ───
                # Applies only to OCR-supported PDFs/images. A blank .md is
                # placed (not a failure) if OCR fails for a supported type.
                if is_blank_output "$tmp" && is_vision_ocr_supported "$input"; then
                    log "Tier 1 output blank for $input — trying Tier 2 Vision OCR"
                    run_vision_ocr "$input" "$tmp" || log "WARN: Tier 2 failed — output may be blank"
                fi
            else
                log "FAILED: $input"
                ((fail++)) || true
                continue
            fi
        fi

        # ── Place output (backup existing, then mv temp into place) ───────────
        # Backup any pre-existing output only after conversion succeeds,
        # so a failed conversion never destroys the user's existing file.
        if [ -f "$output" ]; then
            backup=$(unique_backup "$output")
            log "WARN: $output exists — backing up to $backup"
            if ! mv "$output" "$backup" 2>>"$LOG"; then
                log "ERROR: mv failed backing up $output to $backup"
                notify "Backup failed for $(basename "$output") — file was not modified"
                ((fail++)) || true
                continue
            fi
        fi
        if ! mv "$tmp" "$output" 2>>"$LOG"; then
            log "ERROR: mv failed placing output at $output"
            notify "File placement failed for $(basename "$output") — check logs"
            ((fail++)) || true
            continue
        fi
        record_output "$output"
        log "OK: $output"
        ((success++)) || true

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
