# /validate — Static validation of all project files

Run every static check on the codebase and report pass/fail. Use this before any commit and after editing any shell script, Python file, or plist.

## Checks to run

### Shell syntax
```bash
bash -n scripts/convert.sh
bash -n setup.sh
bash -n tests/run_tests.sh
```

### Python syntax
```bash
python3 -m py_compile scripts/llm_convert.py
```

### Plist validity — run on ALL workflow bundles
```bash
for wf in workflows/*.workflow; do
    plutil -lint "$wf/Contents/document.wflow"
    plutil -lint "$wf/Contents/Info.plist"
done
```

### Secrets scan — grep staged and unstaged changes
```bash
git diff HEAD | grep -En 'sk-[a-zA-Z0-9]{20,}|sk-ant-[a-zA-Z0-9]{20,}|AIza[0-9A-Za-z_-]{35}'
```
If any match is found, STOP and report it as a blocker — do not proceed.

### Doc hygiene — no template artifacts in committed docs
```bash
grep -rn 'TODO:\|TEMPLATE ONLY\|\.\.\.' docs/ AGENTS.md TASKS.md 2>/dev/null
```

## Report format

List each check with a clear PASS or FAIL line. On failure, include the exact error output and the file:line. Do not summarize failures — show the raw output so the fix is obvious.

Example:
```
PASS  bash -n scripts/convert.sh
PASS  bash -n setup.sh
FAIL  plutil -lint workflows/Convert to Markdown.workflow/Contents/Info.plist
      workflows/Convert to Markdown.workflow/Contents/Info.plist: Unexpected character b at line 12
```

If everything passes: `All checks passed — safe to proceed.`
