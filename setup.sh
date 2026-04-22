#!/usr/bin/env bash
# markitdown-automator: setup.sh
# One-time installer. Run once; re-run to update.
# Usage: bash setup.sh [--uninstall | --configure-keys]

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

# ── AI key configuration (shared by --configure-keys and full install) ────────
_configure_keys_interactive() {
    echo ""
    echo "  MarkItDown Automator — Configure AI Keys"
    echo "  ════════════════════════════════════════"
    echo ""
    echo "  API keys are stored in macOS Keychain (never in files on disk)."
    echo "  Press ENTER to skip any provider."
    echo ""

    local openai_key="" anthropic_key=""

    # OpenAI
    printf '  OpenAI API key (sk-...): '
    IFS= read -rs openai_key; printf '\n'
    if [ -n "$openai_key" ]; then
        if security add-generic-password \
                -s markitdown-openai -a api-key -U \
                -w "$openai_key" 2>/dev/null; then
            green "  OpenAI key stored in Keychain ✓"
        else
            red "  Failed to store OpenAI key in Keychain"
        fi
    else
        yellow "  OpenAI skipped"
    fi

    # Anthropic
    printf '  Anthropic API key (sk-ant-...): '
    IFS= read -rs anthropic_key; printf '\n'
    if [ -n "$anthropic_key" ]; then
        if security add-generic-password \
                -s markitdown-anthropic -a api-key -U \
                -w "$anthropic_key" 2>/dev/null; then
            green "  Anthropic key stored in Keychain ✓"
        else
            red "  Failed to store Anthropic key in Keychain"
        fi
    else
        yellow "  Anthropic skipped"
    fi

    # Install Python packages for configured providers
    if [ -x "$VENV/bin/pip" ]; then
        local packages_to_install=""
        local _ok_key _ant_key
        _ok_key=$(security find-generic-password -s markitdown-openai -a api-key -w 2>/dev/null || true)
        _ant_key=$(security find-generic-password -s markitdown-anthropic -a api-key -w 2>/dev/null || true)

        # pymupdf + Pillow needed for both (PDF rendering; Pillow for GIF/TIFF/BMP/HEIC→PNG)
        [ -n "$_ok_key" ] || [ -n "$_ant_key" ] && packages_to_install="pymupdf Pillow"
        [ -n "$_ok_key" ] && packages_to_install="$packages_to_install openai"
        [ -n "$_ant_key" ] && packages_to_install="$packages_to_install anthropic"

        if [ -n "$packages_to_install" ]; then
            step "Installing Python packages for AI providers"
            # shellcheck disable=SC2086
            "$VENV/bin/pip" install --quiet --upgrade $packages_to_install
            green "  Packages installed ✓"
        fi
    else
        yellow "  Python venv not found — run 'bash setup.sh' first, then re-run --configure-keys"
    fi

    # Preferred provider (only asked if both are configured)
    local _ok2 _ant2
    _ok2=$(security find-generic-password -s markitdown-openai -a api-key -w 2>/dev/null || true)
    _ant2=$(security find-generic-password -s markitdown-anthropic -a api-key -w 2>/dev/null || true)

    if [ -n "$_ok2" ] && [ -n "$_ant2" ]; then
        echo ""
        printf '  Preferred provider when both are configured [openai/anthropic] (default: openai): '
        local preferred=""
        IFS= read -r preferred
        preferred=$(printf '%s' "$preferred" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        [ "$preferred" = "anthropic" ] || preferred="openai"

        mkdir -p "$INSTALL_DIR"
        printf 'PREFERRED_LLM_PROVIDER=%s\n' "$preferred" > "$INSTALL_DIR/config"
        green "  Preferred provider: $preferred ✓"
    fi

    echo ""
    green "  Key configuration complete."
    echo "  Test with: bash ~/.markitdown-automator/scripts/convert.sh --llm /path/to/file.pdf"
    echo ""
}

# ── configure-keys mode ───────────────────────────────────────────────────────
if [ "${1:-}" = "--configure-keys" ]; then
    _configure_keys_interactive
    exit 0
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
           "$SERVICES_DIR/Convert to Markdown (AI).workflow" \
        && green "  Removed Quick Actions ✓"

    printf '  Remove AI API keys from Keychain? [y/N]: '
    IFS= read -r _remove_keys
    case "$_remove_keys" in
        [yY]|[yY][eE][sS])
            security delete-generic-password -s markitdown-openai    -a api-key 2>/dev/null || true
            security delete-generic-password -s markitdown-anthropic -a api-key 2>/dev/null || true
            green "  Keychain entries removed ✓"
            ;;
        *)
            yellow "  Keychain entries kept"
            ;;
    esac

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

if [ -f "$SCRIPT_DIR/scripts/llm_convert.py" ]; then
    cp "$SCRIPT_DIR/scripts/llm_convert.py" "$INSTALL_DIR/scripts/llm_convert.py"
    chmod +x "$INSTALL_DIR/scripts/llm_convert.py"
    green "  llm_convert.py installed ✓"
fi

# ── 4b. Compile Vision OCR binary ─────────────────────────────────────────────
# Requires macOS 11+ for VNRecognizeTextRequest .accurate level.
# Compilation failure is non-fatal — Tier 2 is simply unavailable.

if [ -f "$SCRIPT_DIR/scripts/vision_ocr.swift" ]; then
    OS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
    if [ "$OS_MAJOR" -lt 11 ]; then
        yellow "  macOS 11+ required for Vision OCR — skipping Tier 2 (Tier 1 and 3 still work)"
    else
        step "Compiling Vision OCR binary (Tier 2)"
        if swiftc -O \
                -sdk "$(xcrun --show-sdk-path 2>/dev/null)" \
                "$SCRIPT_DIR/scripts/vision_ocr.swift" \
                -o "$INSTALL_DIR/scripts/vision_ocr" \
                2>/dev/null; then
            chmod +x "$INSTALL_DIR/scripts/vision_ocr"
            green "  vision_ocr compiled ✓"
        else
            yellow "  vision_ocr compilation failed — Tier 2 OCR unavailable"
            yellow "  Check Xcode Command Line Tools: xcode-select --install"
        fi
    fi
fi

# ── 5. Install Quick Actions ──────────────────────────────────────────────────
step "Installing Quick Actions to ~/Library/Services/"

mkdir -p "$SERVICES_DIR"

for workflow in \
    "Convert to Markdown.workflow" \
    "Convert URL to Markdown.workflow" \
    "Convert to Markdown (AI).workflow"; do

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

    if [ -d "$dst" ] && ! mv "$dst" "$old_dst"; then
        rm -rf "$tmp_dst"
        red "  Failed to move existing $workflow aside — install aborted, no changes made"
        exit 1
    fi

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

# ── 6. Optional AI provider setup ────────────────────────────────────────────
echo ""
echo "  ── Optional: AI-powered conversion (Tier 3) ──────────────────────────"
echo "  Tier 3 uses OpenAI or Anthropic vision to convert image-only files."
echo "  API keys are stored securely in macOS Keychain."
printf '  Configure AI keys now? [y/N]: '
IFS= read -r _setup_ai
case "$_setup_ai" in
    [yY]|[yY][eE][sS])
        _configure_keys_interactive
        ;;
    *)
        yellow "  Skipped — run 'bash setup.sh --configure-keys' at any time to configure"
        ;;
esac

# ── 7. Reload Services menu ───────────────────────────────────────────────────
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
echo "  AI-powered conversion (image PDFs, scanned docs, photos):"
echo "    Right-click file(s) in Finder → Quick Actions → Convert to Markdown (AI)"
echo "    Configure keys: bash setup.sh --configure-keys"
echo ""
echo "  URL conversion:"
echo "    Safari menu bar → Services → Convert URL to Markdown"
echo "    Output: ~/Downloads/<page>.md"
echo ""
echo "  If Quick Actions don't appear immediately, go to:"
echo "    System Settings → Keyboard → Keyboard Shortcuts → Services"
echo "    and enable the Convert to Markdown entries"
echo ""
echo "  To uninstall: bash setup.sh --uninstall"
echo "  Logs: ~/Library/Logs/markitdown-automator.log"
green "════════════════════════════════════════════"
echo ""
