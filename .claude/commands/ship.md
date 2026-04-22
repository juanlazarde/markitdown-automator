# /ship — Pre-commit checklist

Run the full pre-commit checklist and propose a commit message. Do NOT propose a commit until every gate passes.

## Gates (in order — stop at first failure)

### Gate 1: Static validation
Run the same checks as `/validate`:
```bash
bash -n scripts/convert.sh && bash -n setup.sh && bash -n tests/run_tests.sh
python3 -m py_compile scripts/llm_convert.py
for wf in workflows/*.workflow; do
    plutil -lint "$wf/Contents/document.wflow"
    plutil -lint "$wf/Contents/Info.plist"
done
```
**Blocker:** any syntax error or invalid plist.

### Gate 2: Tests
```bash
bash tests/run_tests.sh --units
bash tests/run_tests.sh --tier1   # if convert.sh, setup.sh, or tests/ changed
bash tests/run_tests.sh           # full suite if anything in scripts/ changed
```
**Blocker:** any FAIL (skips are fine — they mean a dep isn't installed, not a regression).

### Gate 3: Secrets scan
```bash
git diff HEAD | grep -En 'sk-[a-zA-Z0-9]{20,}|sk-ant-[a-zA-Z0-9]{20,}'
```
**Blocker:** any match. API keys must live in macOS Keychain only — never in files.

### Gate 4: TASKS.md hygiene
- Did any backlog item complete this session? Move it to Done.
- Did any new work surface? Add it to Backlog.
- Keep In Progress empty if nothing is actively running.

### Gate 5: Docs
- Did `convert.sh` behavior change? → update `docs/Architecture.md` and the relevant feature doc
- Did a new workflow get added? → update file layout in `docs/Architecture.md` and `AGENTS.md`
- Did `setup.sh` install behavior change? → update the setup.sh Key Behaviors section in `AGENTS.md`
- Are all Mermaid diagrams in `docs/Architecture.md` still accurate?

## Commit message

Once all gates pass, propose a commit message:
- Imperative mood, ≤ 72 chars in subject
- Body: what changed and why (not just what)
- Do NOT include "Co-Authored-By" — that is added automatically by git commit

Format:
```
<subject line>

<body: what changed and why, wrapped at 72 chars>
```

Then wait for user approval before running `git commit`.
