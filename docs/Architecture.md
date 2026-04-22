# Architecture

## Overview

markitdown-automator is a macOS shell-script tool that wraps Microsoft's `markitdown` Python CLI as native Automator Quick Actions. No build step; no test framework beyond the shell.

---

## Three-Tier Conversion Pipeline

Every file conversion goes through up to three tiers, stopping as soon as a tier produces substantive output.

```text
User triggers Quick Action
        │
        ▼
  ┌─────────────┐
  │   Tier 1    │  markitdown "$input" -o "$tmp"
  │  (always)   │  Fast. Handles text PDFs, DOCX, EPUB, HTML, etc.
  └──────┬──────┘
         │
         ▼ output < 50 non-whitespace chars?
  ┌─────────────┐
  │   Tier 2    │  vision_ocr "$input" > "$tmp"       (auto, silent)
  │  (Vision)   │  Apple Vision OCR via VNRecognizeTextRequest.
  └──────┬──────┘  Handles: PDF (all pages), JPEG, PNG, GIF (frame 0),
         │         TIFF, HEIC, WebP, BMP. Local, private, no cost.
         │
  ┌─────────────┐
  │   Tier 3    │  python llm_convert.py --provider ... "$input" "$tmp"
  │   (LLM)     │  OpenAI gpt-4o or Anthropic claude-sonnet-4-6.
  └─────────────┘  Triggered only by "Convert to Markdown (AI)" Quick
                   Action (--llm flag) — never runs automatically.
```

**Tier 2 trigger condition:** `is_blank_output()` checks whether `$tmp` contains fewer than 50 non-whitespace characters after Tier 1 runs. This catches empty files, files with only `![]()`, and minimal EXIF metadata — without false-positiving on real content.

**Tier 3 failure semantics:** Hard failure — the file is counted as failed and no output is placed. Placing blank LLM output is worse than a notification.

**Tier 2 failure semantics:** Soft failure — a blank `.md` is placed (same as today's markitdown behavior pre-patch). A WARN is logged.

**URL inputs:** Only Tier 1 runs. URLs are text-based; Vision OCR and LLM vision don't apply.

---

## File Layout

```bash
setup.sh                          → installer / uninstaller / --configure-keys
scripts/
  convert.sh                      → core conversion logic (three-tier pipeline)
  vision_ocr.swift                → Swift source → compiled to binary by setup.sh
  llm_convert.py                  → Python LLM vision converter (OpenAI + Anthropic)
workflows/
  Convert to Markdown.workflow    → Finder Quick Action (files, Tier 1+2)
  Convert URL to Markdown.workflow → Safari Services Quick Action (URLs, Tier 1 only)
  Convert to Markdown (AI).workflow → Finder Quick Action (files, Tier 3 explicit)
docs/
  Architecture.md                 → this file
tests/
  run_tests.sh                    → test suite
  test_files/                     → fixture files for tests
    expected_outputs/             → expected .md outputs (used by content-comparison tests)
.claude/
  commands/                       → project slash commands (skills)
    fix.md                        → /fix  — autonomous bug-fix loop
    validate.md                   → /validate — static checks (bash -n, plutil, py_compile)
    add-fixture.md                → /add-fixture — add test fixture + wire up tests
    ship.md                       → /ship — pre-commit checklist
    add-workflow.md               → /add-workflow — scaffold Automator Quick Action
```

### Runtime install locations (created by setup.sh)

```bash
~/.markitdown-venv/               → Python venv with markitdown[all], pymupdf, anthropic
~/.markitdown-automator/
  scripts/
    convert.sh                    → installed copy (what workflows actually call)
    vision_ocr                    → compiled binary
    llm_convert.py                → installed copy
  config                          → PREFERRED_LLM_PROVIDER=openai|anthropic (optional)
~/Library/Services/
  Convert to Markdown.workflow
  Convert URL to Markdown.workflow
  Convert to Markdown (AI).workflow
~/Library/Logs/markitdown-automator.log
```

---

## Data Flow: File Conversion

```bash
Quick Action → Automator bootstrap (document.wflow COMMAND_STRING)
    → bash ~/.markitdown-automator/scripts/convert.sh [--llm auto] "$@"
        → for each input file:
            mktemp $dir/.markitdown-tmp-XXXXXX → $tmp
            markitdown "$input" -o "$tmp"
            if --llm: python llm_convert.py → overwrites $tmp
            elif blank: vision_ocr "$input" > $tmp
            backup existing output.md → output.bak.md (if needed)
            mv $tmp → output.md
        → osascript notification (success count / failure count)
```

## Data Flow: LLM Conversion (Tier 3)

```bash
llm_convert.py --provider openai|anthropic --api-key KEY input output
    ├─ PDF → pymupdf renders pages to PNG bytes at 150 DPI
    │        → vision API per page (PDF_PROMPT)
    │        → pages joined with "\n\n---\n\n"
    └─ Image → read bytes directly (GIF/TIFF/BMP/HEIC → PIL → PNG first)
               → vision API (IMAGE_PROMPT)
    → atomic write: output.llm-tmp → os.replace → output
```

---

## convert.sh Key Behaviors

| Behavior | Detail |
| ----------- | -------- |
| Temp-first writes | Converts to `mktemp` file; moves into place only on success |
| Backup on overwrite | Existing `output.md` → `output.bak.md` (then `.bak1.md`, etc.) |
| In-run collision tracking | Two inputs with same stem get `report.md` + `report-2.md` |
| Signal handling | `trap cleanup EXIT` + `trap 'exit 130' INT` + `trap 'exit 143' TERM` |
| Blank detection threshold | < 50 non-whitespace chars in Tier 1 output triggers Tier 2 |
| --llm flag | `--llm [auto\|openai\|anthropic]` — must precede file arguments |

---

## API Key Management

Keys are stored in **macOS Keychain**, never in files.

| Provider  | Keychain service name      | Account    |
|-----------|----------------------------|------------|
| OpenAI    | `markitdown-openai`        | `api-key`  |
| Anthropic | `markitdown-anthropic`     | `api-key`  |

Preferred provider when both are configured: `~/.markitdown-automator/config` → `PREFERRED_LLM_PROVIDER=openai|anthropic`

Configure: `bash setup.sh --configure-keys`
Retrieve (runtime): `security find-generic-password -s markitdown-openai -a api-key -w`

---

## Workflow Bundle Format

`*.workflow` bundles are plist XML. Key files: `Contents/document.wflow` and `Contents/Info.plist`.

- `workflowTypeIdentifier: com.apple.Automator.servicesMenu` — makes it a Quick Action
- `serviceInputTypeIdentifier: com.apple.Automator.fileSystemObject` — accepts files (Finder)
- `serviceInputTypeIdentifier: com.apple.Automator.url` — accepts URLs (Safari Services)
- `inputMethod: 1` — files passed as shell arguments; `0` = via stdin
- `Contents/Info.plist` must declare `NSServices` — without it macOS silently ignores it
- `serviceApplicationBundleID: com.apple.finder` (capital F) for Finder workflows
- `serviceApplicationBundleID: com.apple.Safari` (capital S) for Safari workflows

After editing a workflow bundle, re-run `setup.sh` to push it to `~/Library/Services/`.

---

## Vision OCR Binary (vision_ocr.swift)

Compiled from `scripts/vision_ocr.swift` during `setup.sh`. Requires macOS 11+.

- **PDFs:** `PDFKit.PDFDocument` → page thumbnail at 150 DPI → `VNRecognizeTextRequest`
  - Pages separated by `\n\n---\n\n` in output
  - Per-page failures emit `<!-- OCR failed for page N -->` inline; processing continues
- **Images:** `CGImageSourceCreateWithURL` → `CGImageSourceCreateImageAtIndex(source, 0)` → OCR
  - GIF: frame 0 only
- `VNImageRequestHandler.perform()` is synchronous — no DispatchSemaphore needed
- Exit 0 if any page succeeded; exit 1 if all failed

---

## Adding a New Format

To support a new input format in the pipeline:

1. **Tier 1** — markitdown handles it natively: nothing to do.
2. **Tier 2** — add the extension to the `switch` in `vision_ocr.swift`, recompile via `setup.sh`.
3. **Tier 3** — add the extension to `IMAGE_EXTS` in `llm_convert.py`; add PIL conversion logic if the format isn't natively supported by OpenAI/Anthropic APIs.
4. Update the supported types list in `CLAUDE.md` and this file.

---

## Known Constraints

- **Quick Actions require a system restart** to reliably appear after first install. `pbs -update` and `killall Finder` are insufficient in all cases.
- **Safari share sheet is not supported.** On macOS Ventura+, the share sheet toolbar button uses App Extensions only (`com.apple.share-services`). The URL workflow appears in Safari menu bar → Services only.
- **Vision OCR requires macOS 11+.** `setup.sh` skips compilation on older systems.
- **LLM Tier 3 caps at 50 pages** per PDF to bound cost. Large PDFs are truncated with a log warning.
