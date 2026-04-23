# /add-workflow — Scaffold a new Automator Quick Action

Create a new workflow bundle with correct plist structure, validate it, wire it into setup.sh, and document it. Do NOT install without passing `plutil -lint`.

## Arguments

`$ARGUMENTS` — name of the new workflow, e.g. `"Convert to Markdown (Batch)"`

## Process

### 1. Choose the right template

| Input type | Template to copy |
|---|---|
| Files (Finder) — Tier 1+2 | `workflows/Convert to Markdown.workflow` |
| Files (Finder) — Tier 3 LLM | `workflows/Convert to Markdown (AI).workflow` |
| URLs (Safari Services) | `workflows/Convert URL to Markdown.workflow` |

```bash
cp -r "workflows/<template>.workflow" "workflows/$ARGUMENTS.workflow"
```

### 2. Generate fresh UUIDs

Every workflow needs three unique UUIDs. Never reuse from another bundle.

```bash
python3 -c "import uuid; [print(str(uuid.uuid4()).upper()) for _ in range(3)]"
```

Replace in `document.wflow`:

- `UUID` — the action UUID
- `InputUUID` — connects to the input source
- `OutputUUID` — connects to the output

### 3. Edit `document.wflow`

Key fields to update:

- `COMMAND_STRING` — the shell command the workflow runs (use absolute path via `$SCRIPT` variable already in template)
- `NSMenuItem → default` — must match the workflow name exactly
- `serviceInputTypeIdentifier` — `com.apple.Automator.fileSystemObject` for files, `com.apple.Automator.url` for URLs
- `inputMethod` — `1` = args (use for files), `0` = stdin

### 4. Edit `Info.plist`

Key fields to update:

- `CFBundleIdentifier` — must be unique across all workflows, e.g. `com.markitdown-automator.convert-batch`
- `NSMenuItem → default` — must match `document.wflow` exactly
- `NSApplicationIdentifier` inside `NSServices`:
  - Finder workflows: `com.apple.finder` (lowercase f)
  - Safari workflows: `com.apple.Safari` (capital S)
- `NSSendFileTypes` — keep `public.item` for broad file acceptance

### 5. Validate both files — REQUIRED before proceeding

```bash
plutil -lint "workflows/$ARGUMENTS.workflow/Contents/document.wflow"
plutil -lint "workflows/$ARGUMENTS.workflow/Contents/Info.plist"
```

Fix any error before moving on. `setup.sh` will refuse to install an invalid bundle, but catch it here first.

### 6. Wire into setup.sh

Add the workflow name to the `for workflow in` loop (around line 264):

```bash
for workflow in \
    "Convert to Markdown.workflow" \
    "Convert URL to Markdown.workflow" \
    "Convert to Markdown (AI).workflow" \
    "$ARGUMENTS.workflow"; do   # ← add here
```

### 7. Install and verify

```bash
bash setup.sh
```

Confirm the workflow appears in `~/Library/Services/`.

Note: newly installed Quick Actions require a system restart to appear in Finder/Safari menus. `pbs -update` alone is not reliable.

### 8. Update documentation

**`docs/Architecture.md`** — add to File Layout:

```text
workflows/
  $ARGUMENTS.workflow    → description of what it does
```

**`AGENTS.md`** — add to File Layout section under workflows/.

**`TASKS.md`** — add Done entry: `Added workflow: $ARGUMENTS`

## Constraints

- Never reuse UUIDs from another workflow — generate fresh ones every time
- Always run `plutil -lint` before running `setup.sh`
- `CFBundleIdentifier` must be globally unique — check existing bundles before choosing
- Never edit workflow templates in `docs/templates/` — those are read-only references
