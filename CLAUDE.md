# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A macOS-only personal tool that wraps [Microsoft's `markitdown`](https://github.com/microsoft/markitdown) CLI with native Automator Quick Actions, eliminating the need to open a terminal. Converts files (PDF, DOCX, PPTX, images, HTML, etc.) and URLs (including YouTube) to Markdown.

## Running / Testing

```bash
# One-time install (creates venv, installs markitdown, registers Quick Actions)
bash setup.sh

# Test conversion directly from the terminal
bash scripts/convert.sh path/to/file.pdf
bash scripts/convert.sh https://www.youtube.com/watch?v=...

# Check logs if something goes wrong
cat ~/Library/Logs/markitdown-automator.log
```

No build step. No test suite. This is a shell script project.

## Architecture

```
setup.sh              → one-time installer
scripts/convert.sh    → core conversion logic (called by both Quick Actions)
workflows/
  Convert to Markdown.workflow          → Finder right-click Quick Action (files)
  Convert URL to Markdown.workflow      → Safari Share Sheet Quick Action (URLs)
```

**Runtime install locations** (created by `setup.sh`):
- `~/.markitdown-venv/` — isolated Python venv with `markitdown[all]`
- `~/.markitdown-automator/scripts/convert.sh` — copy of the script the workflows actually call
- `~/Library/Services/*.workflow` — installed Quick Actions

**Data flow:**
1. User triggers a Quick Action → Automator calls the embedded shell bootstrap in `document.wflow`
2. Bootstrap calls `~/.markitdown-automator/scripts/convert.sh` with file paths or URLs
3. `convert.sh` locates `markitdown` (venv first, then `$PATH`), runs it, writes `.md` output
4. macOS notification sent via `osascript`; errors appended to `~/Library/Logs/markitdown-automator.log`

**Output locations:**
- Files → `.md` saved alongside the original file (same directory, same stem)
- URLs → `~/Downloads/<url-slug>-<timestamp>.md`

## Workflow Bundle Format

`*.workflow` bundles are plist XML. The key file is `Contents/document.wflow`. When modifying workflows:
- `workflowTypeIdentifier: com.apple.Automator.servicesMenu` makes it a Quick Action
- `serviceInputTypeIdentifier: com.apple.Automator.fileSystemObject` = accepts files (Finder)
- `serviceInputTypeIdentifier: com.apple.Automator.url` = accepts URLs (Safari Share)
- `inputMethod: 1` in `ActionParameters` = files passed as shell arguments; `0` = via stdin

After editing a workflow bundle, re-run `setup.sh` to push the updated version to `~/Library/Services/`.

## Quick Actions Not Appearing

This has been a recurring issue. Known facts:
- The workflow bundle **requires `Contents/Info.plist`** with `NSServices` — without it macOS silently ignores the workflow.
- `pbs -update` and `killall Finder` are not sufficient to force recognition in all cases.
- **A full system restart is the only reliable way** to get newly installed Quick Actions to appear in Finder's right-click menu.
- After restart, if still missing: System Settings → Keyboard → Keyboard Shortcuts → Services → find under "Files and Folders" and ensure they are checked.

## Updating markitdown

```bash
~/.markitdown-venv/bin/pip install --upgrade 'markitdown[all]'
```
