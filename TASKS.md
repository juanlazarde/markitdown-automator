# Tasks

Backlog for markitdown-automator. Done items are removed when merged.

---

## In Progress

_Nothing currently in progress._

---

## Backlog

### Core pipeline
- [ ] **Test suite coverage for Tier 2** — Tier 2 tests exist and are wired to `MEDRPT-2024-PAT-3847_medical_report_scan.pdf`; they skip until `setup.sh` compiles vision_ocr. Run `bash setup.sh` then `bash tests/run_tests.sh --tier2` to verify.
- [ ] **Test suite coverage for Tier 3** — run against scan PDF with a real API key; verify output quality vs. Tier 2

### UX / workflow
- [ ] **Notification tier label** — after Tier 2 or 3, note which tier was used in the macOS notification (e.g., "Converted 1 item via Vision OCR")
- [ ] **Share sheet support** — Safari share sheet requires a native App Extension (Xcode). Shortcuts automation is an alternative. Currently only Services menu is supported.
- [ ] **Batch URL conversion** — Safari currently passes one URL at a time; explore multi-tab selection support

### AI / LLM
- [ ] **Model configuration** — allow user to override model (e.g., gpt-4o-mini for cost, claude-opus-4-6 for quality) via `~/.markitdown-automator/config`
- [ ] **Cost estimate notification** — after Tier 3, log estimated token cost to log file
- [ ] **Anthropic PDF native API** — Anthropic now supports PDFs natively via `"type": "document"` source. Explore replacing pymupdf page rendering with native PDF upload for Anthropic provider (simpler, potentially better quality)

### Maintenance
- [ ] **Pin markitdown version** — evaluate pinning `MARKITDOWN_PKG` once a stable release ships

---

## Done

- [x] Three-tier conversion pipeline (Tier 1 markitdown, Tier 2 Vision OCR, Tier 3 LLM)
- [x] Apple Vision OCR binary (`scripts/vision_ocr.swift`) — PDF multi-page + all image formats
- [x] LLM vision converter (`scripts/llm_convert.py`) — OpenAI gpt-4o + Anthropic claude-sonnet-4-6
- [x] "Convert to Markdown (AI)" Finder Quick Action
- [x] macOS Keychain API key management (`--configure-keys`)
- [x] Blank output detection (`is_blank_output()` — < 50 non-whitespace chars)
- [x] `setup.sh` compiles vision_ocr.swift, installs AI workflow, prompts for keys
- [x] Atomic workflow install (copy → temp, mv old → backup, mv new → live, delete backup)
- [x] Temp-first writes + backup on overwrite in convert.sh
- [x] In-run output collision tracking
- [x] Signal handling (EXIT, INT, TERM)
- [x] Safari Services menu URL workflow
- [x] AGENTS.md + CLAUDE.md (@./AGENTS.md) — single source of truth for Claude Code + Codex
- [x] PostToolUse hook — shellcheck on .sh, py_compile on .py after Write/Edit (`.claude/settings.local.json`)
- [x] Bug fix: `setup.sh` now installs `openai` + `Pillow` packages (were missing; caused ImportError in Tier 3)
- [x] Bug fix: `llm_convert.py` error messages now point to `bash setup.sh` (not `--configure-keys`)
- [x] Test suite overhaul: fixed `FIXTURES` path (`test_files` → `tests/test_files`), unblocking all Tier 1/2 tests
- [x] Test helpers: `assert_false`, `assert_has_content` (optional min threshold), `assert_contains_key_lines`
- [x] Content-comparison tests using `tests/test_files/expected_outputs/` for 5 PDFs
- [x] New unit tests: `unique_backup()` numbering, no-args guard, directory-skip, files with spaces, same-stem collision, multi-backup sequencing
- [x] Pre-existing bug fix: `assert "..." ! fn` pattern broken in shell (keyword vs command); replaced with `assert_false`
- [x] Pre-existing bug fix: "real content is not blank" test string was exactly 49 non-ws chars (1 below threshold)
- [x] Skills: `/fix`, `/validate`, `/add-fixture`, `/ship`, `/add-workflow` in `.claude/commands/`
