# markitdown-automator

macOS Automator Quick Actions that convert files and URLs to Markdown using Microsoft's [`markitdown`](https://github.com/microsoft/markitdown) — no terminal required.

Right-click any file in Finder, or open a URL in Safari, and get a clean `.md` file in seconds.

---

## What it converts

Anything `markitdown` supports, including:

| Type | Examples |
|------|---------|
| Documents | PDF, DOCX, PPTX, XLSX, EPUB |
| Web | HTML pages, RSS feeds |
| Media | Images (with alt-text), audio transcription |
| Data | CSV, JSON, XML |
| Code notebooks | Jupyter `.ipynb` |
| Video | YouTube URLs (transcript + metadata) |

---

## Requirements

- **macOS** (Automator Quick Actions are macOS-only)
- **Python 3.10+** — check with `python3 --version`; install via [Homebrew](https://brew.sh): `brew install python`
- Internet access for the first install (downloads `markitdown` from PyPI)

---

## Installation

```bash
git clone https://github.com/juanlazarde/markitdown-automator.git
cd markitdown-automator
bash setup.sh
```

Setup does the following automatically:
1. Creates an isolated Python venv at `~/.markitdown-venv`
2. Installs `markitdown[all]` into the venv
3. Copies `convert.sh` to `~/.markitdown-automator/scripts/`
4. Installs both Quick Actions into `~/Library/Services/`
5. Refreshes the macOS Services registry

**After setup, restart your Mac.** Quick Actions require a full restart to appear reliably in menus.

---

## Usage

### Convert files (Finder)

1. Select one or more files in Finder
2. Right-click → **Quick Actions** → **Convert to Markdown**
3. A `.md` file appears alongside each original file

Supports batch selection — convert an entire folder's worth of files in one shot.

### Convert URLs (Safari)

1. Navigate to any page in Safari
2. In the menu bar: **Safari** → **Services** → **Convert URL to Markdown**
3. A `.md` file is saved to `~/Downloads/`

Works with YouTube URLs too — `markitdown` extracts the transcript and video metadata.

> **Note:** The URL action appears under **Safari → Services**, not in the share sheet toolbar button. This is a macOS limitation — the share sheet only supports native App Extensions, not Automator Quick Actions.

### From the terminal

```bash
# Convert a file
bash scripts/convert.sh path/to/document.pdf

# Convert a URL
bash scripts/convert.sh https://example.com/article

# Convert multiple files at once
bash scripts/convert.sh report.docx slides.pptx notes.html
```

---

## Output locations

| Input | Output |
|-------|--------|
| `/path/to/file.pdf` | `/path/to/file.md` (alongside original) |
| `https://example.com/page` | `~/Downloads/example.com-page-20240101-120000-1.md` |

**Safe-write behaviour:**
- Conversion writes to a temp file first; the `.md` is only placed if conversion succeeds — a crash or error never corrupts an existing file
- If `output.md` already exists, it is renamed to `output.bak.md` before the new file is placed
- Multiple files that share a stem (e.g. `report.pdf` and `report.docx`) produce `report.md` and `report-2.md`

---

## Troubleshooting

### Quick Actions don't appear after install

1. **Restart your Mac** — this is required; `pbs -update` alone is not always sufficient
2. After restart, check: **System Settings → Keyboard → Keyboard Shortcuts → Services** and ensure both "Convert to Markdown" entries are checked

### Conversion failed notification

Check the log for details:

```bash
cat ~/Library/Logs/markitdown-automator.log
```

Common causes: file is password-protected, unsupported format, or a network error for URLs.

### markitdown not found

Re-run setup:

```bash
bash setup.sh
```

Or install manually into the venv:

```bash
~/.markitdown-venv/bin/pip install 'markitdown[all]'
```

### Safari Services menu item missing

After a restart it should appear under **Safari → Services**. If it still doesn't:
1. Open **System Settings → Keyboard → Keyboard Shortcuts → Services**
2. Scroll to find "Convert URL to Markdown" and enable it

---

## Updating markitdown

```bash
~/.markitdown-venv/bin/pip install --upgrade 'markitdown[all]'
```

To pin a specific version, edit `MARKITDOWN_PKG` near the top of `setup.sh` (e.g. `markitdown[all]==0.1.1`) and re-run `bash setup.sh`.

---

## Uninstall

```bash
bash setup.sh --uninstall
```

Removes the venv, installed scripts, and both Quick Actions from `~/Library/Services/`.

---

## How it works

```
Finder / Safari
      │
      ▼
  Quick Action (~/Library/Services/*.workflow)
      │  Automator shell bootstrap
      ▼
  ~/.markitdown-automator/scripts/convert.sh
      │  locates markitdown in venv, runs it
      ▼
  markitdown → .md output
      │
      ▼
  macOS notification (success or failure)
  ~/Library/Logs/markitdown-automator.log
```

The `.workflow` bundles are Automator plist XML — no compiled code, fully inspectable. `setup.sh` validates both plist files with `plutil -lint` before touching any live install, and uses atomic temp→rename installs so a failed update never leaves a broken Quick Action.

---

## Project structure

```
setup.sh                          one-time installer / uninstaller
scripts/
  convert.sh                      core conversion logic
workflows/
  Convert to Markdown.workflow    Finder Quick Action (files)
  Convert URL to Markdown.workflow  Safari Services Quick Action (URLs)
```

---

## License

MIT
