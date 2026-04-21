#!/usr/bin/env bash
# markitdown-automator: setup.sh
# One-time installer. Run once; re-run to update.
# Usage: bash setup.sh [--uninstall]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.markitdown-automator"
VENV="$HOME/.markitdown-venv"
SERVICES_DIR="$HOME/Library/Services"

green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[1m→ %s\033[0m\n' "$*"; }

# ── 0. Verify macOS ───────────────────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
    red "This script requires macOS. Detected: $(uname -s)"
    exit 1
fi

# ── uninstall mode ────────────────────────────────────────────────────────────
if [ "${1:-}" = "--uninstall" ]; then
    echo ""
    echo "  MarkItDown Automator — Uninstall"
    echo "  ════════════════════════════════"
    step "Removing installed files"
    rm -rf "$INSTALL_DIR" && green "  Removed $INSTALL_DIR ✓"
    rm -rf "$VENV"        && green "  Removed $VENV ✓"
    rm -rf "$SERVICES_DIR/Convert to Markdown.workflow" \
           "$SERVICES_DIR/Convert URL to Markdown.workflow" \
        && green "  Removed Quick Actions ✓"
    if /System/Library/CoreServices/pbs -update 2>/dev/null; then
        green "  Services menu refreshed ✓"
    else
        yellow "  pbs -update failed — you may need to log out and back in"
    fi
    echo ""
    green "Uninstalled successfully."
    exit 0
fi

echo ""
echo "  MarkItDown Automator — Setup"
echo "  ════════════════════════════"

# ── 1. Check Python ───────────────────────────────────────────────────────────
step "Checking Python 3.10+"

PYTHON=$(command -v python3 2>/dev/null || true)
if [ -z "$PYTHON" ]; then
    red "python3 not found. Install via Homebrew: brew install python"
    exit 1
fi

PY_VERSION=$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(printf '%s' "$PY_VERSION" | cut -d. -f1)
PY_MINOR=$(printf '%s' "$PY_VERSION" | cut -d. -f2)

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 10 ]; }; then
    red "Python 3.10+ required, found $PY_VERSION"
    red "Install a newer version: brew install python"
    exit 1
fi
green "  Python $PY_VERSION ✓"

# ── 2. Create / validate / update venv ───────────────────────────────────────
step "Setting up Python venv at $VENV"

needs_venv=false
if [ ! -d "$VENV" ]; then
    needs_venv=true
elif [ ! -f "$VENV/bin/python" ] || [ ! -f "$VENV/bin/pip" ]; then
    yellow "  Venv is incomplete — recreating"
    rm -rf "$VENV"
    needs_venv=true
else
    # Verify the venv's Python still meets the version floor
    VENV_PY=$("$VENV/bin/python" -c \
        'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' \
        2>/dev/null || echo "0.0")
    VENV_MAJOR=$(printf '%s' "$VENV_PY" | cut -d. -f1)
    VENV_MINOR=$(printf '%s' "$VENV_PY" | cut -d. -f2)
    if [ "$VENV_MAJOR" -lt 3 ] || { [ "$VENV_MAJOR" -eq 3 ] && [ "$VENV_MINOR" -lt 10 ]; }; then
        yellow "  Venv Python $VENV_PY is too old — recreating"
        rm -rf "$VENV"
        needs_venv=true
    else
        yellow "  Venv exists (Python $VENV_PY) — will upgrade packages"
    fi
fi

if [ "$needs_venv" = true ]; then
    "$PYTHON" -m venv "$VENV"
    green "  Created venv ✓"
fi

# ── 3. Install markitdown ─────────────────────────────────────────────────────
# To pin a specific version change to e.g. 'markitdown[all]==0.1.1'
MARKITDOWN_PKG="markitdown[all]"

step "Installing $MARKITDOWN_PKG (this may take a minute)"

"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --upgrade "$MARKITDOWN_PKG"
green "  markitdown installed ✓"

MARKITDOWN_VERSION=$("$VENV/bin/markitdown" --version 2>/dev/null || echo "unknown")
green "  Version: $MARKITDOWN_VERSION"

# ── 4. Install scripts ────────────────────────────────────────────────────────
step "Installing scripts to $INSTALL_DIR"

mkdir -p "$INSTALL_DIR/scripts"
cp "$SCRIPT_DIR/scripts/convert.sh" "$INSTALL_DIR/scripts/convert.sh"
chmod +x "$INSTALL_DIR/scripts/convert.sh"
green "  convert.sh installed ✓"

# ── 5. Install Quick Actions ──────────────────────────────────────────────────
step "Installing Quick Actions to ~/Library/Services/"

mkdir -p "$SERVICES_DIR"

for workflow in \
    "Convert to Markdown.workflow" \
    "Convert URL to Markdown.workflow"; do

    src="$SCRIPT_DIR/workflows/$workflow"
    dst="$SERVICES_DIR/$workflow"

    if [ ! -d "$src" ]; then
        yellow "  Skipping $workflow (not found in workflows/)"
        continue
    fi

    # Require both plist files to exist and be valid before touching the live install
    for plist in "$src/Contents/document.wflow" "$src/Contents/Info.plist"; do
        if [ ! -f "$plist" ]; then
            red "  MISSING required file: $plist"
            exit 1
        fi
        if ! plutil -lint "$plist" > /dev/null 2>&1; then
            red "  INVALID plist: $plist"
            red "  Run: plutil -lint \"$plist\" for details"
            exit 1
        fi
    done

    # Fully atomic install:
    #   1. Copy src → tmp (if this fails, dst is untouched)
    #   2. Move dst → old backup (dst is now gone, but old is safe)
    #   3. Move tmp → dst (if this fails, restore old from backup)
    #   4. Delete old backup
    tmp_dst="${SERVICES_DIR}/.markitdown-${workflow}.tmp.$$"
    old_dst="${SERVICES_DIR}/.markitdown-${workflow}.old.$$"

    if ! cp -r "$src" "$tmp_dst"; then
        rm -rf "$tmp_dst"
        red "  Failed to copy $workflow — existing install unchanged"
        exit 1
    fi

    [ -d "$dst" ] && mv "$dst" "$old_dst"

    if mv "$tmp_dst" "$dst"; then
        rm -rf "$old_dst"
        green "  $workflow ✓"
    else
        rm -rf "$tmp_dst"
        # Restore previous install so we don't leave the user with nothing
        [ -d "$old_dst" ] && mv "$old_dst" "$dst"
        red "  Failed to install $workflow — previous install restored"
        exit 1
    fi

done

# ── 6. Reload Services menu ───────────────────────────────────────────────────
step "Reloading macOS Services"

if /System/Library/CoreServices/pbs -update 2>/dev/null; then
    green "  Services menu refreshed ✓"
else
    yellow "  pbs -update failed — you may need to log out and back in"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
green "════════════════════════════════════════════"
green "  Setup complete!"
echo ""
echo "  File conversion:"
echo "    Right-click file(s) in Finder → Quick Actions → Convert to Markdown"
echo "    Output: .md saved alongside the original file"
echo ""
echo "  URL conversion:"
echo "    Safari Share button → Convert URL to Markdown"
echo "    Output: ~/Downloads/<page>.md"
echo ""
echo "  If Quick Actions don't appear immediately, go to:"
echo "    System Settings → Keyboard → Keyboard Shortcuts → Services"
echo "    and enable both Convert to Markdown entries"
echo ""
echo "  To uninstall: bash setup.sh --uninstall"
echo "  Logs: ~/Library/Logs/markitdown-automator.log"
green "════════════════════════════════════════════"
echo ""
