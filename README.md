# markitdown-automator

macOS Automator Quick Actions that convert files and URLs to Markdown using Microsoft's [`markitdown`](https://github.com/microsoft/markitdown), with optional local OCR and explicit AI conversion.

Right-click supported files in Finder, or open a URL in Safari, and get a `.md` file without using the terminal.

---

## What it converts

The standard action converts anything `markitdown` supports, including:

| Type | Examples |
|------|---------|
| Documents | PDF, DOCX, PPTX, XLSX, EPUB |
| Web | HTML pages, RSS feeds |
| Media | Images (with alt-text), audio transcription |
| Data | CSV, JSON, XML |
| Code notebooks | Jupyter `.ipynb` |
| Video | YouTube URLs (transcript + metadata) |

Image-only PDFs and images can also fall back to on-device Apple Vision OCR. The separate AI action can convert PDFs and images with OpenAI or Anthropic when you explicitly choose it.

---

## Requirements

- **macOS** (Automator Quick Actions are macOS-only)
- **Python 3.10+** — setup checks this and can install Python through Homebrew if needed
- Internet access for the first install (downloads `markitdown` from PyPI)
- **Xcode Command Line Tools** for local OCR compilation — setup checks this and can open Apple's installer if needed

If Homebrew is missing and Python 3.10+ is not available, setup can install Homebrew first, then install Python. Homebrew or Apple's Xcode tools installer may ask for your administrator password. The script explains the command and reason before that happens; password entry is handled by macOS/sudo and is never read, stored, logged, or forwarded by this project.

Local OCR requires macOS 11+ and Xcode Command Line Tools. If Swift compilation fails or you skip the tools install, setup still installs Tier 1 and Tier 3, but automatic Vision OCR is unavailable until the toolchain issue is fixed.

---

## Installation

```bash
git clone https://github.com/juanlazarde/markitdown-automator.git
cd markitdown-automator
bash setup.sh
```

To preview what setup does without making changes:

```bash
bash setup.sh --help
```

Setup does the following automatically:
1. Checks required macOS tools.
2. Checks Python 3.10+; if missing or too old, offers to install Homebrew and Python with clear admin-password disclosure.
3. Creates an isolated Python venv at `~/.markitdown-venv`.
4. Installs `markitdown[all]` into the venv.
5. Copies `convert.sh` and `llm_convert.py` to `~/.markitdown-automator/scripts/`.
6. Checks Xcode Command Line Tools and offers to open Apple's installer if local OCR cannot compile.
7. Compiles `vision_ocr.swift` when the Xcode toolchain is available.
8. Installs three Quick Actions into `~/Library/Services/`.
9. Refreshes the macOS Services registry.

If you configure AI keys during setup, it also installs the full Tier 3 package set: `pymupdf`, `Pillow`, and the selected provider SDKs.

**After setup, restart your Mac.** Quick Actions require a full restart to appear reliably in menus.

---

## Usage

### Convert files (Finder)

1. Select one or more files in Finder
2. Right-click → **Quick Actions** → **Convert to Markdown**
3. A `.md` file appears alongside each original file

Supports batch selection. Select the files inside a folder, not the folder itself.

If Tier 1 produces blank or near-blank output for a supported PDF/image, the action automatically tries local Apple Vision OCR before placing the `.md`.

### Convert files with AI (Finder)

1. Configure keys with `bash setup.sh --configure-keys`
2. Select one or more PDFs or images in Finder
3. Right-click → **Quick Actions** → **Convert to Markdown (AI)**

The AI action is never automatic. It is a separate action for paid/slow conversion and writes output only after the API conversion succeeds. URL inputs always use the standard Tier 1 path, even if `--llm` is present.

### Convert URLs (Safari)

1. Navigate to any page in Safari
2. In the menu bar: **Safari** → **Services** → **Convert URL to Markdown**
3. A `.md` file is saved to `~/Downloads/`

Works with YouTube URLs too — `markitdown` extracts the transcript and video metadata.

> **Note:** The URL action appears under **Safari → Services**, in the Text and Internet Services categories. It does not appear in the share sheet toolbar button. This is a macOS limitation — the share sheet only supports native App Extensions, not Automator Quick Actions.

### From the terminal

```bash
# Convert a file
bash scripts/convert.sh path/to/document.pdf

# Convert a URL
bash scripts/convert.sh https://example.com/article

# Convert a file with the explicit AI path
bash scripts/convert.sh --llm auto path/to/scanned.pdf

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
- File conversion writes to a temp file first, then moves the temp file into place
- If `output.md` already exists, it is renamed to `output.bak.md` before the new file is placed
- Multiple files that share a stem (e.g. `report.pdf` and `report.docx`) produce `report.md` and `report-2.md`
- Tier 3 failure never modifies an existing `.md`; Tier 2 OCR failure is soft and may place the blank Tier 1 output with a warning in the log

---

## Troubleshooting

### Quick Actions don't appear after install

1. **Restart your Mac** — this is required; `pbs -update` alone is not always sufficient
2. After restart, check: **System Settings → Keyboard → Keyboard Shortcuts → Services** and ensure the MarkItDown entries are checked

### Conversion failed notification

Check the log for details:

```bash
cat ~/Library/Logs/markitdown-automator.log
```

Common causes: file is password-protected, unsupported format, missing API key for AI conversion, or a network error for URLs.

### OCR did not run

Check that the compiled binary exists:

```bash
ls -l ~/.markitdown-automator/scripts/vision_ocr
```

If it is missing, install Xcode Command Line Tools and rerun setup:

```bash
xcode-select --install
bash setup.sh
```

### Python or Homebrew is missing

Run setup normally:

```bash
bash setup.sh
```

If Python 3.10+ is not available, setup will offer to install Homebrew if needed, then Python. It will explain any command that may request an administrator password before running it.

### AI conversion says no API key is configured

Run:

```bash
bash setup.sh --configure-keys
```

Keys are stored in macOS Keychain, not in repo files or shell profiles.

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

Removes project-owned files:

- `~/.markitdown-venv/`
- `~/.markitdown-automator/`
- the three Quick Actions from `~/Library/Services/`
- `~/Library/Logs/markitdown-automator.log`

The uninstaller asks before removing API keys from Keychain.

Homebrew, Homebrew-installed Python, and Xcode Command Line Tools are shared system dependencies. They are kept by default. If Homebrew or Homebrew Python are present, uninstall asks separately whether to remove them; press ENTER to keep them. Xcode Command Line Tools are not removed by this script.

For all setup modes and dependency details:

```bash
bash setup.sh --help
```

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
      │  runs markitdown, Vision OCR, or explicit AI conversion
      ▼
  temp file → .md output
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
  vision_ocr.swift                Apple Vision OCR source
  llm_convert.py                  explicit AI conversion helper
workflows/
  Convert to Markdown.workflow      Finder Quick Action (files, Tier 1+2)
  Convert URL to Markdown.workflow  Safari Services Quick Action (URLs, Tier 1; Text + Internet categories)
  Convert to Markdown (AI).workflow Finder Quick Action (files, Tier 3)
docs/
  Architecture.md                   primary architecture reference
  Features/                         behavior specs and implementation plans
tests/
  run_tests.sh                      shell test suite
```

---

## License

MIT
