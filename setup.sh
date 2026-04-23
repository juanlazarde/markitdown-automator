#!/usr/bin/env bash
# markitdown-automator: setup.sh
# One-time installer. Run once; re-run to update.
# Usage: bash setup.sh [--help | --uninstall | --configure-keys]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.markitdown-automator"
VENV="$HOME/.markitdown-venv"
SERVICES_DIR="$HOME/Library/Services"
LOG_FILE="$HOME/Library/Logs/markitdown-automator.log"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
HOMEBREW_UNINSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[1m→ %s\033[0m\n' "$*"; }

show_help() {
    cat <<'HELP'
MarkItDown Automator setup

MarkItDown Automator adds macOS Quick Actions to convert files and URLs to
Markdown using the MarkItDown library. This setup script installs the necessary
Python environment, scripts, and Quick Actions, and optionally configures
AI API keys for enhanced conversion.

Usage:
  bash setup.sh
      Install or update the local venv, scripts, and Automator Quick Actions.

  bash setup.sh --configure-keys
      Store OpenAI and/or Anthropic API keys in macOS Keychain and install
      the Python packages required for explicit AI conversion.

  bash setup.sh --uninstall
      Remove project-owned files: installed scripts/config, venv, Quick Actions,
      and the MarkItDown Automator log file. You will be asked whether to remove
      API keys from Keychain.

      Homebrew and Python are shared dependencies and are kept by default. If
      they are present, uninstall asks separately whether to remove Homebrew
      Python or Homebrew itself. Press ENTER to keep them.

  bash setup.sh --help
      Show this help text. No dependency checks, installs, Keychain changes,
      or workflow changes are performed.

What setup installs:
  - ~/.markitdown-venv/ with markitdown[all]
  - ~/.markitdown-automator/scripts/convert.sh
  - ~/.markitdown-automator/scripts/llm_convert.py
  - ~/.markitdown-automator/scripts/vision_ocr, when Swift/Xcode tools work
  - ~/Library/Services/Convert to Markdown.workflow
  - ~/Library/Services/Convert URL to Markdown.workflow
  - ~/Library/Services/Convert to Markdown (AI).workflow
  - ~/Library/Logs/markitdown-automator.log during use

Dependency checks:
  - macOS built-ins required: plutil, security, osascript, sw_vers
  - Python 3.10+ is required for the venv and markitdown
  - Homebrew is optional and used only if Python 3.10+ must be installed
  - Xcode Command Line Tools are needed only for local Vision OCR

Admin password prompts:
  Setup checks first and asks before starting any dependency installer that may
  request an administrator password. If Homebrew, Python, or Xcode tools need
  installation, macOS/sudo may ask for your password. This project never reads,
  stores, logs, or forwards that password; entry is handled by macOS/sudo.

AI keys:
  OpenAI and Anthropic keys are stored in macOS Keychain only:
  - service: markitdown-openai, account: api-key
  - service: markitdown-anthropic, account: api-key

After install:
  Restart your Mac if Quick Actions do not appear. Then check:
  System Settings -> Keyboard -> Keyboard Shortcuts -> Services.

Logs:
  ~/Library/Logs/markitdown-automator.log
HELP
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

prompt_yes_no() {
    local prompt="$1" answer=""
    printf '%s [y/N]: ' "$prompt"
    IFS= read -r answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

explain_admin_prompt() {
    local action="$1" reason="$2"
    echo ""
    yellow "  Admin password notice"
    echo "  Action: $action"
    echo "  Why: $reason"
    echo "  macOS or sudo may ask for your administrator password."
    echo "  This project never reads, stores, logs, or forwards that password."
    echo "  Password entry is handled by macOS/sudo for the install command only."
    echo ""
}

python_meets_minimum() {
    local version="$1" major minor
    case "$version" in
        *[!0-9.]*|""|.*|*.) return 1 ;;
    esac
    major=$(printf '%s' "$version" | cut -d. -f1)
    minor=$(printf '%s' "$version" | cut -d. -f2)
    [ -n "$major" ] || return 1
    [ -n "$minor" ] || minor=0
    [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; }
}

refresh_homebrew_path() {
    if [ -x /opt/homebrew/bin/brew ]; then
        PATH="/opt/homebrew/bin:$PATH"
    elif [ -x /usr/local/bin/brew ]; then
        PATH="/usr/local/bin:$PATH"
    fi
    export PATH
}

ensure_homebrew() {
    refresh_homebrew_path
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi

    yellow "  Homebrew is not installed."
    echo "  Homebrew is needed here only to install Python 3.10+ automatically."
    echo "  If you prefer, stop now, install Python 3.10+ yourself, then rerun setup."
    explain_admin_prompt \
        "Install Homebrew using the official installer from $HOMEBREW_INSTALL_URL" \
        "Homebrew may need to create system directories under /opt/homebrew or /usr/local."

    if ! prompt_yes_no "  Install Homebrew now?"; then
        red "  Cannot continue without Python 3.10+. Install Homebrew or Python, then rerun setup."
        exit 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        red "  curl is required to download the Homebrew installer, but it was not found."
        exit 1
    fi

    /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALL_URL")"
    refresh_homebrew_path

    if ! command -v brew >/dev/null 2>&1; then
        red "  Homebrew installation finished, but 'brew' is still not on PATH."
        red "  Open a new terminal or add Homebrew to PATH, then rerun setup."
        exit 1
    fi
}

ensure_python_310() {
    local current_version=""
    PYTHON=$(command -v python3 2>/dev/null || true)
    if [ -n "$PYTHON" ]; then
        current_version=$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
        if python_meets_minimum "$current_version"; then
            green "  Python $current_version ✓"
            return 0
        fi
        yellow "  Python $current_version found, but Python 3.10+ is required."
    else
        yellow "  python3 not found."
    fi

    ensure_homebrew
    explain_admin_prompt \
        "Install or upgrade Python with Homebrew: brew install python" \
        "Python 3.10+ is required to create the isolated venv and install markitdown."

    if ! prompt_yes_no "  Install or upgrade Python with Homebrew now?"; then
        red "  Cannot continue without Python 3.10+."
        exit 1
    fi

    if ! brew install python; then
        yellow "  brew install python failed; trying brew upgrade python"
        brew upgrade python
    fi

    refresh_homebrew_path
    PYTHON=$(command -v python3 2>/dev/null || true)
    if [ -z "$PYTHON" ]; then
        red "  python3 still not found after Homebrew Python install."
        exit 1
    fi
    current_version=$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
    if ! python_meets_minimum "$current_version"; then
        red "  Python 3.10+ required, found $current_version after installation."
        exit 1
    fi
    green "  Python $current_version ✓"
}

have_xcode_tools() {
    command -v swiftc >/dev/null 2>&1 &&
        command -v xcrun >/dev/null 2>&1 &&
        xcrun --show-sdk-path >/dev/null 2>&1
}

offer_xcode_tools_install() {
    yellow "  Xcode Command Line Tools are missing or incomplete."
    echo "  They are required only for local Apple Vision OCR (Tier 2)."
    echo "  Tier 1 markitdown and explicit AI conversion can still be installed without them."
    explain_admin_prompt \
        "Open Apple's Xcode Command Line Tools installer: xcode-select --install" \
        "Apple's installer may need administrator approval to add compiler and SDK tools."

    if prompt_yes_no "  Open the Xcode Command Line Tools installer now?"; then
        xcode-select --install 2>/dev/null || true
        yellow "  Finish the Apple installer, then rerun 'bash setup.sh' to compile Vision OCR."
    else
        yellow "  Skipping Xcode tools install — Tier 2 OCR will be unavailable."
    fi
}

require_system_command() {
    local cmd="$1" purpose="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        red "  Missing required macOS command: $cmd"
        red "  Needed for: $purpose"
        exit 1
    fi
}

offer_homebrew_python_uninstall() {
    refresh_homebrew_path
    if ! command -v brew >/dev/null 2>&1; then
        yellow "  Homebrew not found — no Homebrew Python package to remove"
        return 0
    fi

    # Homebrew installs Python as versioned formulae (python@3.12, python@3.13, etc.)
    # so 'brew list python' misses them. Collect all matching formulae.
    local python_formulae
    python_formulae=$(brew list --formula 2>/dev/null | grep -E '^python' || true)
    if [ -z "$python_formulae" ]; then
        yellow "  No Homebrew Python package found — keeping existing Python installations"
        return 0
    fi

    echo ""
    yellow "  Optional shared dependency cleanup"
    echo "  Homebrew Python ($python_formulae) may be used by other projects or tools on this Mac."
    echo "  The default is to keep it installed."
    if prompt_yes_no "  Remove Homebrew Python ($python_formulae) with 'brew uninstall'?"; then
        # shellcheck disable=SC2086
        brew uninstall $python_formulae
        green "  Homebrew Python removed ✓"
    else
        yellow "  Homebrew Python kept"
    fi
}

offer_homebrew_uninstall() {
    refresh_homebrew_path
    if ! command -v brew >/dev/null 2>&1; then
        yellow "  Homebrew not found — nothing to remove"
        return 0
    fi

    echo ""
    yellow "  Optional shared dependency cleanup"
    echo "  Homebrew is a system-wide package manager and may manage packages for other projects."
    echo "  Removing Homebrew can remove or break unrelated command-line tools."
    echo "  The default is to keep Homebrew installed."
    explain_admin_prompt \
        "Run the official Homebrew uninstall script from $HOMEBREW_UNINSTALL_URL" \
        "Homebrew uninstall may remove package-manager files from /opt/homebrew or /usr/local."

    if ! prompt_yes_no "  Remove Homebrew itself and all Homebrew-managed packages?"; then
        yellow "  Homebrew kept"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        red "  curl is required to download the Homebrew uninstall script, but it was not found."
        return 1
    fi

    /bin/bash -c "$(curl -fsSL "$HOMEBREW_UNINSTALL_URL")"
    green "  Homebrew uninstall script finished ✓"
}

# ── 0. Verify macOS ───────────────────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
    red "This script requires macOS. Detected: $(uname -s)"
    exit 1
fi

for required_cmd in plutil security osascript sw_vers; do
    require_system_command "$required_cmd" "setup validation and macOS integration"
done

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
            if ! "$VENV/bin/pip" install --upgrade $packages_to_install; then
                red "  ERROR: pip install failed — check network connection and disk space"
                exit 1
            fi
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
    step "Removing project-owned files"
    rm -rf "$INSTALL_DIR" && green "  Removed $INSTALL_DIR ✓"
    rm -rf "$VENV"        && green "  Removed $VENV ✓"
    rm -rf "$SERVICES_DIR/Convert to Markdown.workflow" \
           "$SERVICES_DIR/Convert URL to Markdown.workflow" \
           "$SERVICES_DIR/Convert to Markdown (AI).workflow" \
        && green "  Removed Quick Actions ✓"
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        green "  Removed $LOG_FILE ✓"
    else
        yellow "  Log file not found — nothing to remove"
    fi

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

    echo ""
    echo "  Shared dependencies are not project-owned and are kept by default."
    echo "  Only remove them if you know they are not used elsewhere."
    offer_homebrew_python_uninstall
    offer_homebrew_uninstall

    echo ""
    yellow "  Xcode Command Line Tools are shared Apple developer tools and are not removed by this script."
    yellow "  If you installed them only for this project, remove them manually after checking other tools do not need them."

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

# ── 1. Check / install Python ─────────────────────────────────────────────────
step "Checking Python 3.10+"

ensure_python_310

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
    if ! python_meets_minimum "$VENV_PY"; then
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

"$VENV/bin/pip" install --upgrade pip
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
    elif ! have_xcode_tools; then
        offer_xcode_tools_install
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

# Track tmp/old workflow dirs so they are removed if setup is interrupted mid-install.
_wf_tmpdirs=()
_wf_cleanup() {
    local d
    for d in "${_wf_tmpdirs[@]+"${_wf_tmpdirs[@]}"}";
    do
        rm -rf "$d" 2>/dev/null || true
    done
}
trap '_wf_cleanup' EXIT

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
    _wf_tmpdirs+=("$tmp_dst" "$old_dst")

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
