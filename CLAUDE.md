# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A macOS-only personal tool that wraps [Microsoft's `markitdown`](https://github.com/microsoft/markitdown) CLI with native Automator Quick Actions, eliminating the need to open a terminal. Converts files (PDF, DOCX, PPTX, images, HTML, etc.) and URLs (including YouTube) to Markdown.

## Running / Testing

```bash
# One-time install (creates venv, installs markitdown, registers Quick Actions)
bash setup.sh

# Uninstall everything
bash setup.sh --uninstall

# Test conversion directly from the terminal
bash scripts/convert.sh path/to/file.pdf
bash scripts/convert.sh https://www.youtube.com/watch?v=...

# Check logs if something goes wrong
cat ~/Library/Logs/markitdown-automator.log
```

No build step. No test suite. This is a shell script project.

## Architecture

```
setup.sh              → one-time installer / uninstaller
scripts/convert.sh    → core conversion logic (called by both Quick Actions)
workflows/
  Convert to Markdown.workflow          → Finder right-click Quick Action (files)
  Convert URL to Markdown.workflow      → Safari Share Sheet Quick Action (URLs)
```

**Runtime install locations** (created by `setup.sh`):
- `~/.markitdown-venv/` — isolated Python venv with `markitdown[all]`
- `~/.markitdown-automator/scripts/convert.sh` — copy of the script the workflows call
- `~/Library/Services/*.workflow` — installed Quick Actions

**Data flow:**
1. User triggers a Quick Action → Automator calls the embedded shell bootstrap in `document.wflow`
2. Bootstrap calls `~/.markitdown-automator/scripts/convert.sh` with file paths or URLs
3. `convert.sh` locates `markitdown` (venv `-x` check first, then `$PATH`), runs it, writes `.md` output
4. macOS notification sent via AppleScript argv (injection-safe); errors appended to `~/Library/Logs/markitdown-automator.log`

**Output locations:**
- Files → `.md` saved alongside the original file (same directory, same stem)
- URLs → `~/Downloads/<url-slug>-<timestamp>-<seq>.md` (no-clobber: increments if file exists)

## convert.sh — Key Behaviours

- **Temp-first writes**: converts to a `mktemp` file, moves into place only on success — a failed conversion never touches the existing `.md`
- **Backup on overwrite**: if `output.md` already exists, it is renamed to `output.bak.md` (then `.bak1.md`, etc.) before the new file is placed
- **In-run collision tracking**: two inputs with the same stem (e.g. `report` and `report.txt`) produce `report.md` and `report-2.md` rather than clobbering each other
- **Signal handling**: `trap cleanup EXIT` + `trap 'exit 130' INT` + `trap 'exit 143' TERM` — temp files are always cleaned up, parent sees correct exit codes
- **Pinning markitdown**: change `MARKITDOWN_PKG` in `setup.sh` (line ~102) to pin a version, e.g. `markitdown[all]==0.1.1`

## setup.sh — Key Behaviours

- Validates existing venv has `bin/python` and `bin/pip` and meets Python 3.10+; recreates if broken or outdated
- Workflow install is atomic: copy → temp sibling, move old → backup, move new → live, delete backup; restores old install if any step fails
- `plutil -lint` validates both `document.wflow` and `Info.plist` before touching the live install

## Workflow Bundle Format

`*.workflow` bundles are plist XML. The key files are `Contents/document.wflow` and `Contents/Info.plist`. When modifying workflows:
- `workflowTypeIdentifier: com.apple.Automator.servicesMenu` makes it a Quick Action
- `serviceInputTypeIdentifier: com.apple.Automator.fileSystemObject` = accepts files (Finder)
- `serviceInputTypeIdentifier: com.apple.Automator.url` = accepts URLs (Safari Share)
- `inputMethod: 1` in `ActionParameters` = files passed as shell arguments; `0` = via stdin
- `Contents/Info.plist` must declare `NSServices` — without it macOS silently ignores the workflow
- Always run `plutil -lint` after editing any plist; `setup.sh` will refuse to install an invalid bundle
- Both `public.url` and `NSURLPboardType` are declared in the URL workflow's `Info.plist` for broadest share sheet compatibility

After editing a workflow bundle, re-run `setup.sh` to push the updated version to `~/Library/Services/`.

## Quick Actions Not Appearing

Known facts from prior debugging:
- `pbs -update` and `killall Finder` are not sufficient in all cases
- **A full system restart is the only reliable way** to get newly installed Quick Actions to appear
- After restart, if still missing: System Settings → Keyboard → Keyboard Shortcuts → Services → find under "Files and Folders" and ensure they are checked

## Updating markitdown

```bash
~/.markitdown-venv/bin/pip install --upgrade 'markitdown[all]'
```
