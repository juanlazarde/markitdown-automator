#!/usr/bin/env bash
# markitdown-automator: setup.sh
# One-time installer. Run once; re-run to update.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.markitdown-automator"
VENV="$HOME/.markitdown-venv"
SERVICES_DIR="$HOME/Library/Services"

green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[1m→ %s\033[0m\n' "$*"; }

echo ""
echo "  MarkItDown Automator — Setup"
echo "  ════════════════════════════"

# ── 1. Check Python ───────────────────────────────────────────────────────────
step "Checking Python 3.10+"

PYTHON=$(command -v python3 2>/dev/null || true)
if [ -z "$PYTHON" ]; then
    red "python3 not found. Install it from python.org or via Homebrew: brew install python"
    exit 1
fi

PY_VERSION=$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 10 ]; }; then
    red "Python 3.10+ required, found $PY_VERSION"
    red "Install a newer version: brew install python"
    exit 1
fi
green "  Python $PY_VERSION ✓"

# ── 2. Create / update venv ───────────────────────────────────────────────────
step "Setting up Python venv at $VENV"

if [ ! -d "$VENV" ]; then
    "$PYTHON" -m venv "$VENV"
    green "  Created venv ✓"
else
    yellow "  Venv already exists — will upgrade packages"
fi

# ── 3. Install markitdown ─────────────────────────────────────────────────────
# To pin a specific version, change to e.g. 'markitdown[all]==0.1.1'
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
    if [ -d "$src" ]; then
        # Require both files to exist, then validate
        for plist in "$src/Contents/document.wflow" "$src/Contents/Info.plist"; do
            if [ ! -f "$plist" ]; then
                red "  MISSING required file: $plist"
                exit 1
            fi
            if ! plutil -lint "$plist" > /dev/null 2>&1; then
                red "  INVALID plist: $plist — aborting install of $workflow"
                red "  Run: plutil -lint \"$plist\" for details"
                exit 1
            fi
        done
        rm -rf "$dst"
        cp -r "$src" "$dst"
        green "  $workflow ✓"
    else
        yellow "  Skipping $workflow (not found in workflows/)"
    fi
done

# ── 6. Enable services in macOS ───────────────────────────────────────────────
step "Reloading macOS Services"

# Reload the Services menu so the new Quick Actions appear immediately
/System/Library/CoreServices/pbs -update 2>/dev/null || true
green "  Services menu refreshed ✓"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
green "════════════════════════════════════════════"
green "  Setup complete!"
echo ""
echo "  File conversion (Finder):"
echo "    Right-click file(s) → Quick Actions → Convert to Markdown"
echo "    Output: .md file alongside the original"
echo ""
echo "  URL conversion (Safari / any browser):"
echo "    Share button → Convert URL to Markdown"
echo "    Output: ~/Downloads/<page-name>.md"
echo ""
echo "  If Quick Actions don't appear immediately:"
echo "    System Settings → Privacy & Security → Extensions → Finder"
echo "    and enable both 'Convert to Markdown' actions"
echo ""
echo "  Logs: ~/Library/Logs/markitdown-automator.log"
green "════════════════════════════════════════════"
echo ""
