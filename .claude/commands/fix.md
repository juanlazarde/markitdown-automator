# /fix — Autonomous bug-fix loop

Identify, test, fix, and verify a bug in markitdown-automator. Do NOT present code or stop until all relevant tests pass.

## Arguments

`$ARGUMENTS` — describe the bug, paste an error message, or name the failing test. If blank, scan for known issues (syntax errors, test failures, incorrect behavior).

## Process

### 1. Understand the bug
- Start from `docs/Architecture.md` if scope is unclear — identify the affected tier(s)
- Read the relevant source file(s): `scripts/convert.sh`, `setup.sh`, `scripts/llm_convert.py`, `scripts/vision_ocr.swift`
- Reproduce the failure: run `bash tests/run_tests.sh --units` first (no deps), then narrow to `--tier1` or `--tier2` as needed
- State the root cause before writing any code

### 2. Write a failing test first
- Add the test to `tests/run_tests.sh` in the appropriate section (`--units`, `--tier1`, or `--tier2`)
- Run it to confirm it fails with the expected failure (not a harness error)
- Remember: `!` cannot be passed through `"$@"` — use `assert_false` for negated assertions
- Never source `convert.sh` in `--units` tests — define functions inline

### 3. Implement the fix
- Smallest change that addresses the root cause — no collateral cleanup
- Follow AGENTS.md code style: `set -euo pipefail`, temp-first writes, no magic strings, `((n++)) || true` for arithmetic
- Validate immediately: `bash -n` for shell, `python3 -m py_compile` for Python, `plutil -lint` for any plist touched

### 4. Run tests in tier order
```bash
bash tests/run_tests.sh --units
bash tests/run_tests.sh --tier1   # if markitdown or file handling is involved
bash tests/run_tests.sh --tier2   # if vision_ocr is involved
bash tests/run_tests.sh           # full suite as final confirmation
```

### 5. If tests fail — loop
- Read the failure output carefully; diagnose before changing anything
- Fix the root cause (not the test) unless the test itself is wrong
- Never delete or weaken a test to make it pass
- Re-run the smallest relevant tier, not the full suite every iteration

### 6. Report (only when all tests pass)
- Root cause
- Files changed (with line numbers for key changes)
- Full test output (passed / failed / skipped counts)
