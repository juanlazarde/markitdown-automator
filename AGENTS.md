# AGENTS.md

Project: markitdown-automator  
Stack: Bash / Swift / Python / macOS Automator plist XML  

---

## Conversations (Self-Learning)

Learn the user's habits, preferences, and working style. Extract rules from conversations, save to "## Rules to follow", and generate code according to the user's personal rules.

**Update requirement (core mechanism):**

Before doing ANY task, evaluate the latest user message.  
If you detect a new rule, correction, preference, or change → update `AGENTS.md` first.  
Only after updating the file you may produce the task output.  
If no new rule is detected → do not update the file.

**When to extract rules:**

- prohibition words (never, don't, stop, avoid) or similar → add NEVER rule
- requirement words (always, must, make sure, should) or similar → add ALWAYS rule
- memory words (remember, keep in mind, note that) or similar → add rule
- process words (the process is, the workflow is, we do it like) or similar → add to workflow
- future words (from now on, going forward) or similar → add permanent rule

**Preferences → add to Preferences section:**

- positive (I like, I prefer, this is better) or similar → Likes
- negative (I don't like, I hate, this is bad) or similar → Dislikes
- comparison (prefer X over Y, use X instead of Y) or similar → preference rule

**Corrections → update or add rule:**

- error indication (this is wrong, incorrect, broken) or similar → fix and add rule
- repetition frustration (don't do this again, you ignored, you missed) or similar → emphatic rule
- manual fixes by user → extract what changed and why

**Strong signal (add IMMEDIATELY):**

- swearing, frustration, anger, sarcasm → critical rule
- ALL CAPS, excessive punctuation (!!!, ???) → high priority
- same mistake twice → permanent emphatic rule
- user undoes your changes → understand why, prevent

**Ignore (do NOT add):**

- temporary scope (only for now, just this time, for this task) or similar
- one-off exceptions
- context-specific instructions for current task only

**Rule format:**

- One instruction per bullet
- Tie to category (Testing, Code, Docs, etc.)
- Capture WHY, not just what
- Remove obsolete rules when superseded

---

## Rules to follow (Mandatory, no exceptions)

### Environment

- This is a macOS environment.
- Use macOS-compatible commands (e.g., `mktemp -t prefix` not `mktemp prefix.XXXXXX`, `open` not `xdg-open`).
- Be aware of Xcode toolchain, codesigning, and Apple framework constraints.

### Commands

- build: `bash setup.sh`
- build (keys only): `bash setup.sh --configure-keys`
- build (uninstall): `bash setup.sh --uninstall`
- test: `bash tests/run_tests.sh`
- test (units only, no deps): `bash tests/run_tests.sh --units`
- test (tier 1 only): `bash tests/run_tests.sh --tier1`
- test (tier 2 only): `bash tests/run_tests.sh --tier2`
- validate plist: `plutil -lint <path/to/file.wflow|Info.plist>`

No format or coverage commands — not applicable to this shell/Swift/Python project.

### Skills (slash commands)

Project skills live in `.claude/commands/`. Invoke with `/skill-name`.

| Skill | When to use |
| --- | --- |
| `/fix` | Bug reported or test failing — autonomous write-test → fix → verify loop |
| `/validate` | Before any commit — runs bash -n, py_compile, plutil-lint, secrets scan |
| `/add-fixture <path>` | Adding a new test file — copies fixture, generates expected output, wires up tests |
| `/ship` | Ready to commit — full checklist: validate + test + secrets + docs + commit message |
| `/add-workflow <name>` | Creating a new Automator Quick Action — scaffold, UUID generation, setup.sh wiring |

### Task Delivery (ALL TASKS)

- Always start from the architecture map in `docs/Architecture.md`:
  - confirm any Mermaid diagrams exist and are up to date (if missing/outdated → update first)
  - identify the impacted tier(s) and entry points (Tier 1: `convert.sh` + `markitdown`; Tier 2: `vision_ocr.swift`; Tier 3: `llm_convert.py`)
  - follow links to relevant feature docs or ADRs (do not read everything)
- Scope first (prevent context overload):
  - write **in scope / out of scope** (what will change and what must not change)
  - if you cannot identify scope from `docs/Architecture.md` → stop and fix the doc, or ask one clarifying question
- Analyze first (no coding yet):
  - what exists today (facts only)
  - what must change / must not change
  - unknowns and risks
- Create a written plan before implementation:
  - for architecture/decision work: keep the plan in the relevant ADR under `docs/ADR/`
  - for behavior work: keep the plan in the relevant feature doc under `docs/Features/`
  - update the plan while executing (tick items as work completes)
- Implement code and tests together
- Run `bash setup.sh` before `bash tests/run_tests.sh` when the binary or install is involved
- Verification timing:
  - do not run tests "just because" before you wrote/changed code (exception: reproducing a bug)
  - while iterating, run the smallest meaningful scope first (`--units` → `--tier1` → `--tier2`)
  - run the full suite only when you have something real to verify
- After tests pass: summarize changes and results before marking complete
- Run tests yourself — do not ask the user to execute them

### Documentation (ALL TASKS)

- All docs live in `docs/`
- `docs/Architecture.md` is the primary architecture reference — read it first, keep it current
- `docs/templates/` holds templates (AGENTS, CLAUDE, Feature, ADR, Architecture) — use them, do not edit them
- Future feature docs → `docs/Features/`; future decisions → `docs/ADR/`
- `TASKS.md` is the backlog — update it when work is done or new work is identified
- Single source of truth (no duplication):
  - each important fact lives in exactly one canonical place; other docs link, not copy
  - `docs/Architecture.md` is navigational; detailed behavior belongs in `docs/Features/`; decisions in `docs/ADR/`
- When creating docs from templates: copy to real location, replace all placeholders, remove all template notes — committed docs must be clean (no `TEMPLATE ONLY`, `TODO:`, `...`)
- Update feature docs when behavior changes; update ADRs when architecture changes
- Diagrams are mandatory in feature and ADR docs — use Mermaid; prefer `flowchart` / `sequenceDiagram`; ensure they render

### Testing (ALL TASKS)

- Tests run against real fixture files in `tests/test_files/` — no mocking (this IS the system; there is nothing to mock)
- Expected outputs live in `tests/test_files/expected_outputs/` — use `assert_contains_key_lines` for fuzzy content comparison against them (not exact diff; markitdown output varies by version)
- Layer order: `--units` (always safe, no deps) → `--tier1` (needs markitdown) → `--tier2` (needs vision_ocr binary)
- `tests/run_tests.sh --units` can always run without any install — it tests pure shell logic
- Every behavior change needs at least one test that exercises a real file through the affected code path
- Never delete or weaken a test to make it pass; never lower a threshold just to make a test pass — lower thresholds are only valid when a fixture legitimately produces minimal output (document why with a comment)
- Each test verifies a real flow (real file in, real output checked) — tests without meaningful assertions are forbidden
- Flaky tests are failures: fix the test or the underlying behavior
- Shell test harness patterns (avoid known pitfalls):
  - `!` is a shell keyword — it cannot be passed through `"$@"`; use the `assert_false` helper instead of `assert "..." ! some_fn`
  - Never source `convert.sh` to extract a function for unit testing — the script exits non-zero when markitdown is not installed; define functions inline in the test file
  - `assert_has_content` accepts an optional 3rd arg (min non-whitespace char threshold, default 50); `tier1_test` accepts an optional 3rd arg that forwards to it

### Autonomy

- Start work immediately — no permission seeking
- Questions only for architecture blockers not covered by existing docs
- Report only when task is complete
- When asked to create files or scaffold a repo, proceed directly without asking clarifying questions unless truly ambiguous. Prefer action over confirmation.

### Advisor stance (ALL TASKS)

- Stop being agreeable: be direct and honest; no flattery, no validation, no sugar-coating
- Challenge weak reasoning; point out missing assumptions and trade-offs
- If something is underspecified, contradictory, or risky — say so and list what must be clarified
- Never guess or invent. If unsure, say "I don't know" and propose how to verify
- Quality and security first: tests are gates; treat security regressions as blockers

### Git Conventions

- git operations never overwrite existing config files (.gitignore, .gitattributes) without checking first.
- Use --no-clobber or diff before rsync/cp operations.

### Code Quality

- Always validate scripts and shell commands before presenting them.
- Check for:
  - missing files (e.g., Info.plist),
  - unsafe operations (mv without backup),
  - proper escaping (XML, AppleScript),
  - correct platform-specific syntax (e.g., mktemp on macOS requires template pattern).
- When adding or modifying LLM provider support in `setup.sh → _configure_keys_interactive()`: always install the full dependency set — `pymupdf` + `Pillow` (for GIF/TIFF/BMP/HEIC→PNG in llm_convert.py) + the provider SDK (`openai` or `anthropic`). Missing any one causes an ImportError at conversion time that is hard to diagnose.

### Code Style

**Bash:**

- `set -euo pipefail` at the top of every script — no exceptions
- `((n++)) || true` for arithmetic that might legitimately reach zero (prevents pipefail)
- No magic strings or numbers — extract to named variables
- Temp-first writes always: `mktemp` → process → `mv` on success only
- Signal handling in any script that creates temp files: `trap cleanup EXIT`, `trap 'exit 130' INT`, `trap 'exit 143' TERM`

**Swift:**

- Standard library + system frameworks only (Vision, PDFKit, AppKit) — no external packages
- `VNImageRequestHandler.perform()` is synchronous — completion handler runs before `perform()` returns; no DispatchSemaphore needed
- Use `fputs(..., stderr)` for errors; `print(...)` for stdout output

**Python:**

- stdlib + venv packages only (`pymupdf`, `anthropic`, `openai`, `Pillow`)
- Exit codes: 0 = success, 1 = runtime error (API failure, bad input), 2 = missing dependency
- Atomic output writes: write to `output + ".llm-tmp"` then `os.replace(tmp, output)`

### Critical (NEVER violate)

- Never commit API keys, secrets, or credentials — OpenAI and Anthropic keys live in macOS Keychain only
- Never install a workflow bundle without running `plutil -lint` on both `document.wflow` and `Info.plist` first — `setup.sh` will refuse, but do not bypass this check
- Never write conversion output directly to the destination file — always temp-first (`mktemp` → success → `mv`); a failed conversion must never corrupt or blank an existing `.md` file
- Never remove signal handling (`trap cleanup EXIT`, `trap 'exit 130' INT`, `trap 'exit 143' TERM`) from `convert.sh` — temp files must always be cleaned up
- Never mock internal systems in tests — run against real fixture files
- Never skip tests to make a task appear complete
- Never force push to main
- Never approve or merge (human decision)

### Boundaries

**Always:**

- Read `AGENTS.md` and `docs/Architecture.md` before editing code
- Run `plutil -lint` after any plist edit, before anything else
- Run `bash tests/run_tests.sh` (or the relevant `--tier` subset) after any change to `convert.sh`, `vision_ocr.swift`, or `llm_convert.py`
- Update `TASKS.md` when completing backlog items or identifying new work

**Ask first:**

- Adding new Python packages to the venv — changes what `setup.sh` installs for all users
- Changing the blank-detection threshold (currently 50 non-whitespace chars) — affects which files trigger Tier 2 for every user
- Changing workflow bundle UUIDs or `NSServices` structure — affects macOS Services registration
- Changing Keychain service names (`markitdown-openai`, `markitdown-anthropic`) — silently breaks existing stored keys for all users
- Deleting any file in `tests/test_files/` or `tests/test_files/expected_outputs/`

---

## Project Reference

### Three-Tier Conversion Pipeline

Every file goes through up to three tiers. Stops when a tier produces content (≥ 50 non-whitespace chars).

| Tier | Trigger | Method | Failure mode |
| --- | --- | --- | --- |
| 1 | Always | `markitdown "$input" -o "$tmp"` | Hard — counted as failure |
| 2 | Auto — Tier 1 output blank | `vision_ocr "$input" > "$tmp"` | Soft — blank `.md` placed, warning logged |
| 3 | Explicit `--llm` flag | `python llm_convert.py --provider ...` | Hard — no output placed, user notified |

**Supported file types for Tiers 2 & 3:** PDF (all pages), JPEG, PNG, GIF (first frame), TIFF, HEIC, WebP, BMP

**Tier 3 is never automatic.** It is triggered only by the "Convert to Markdown (AI)" Quick Action or the `--llm` flag. URL inputs only use Tier 1.

### File Layout

```bash
setup.sh                              → installer / uninstaller / --configure-keys
scripts/
  convert.sh                          → core conversion logic (three-tier pipeline)
  vision_ocr.swift                    → Swift source → compiled to binary by setup.sh
  llm_convert.py                      → LLM vision converter (OpenAI + Anthropic)
workflows/
  Convert to Markdown.workflow        → Finder Quick Action (files, Tier 1+2)
  Convert URL to Markdown.workflow    → Safari Services Quick Action (URLs, Tier 1 only)
  Convert to Markdown (AI).workflow   → Finder Quick Action (files, Tier 3 explicit)
docs/
  Architecture.md                     → primary architecture reference
  templates/                          → templates (do not edit)
tests/
  run_tests.sh                        → test suite
  test_files/                         → fixture files for tests
    expected_outputs/                 → expected .md outputs for fixture files
TASKS.md                              → backlog
```

### Runtime Install Locations (created by setup.sh)

```bash
~/.markitdown-venv/                   → Python venv (markitdown[all], pymupdf, anthropic)
~/.markitdown-automator/
  scripts/convert.sh                  → installed copy (what workflows call)
  scripts/vision_ocr                  → compiled Swift binary (Tier 2)
  scripts/llm_convert.py              → installed copy (Tier 3)
  config                              → PREFERRED_LLM_PROVIDER=openai|anthropic (optional)
~/Library/Services/*.workflow         → installed Quick Actions
~/Library/Logs/markitdown-automator.log
```

### convert.sh Key Behaviors

- **`--llm` flag**: `convert.sh --llm [auto|openai|anthropic] file ...` — must precede file args; triggers Tier 3 and skips blank-detection
- **Blank detection**: after Tier 1, checks for < 50 non-whitespace chars → triggers Tier 2 automatically
- **Temp-first writes**: converts to `mktemp`, moves into place only on success
- **Backup on overwrite**: existing `output.md` → `output.bak.md` (then `.bak1.md`, etc.)
- **In-run collision tracking**: two inputs with the same stem get `report.md` and `report-2.md`
- **Signal handling**: `trap cleanup EXIT` + `trap 'exit 130' INT` + `trap 'exit 143' TERM`
- **Tier 3 failure = hard**: no output placed, counted as failure, user notified via AppleScript
- **Tier 2 failure = soft**: blank `.md` placed, WARN logged — same as pre-OCR behaviour

### setup.sh Key Behaviors

- Validates existing venv meets Python 3.10+; recreates if broken or outdated
- Compiles `vision_ocr.swift` → `~/.markitdown-automator/scripts/vision_ocr` (macOS 11+ only; non-fatal if swiftc fails)
- Workflow install is atomic: copy → temp sibling, move old → backup, move new → live, delete backup; restores previous install if any step fails
- `plutil -lint` validates both `document.wflow` and `Info.plist` before touching the live install — will `exit 1` on invalid plist
- `--configure-keys`: prompts for OpenAI/Anthropic keys (silent `read -rs`), stores in Keychain, installs `pymupdf`/`anthropic` packages, writes `PREFERRED_LLM_PROVIDER` to config
- `--uninstall`: prompts before removing Keychain entries
- To pin markitdown version: change `MARKITDOWN_PKG` in `setup.sh` (line ~102), e.g. `markitdown[all]==0.1.1`

### API Key Management

Keys are stored in **macOS Keychain**, never in files on disk.

| Provider | Keychain service name | Account |
| --- | --- | --- |
| OpenAI | `markitdown-openai` | `api-key` |
| Anthropic | `markitdown-anthropic` | `api-key` |

Configure: `bash setup.sh --configure-keys`  
Retrieve: `security find-generic-password -s markitdown-openai -a api-key -w`  
Preferred provider (when both set): `~/.markitdown-automator/config` → `PREFERRED_LLM_PROVIDER=openai|anthropic`

### Workflow Bundle Format

`*.workflow` bundles are plist XML. Key files: `Contents/document.wflow` and `Contents/Info.plist`.

- `workflowTypeIdentifier: com.apple.Automator.servicesMenu` — makes it a Quick Action
- `serviceInputTypeIdentifier: com.apple.Automator.fileSystemObject` — accepts files (Finder)
- `serviceInputTypeIdentifier: com.apple.Automator.url` — accepts URLs (Safari Services)
- `inputMethod: 1` in `ActionParameters` — files passed as shell arguments; `0` = via stdin
- `Contents/Info.plist` must declare `NSServices` — without it macOS silently ignores the workflow
- `serviceApplicationBundleID: com.apple.Safari` (capital S) for Safari; `com.apple.finder` (lowercase f) for Finder
- Always run `plutil -lint` after editing any plist; `setup.sh` will refuse to install an invalid bundle
- After editing a workflow bundle, re-run `setup.sh` to push it to `~/Library/Services/`

### macOS Constraints

**Quick Actions not appearing:**

- `pbs -update` and `killall Finder` are not sufficient in all cases
- A full system restart is the only reliable way to get newly installed Quick Actions to appear
- After restart, if still missing: System Settings → Keyboard → Keyboard Shortcuts → Services → enable under "Files and Folders"

**Safari share sheet vs Services menu:**

- The share sheet toolbar button exclusively uses `com.apple.share-services` App Extensions — Automator Quick Actions do NOT appear there
- The URL workflow appears only in Safari menu bar → Services → Convert URL to Markdown
- Share sheet support would require a native Share Extension (Xcode) or Shortcuts automation — see TASKS.md backlog

---

## Preferences

### Likes

- Local/private solutions before cloud: Tier 2 (on-device Vision OCR) always runs before Tier 3 (LLM API)
- Explicit user intent for paid/slow operations: Tier 3 LLM is a separate Quick Action, never automatic
- macOS-native patterns: Keychain for secrets, AppleScript argv for notifications (injection-safe), Services menu for integration
- Atomic operations everywhere: temp-first file writes, atomic workflow installs, Keychain not config files
- Three-tier architecture where each tier is independently testable and the user controls escalation

### Dislikes

- Storing API keys in files on disk — Keychain always
- Auto-triggering LLM or paid operations without explicit user action
- Mocking when real fixture files can be used instead
