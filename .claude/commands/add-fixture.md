# /add-fixture — Add a new test fixture and wire up tests

Add a source file to the test suite, generate its expected output, and write the corresponding tests. All new tests must pass before you are done.

## Arguments

`$ARGUMENTS` — path to the source file to add (e.g., `/path/to/invoice.pdf`)

## Process

### 1. Copy to fixtures directory
```bash
cp "$ARGUMENTS" tests/test_files/
```
The fixture path in run_tests.sh is `FIXTURES="tests/test_files"` — always use this path.

### 2. Generate expected output
Run the conversion in a temp directory to avoid polluting the source:
```bash
tmp=$(mktemp -d /tmp/fixture-gen-XXXXXX)
cp "$ARGUMENTS" "$tmp/"
bash scripts/convert.sh "$tmp/<filename>" 2>/dev/null || true
cat "$tmp/<stem>.md"
```

Review the output:
- **Has meaningful content (≥ 50 non-ws chars):** save it as the expected output
  ```bash
  cp "$tmp/<stem>.md" tests/test_files/expected_outputs/
  ```
- **Blank or near-blank (image-only PDF, scan):** this is a Tier 2 candidate — do NOT save an expected output file; note it in TASKS.md as a Tier 2 test candidate
- **Minimal but non-zero (< 50 chars):** save the expected output anyway, but use a lower threshold in `tier1_test` — document why with a comment

### 3. Wire up tests in `tests/run_tests.sh`

**Always add** a `tier1_test` call in the "Tier 1: markitdown conversions" section:
```bash
tier1_test "Description → Markdown" "filename.ext"
# Use optional 3rd arg if fixture legitimately produces < 50 non-ws chars:
# tier1_test "Minimal EPUB → Markdown" "tiny.epub" 30
```

**If expected output exists and is non-empty**, also add a `compare_test` call in "Tier 1: content comparison against expected outputs":
```bash
compare_test "Description → key content preserved" "filename.ext"
```

### 4. Run tests to confirm
```bash
bash tests/run_tests.sh --tier1
```
All new tests must pass. If a test fails:
- Check the actual output matches what you saved as expected
- Adjust the threshold if the fixture is legitimately minimal (and document why)
- Never weaken the assertion to make it pass — if the output is wrong, the conversion is wrong

### 5. Update TASKS.md
Add a Done entry: `Added fixture: <filename> (Tier 1 content-comparison test)`

If the fixture is a Tier 2 candidate, add a Backlog entry in "Core pipeline".
