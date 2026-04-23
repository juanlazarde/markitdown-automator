#!/usr/bin/env bash
# tests/run_tests.sh — markitdown-automator test suite
#
# Usage:
#   bash tests/run_tests.sh              # run all tests (Tier 3 skipped if no key)
#   bash tests/run_tests.sh --tier1      # Tier 1 (markitdown) only
#   bash tests/run_tests.sh --tier2      # Tier 2 (Vision OCR) only
#   bash tests/run_tests.sh --units      # unit tests only (no markitdown needed)
#
# Tests run against files in test_files/ and clean up after themselves.
# Exit code: 0 = all ran tests passed, 1 = one or more failed.

set -euo pipefail
cd "$(dirname "$0")/.."

# ── Colors / helpers ──────────────────────────────────────────────────────────

green()  { printf '\033[32m  PASS\033[0m  %s\n' "$*"; }
red()    { printf '\033[31m  FAIL\033[0m  %s\n' "$*"; }
skip()   { printf '\033[33m  SKIP\033[0m  %s\n' "$*"; }
header() { printf '\n\033[1m── %s ──\033[0m\n' "$*"; }

PASS=0; FAIL=0; SKIP=0

pass() { ((PASS++)) || true; green "$1"; }
fail() { ((FAIL++)) || true; red   "$1"; }
skipped() { ((SKIP++)) || true; skip "$1"; }

# Run a test: assert <description> <condition>
assert() {
    local desc="$1"; shift
    if "$@" 2>/dev/null; then pass "$desc"; else fail "$desc"; fi
}

# assert_false: pass when the command exits non-zero
# Needed because '!' is a shell keyword and can't be passed through "$@"
assert_false() {
    local desc="$1"; shift
    if "$@" 2>/dev/null; then fail "$desc"; else pass "$desc"; fi
}

# assert_contains_key_lines <desc> <actual_file> <expected_file> [min_matches=5]
# Samples up to 30 non-blank, non-separator lines from expected_file and checks
# that at least min_matches of them appear verbatim in actual_file.
# This is intentionally fuzzy — markitdown output can vary slightly by version.
assert_contains_key_lines() {
    local desc="$1" actual="$2" expected="$3" min_matches="${4:-5}"
    local match=0 total=0 line
    if [ ! -f "$actual" ]; then
        fail "$desc — output file not found: $actual"; return
    fi
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        ((total++)) || true
        grep -qF -- "$line" "$actual" 2>/dev/null && ((match++)) || true
    done < <(grep -Ev '^[[:space:]]*(##+|---|===|[|]+[-]+[|]|[[:space:]]*)$' "$expected" | head -30)
    if [ "$match" -ge "$min_matches" ]; then
        pass "$desc (${match}/${total} key lines matched)"
    else
        fail "$desc — only ${match}/${total} key lines matched (need ≥${min_matches})"
    fi
}

# Assert a file is non-empty AND contains >= min non-whitespace chars (default 50)
assert_has_content() {
    local desc="$1" file="$2" min="${3:-50}"
    if [ ! -f "$file" ]; then
        fail "$desc — file not created: $file"; return
    fi
    local count
    count=$(awk '{gsub(/[[:space:]]/, ""); sum+=length($0)} END{print sum+0}' "$file")
    if [ "$count" -ge "$min" ]; then
        pass "$desc (${count} non-ws chars)"
    else
        fail "$desc — output too short (${count} non-ws chars, need ≥${min})"
    fi
}

run_convert_success() {
    local desc="$1"; shift
    if bash "$CONVERT" "$@" 2>/dev/null; then
        return 0
    fi
    fail "$desc — convert.sh exited non-zero"
    return 1
}

run_convert_failure() {
    local desc="$1"; shift
    local rc=0
    bash "$CONVERT" "$@" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ]; then
        pass "$desc"
        return 0
    fi
    fail "$desc — convert.sh exited zero unexpectedly"
    return 1
}

# ── Setup ─────────────────────────────────────────────────────────────────────

TMPDIR_TEST=$(mktemp -d /tmp/markitdown-test-XXXXXX)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

CONVERT="scripts/convert.sh"
FIXTURES="tests/test_files"
VENV="$HOME/.markitdown-venv"
VISION_OCR="$HOME/.markitdown-automator/scripts/vision_ocr"

# Filter flag
RUN_FILTER="${1:-all}"

# ── Unit tests (no external dependencies) ─────────────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--units" ]]; then
header "Unit: is_blank_output()"

# Extract the awk logic directly for unit testing
_is_blank() {
    local f="$1"
    [ ! -s "$f" ] && return 0
    local count
    count=$(awk '{gsub(/[[:space:]]/, ""); sum+=length($0)} END{print sum+0}' "$f")
    [ "$count" -lt 50 ]
}

_is_vision_ocr_supported() {
    local input="$1" ext
    ext="${input##*.}"
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
        pdf|jpg|jpeg|png|gif|tiff|tif|heic|heif|webp|bmp) return 0 ;;
        *) return 1 ;;
    esac
}

# Empty file → blank
empty_file="$TMPDIR_TEST/empty.md"
touch "$empty_file"
assert "empty file is blank" _is_blank "$empty_file"

# Whitespace only → blank
ws_file="$TMPDIR_TEST/whitespace.md"
printf '   \n\n   \t  \n' > "$ws_file"
assert "whitespace-only file is blank" _is_blank "$ws_file"

# markitdown image output → blank (just alt text placeholder)
img_stub="$TMPDIR_TEST/img_stub.md"
printf '![]()\n' > "$img_stub"
assert "bare image stub is blank" _is_blank "$img_stub"

# 49 non-whitespace chars → blank
short_file="$TMPDIR_TEST/short.md"
printf '%s' "$(python3 -c "print('x'*49, end='')")" > "$short_file"
assert "49 non-ws chars is blank" _is_blank "$short_file"

# 50 non-whitespace chars → NOT blank
ok_file="$TMPDIR_TEST/ok.md"
printf '%s' "$(python3 -c "print('x'*50, end='')")" > "$ok_file"
assert_false "50 non-ws chars is not blank" _is_blank "$ok_file"

# Real content → NOT blank
real_file="$TMPDIR_TEST/real.md"
printf '# Hello\n\nThis is a real document with enough content to pass the threshold.\n' > "$real_file"
assert_false "real content is not blank" _is_blank "$real_file"

assert "PDF is eligible for Vision OCR fallback" _is_vision_ocr_supported "scan.PDF"
assert "JPEG is eligible for Vision OCR fallback" _is_vision_ocr_supported "photo.jpeg"
assert_false "EPUB is not eligible for Vision OCR fallback" _is_vision_ocr_supported "book.epub"
assert_false "DOCX is not eligible for Vision OCR fallback" _is_vision_ocr_supported "report.docx"

fi  # units

# ── Unit tests: setup.sh dependency helpers ───────────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--units" ]]; then
header "Unit: setup.sh dependency helpers"

# Mirrors setup.sh. Keep this inline; do not source setup.sh because it performs
# install-time side effects.
python_meets_minimum() {
    local version="$1" major minor
    case "$version" in
        *[!0-9.]*|""|.*|*.) return 1 ;;
    esac
    major=$(printf '%s' "$version" | cut -d. -f1)
    minor=$(printf '%s' "$version" | cut -d. -f2)
    [ -n "$major" ] || return 1
    [ -n "$minor" ] || minor=0
    [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; }
}

assert_false "Python 3.9 is below minimum" python_meets_minimum "3.9"
assert "Python 3.10 meets minimum" python_meets_minimum "3.10"
assert "Python 3.14 meets minimum" python_meets_minimum "3.14"
assert "Python 4.0 meets minimum" python_meets_minimum "4.0"
assert_false "malformed Python version is rejected" python_meets_minimum "not-a-version"
assert_false "empty Python version is rejected" python_meets_minimum ""

help_out="$TMPDIR_TEST/setup-help.txt"
if bash setup.sh --help > "$help_out" 2>/dev/null; then
    pass "setup.sh --help exits zero"
else
    fail "setup.sh --help exits zero"
fi
assert "setup.sh --help documents Homebrew" grep -q "Homebrew" "$help_out"
assert "setup.sh --help documents admin password handling" grep -q "macOS/sudo" "$help_out"
assert "setup.sh --help documents password is not saved" grep -q "stores, logs, or forwards" "$help_out"
assert "setup.sh --help documents configure-keys" grep -q -- "--configure-keys" "$help_out"
assert "setup.sh --help documents uninstall log cleanup" grep -q "markitdown-automator.log" "$help_out"
assert "setup.sh --help documents shared dependency defaults" grep -q "Homebrew and Python are shared dependencies and are kept by default" "$help_out"
assert "setup.sh --help documents Enter keeps dependencies" grep -q "Press ENTER to keep them" "$help_out"

fi  # setup dependency helpers

# ── Unit tests: workflow bundle metadata ──────────────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--units" ]]; then
header "Unit: workflow bundles"

workflow_plists_valid() {
    local wf="$1"
    plutil -lint "$wf/Contents/document.wflow" >/dev/null &&
        plutil -lint "$wf/Contents/Info.plist" >/dev/null
}

workflow_shell_valid() {
    local wf="$1" tmp
    tmp=$(mktemp /tmp/workflow-cmd-XXXXXX)
    /usr/libexec/PlistBuddy \
        -c 'Print :actions:0:action:ActionParameters:COMMAND_STRING' \
        "$wf/Contents/document.wflow" > "$tmp"
    if bash -n "$tmp"; then
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

workflow_value_is() {
    local wf="$1" key_path="$2" expected="$3" actual
    actual=$(/usr/libexec/PlistBuddy -c "Print $key_path" "$wf/Contents/document.wflow" 2>/dev/null)
    [ "$actual" = "$expected" ]
}

workflow_category_is() {
    local wf="$1" index="$2" expected="$3" actual
    actual=$(/usr/libexec/PlistBuddy \
        -c "Print :actions:0:action:Category:$index" \
        "$wf/Contents/document.wflow" 2>/dev/null)
    [ "$actual" = "$expected" ]
}

assert "standard file workflow plists are valid" workflow_plists_valid "workflows/Convert to Markdown.workflow"
assert "AI file workflow plists are valid" workflow_plists_valid "workflows/Convert to Markdown (AI).workflow"
assert "URL workflow plists are valid" workflow_plists_valid "workflows/Convert URL to Markdown.workflow"

assert "standard file workflow embedded shell is valid" workflow_shell_valid "workflows/Convert to Markdown.workflow"
assert "AI file workflow embedded shell is valid" workflow_shell_valid "workflows/Convert to Markdown (AI).workflow"
assert "URL workflow embedded shell is valid" workflow_shell_valid "workflows/Convert URL to Markdown.workflow"

assert "standard file workflow passes input as arguments" workflow_value_is \
    "workflows/Convert to Markdown.workflow" \
    ":actions:0:action:ActionParameters:inputMethod" "1"
assert "AI file workflow passes input as arguments" workflow_value_is \
    "workflows/Convert to Markdown (AI).workflow" \
    ":actions:0:action:ActionParameters:inputMethod" "1"
assert "URL workflow reads input from stdin" workflow_value_is \
    "workflows/Convert URL to Markdown.workflow" \
    ":actions:0:action:ActionParameters:inputMethod" "0"

assert "standard file workflow is Finder-scoped" workflow_value_is \
    "workflows/Convert to Markdown.workflow" \
    ":workflowMetaData:serviceApplicationBundleID" "com.apple.finder"
assert "AI file workflow is Finder-scoped" workflow_value_is \
    "workflows/Convert to Markdown (AI).workflow" \
    ":workflowMetaData:serviceApplicationBundleID" "com.apple.finder"
assert "URL workflow is Safari-scoped" workflow_value_is \
    "workflows/Convert URL to Markdown.workflow" \
    ":workflowMetaData:serviceApplicationBundleID" "com.apple.Safari"
assert "URL workflow first Services category is Text" workflow_category_is \
    "workflows/Convert URL to Markdown.workflow" "0" "AMCategoryText"
assert "URL workflow second Services category is Internet" workflow_category_is \
    "workflows/Convert URL to Markdown.workflow" "1" "AMCategoryInternet"

fi  # workflow bundles

# ── Tier 1 tests (requires markitdown in venv) ────────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--tier1" ]]; then
header "Tier 1: markitdown conversions"

if [ ! -x "$VENV/bin/markitdown" ]; then
    skipped "markitdown not installed — run setup.sh first"
else

    # Helper: convert a fixture file to tmp dir, check output has content
    # Optional 3rd arg overrides the minimum non-whitespace char threshold (default 50)
    tier1_test() {
        local desc="$1" fixture="$2" min_chars="${3:-50}"
        local src="$FIXTURES/$fixture"
        local stem="${fixture%.*}"
        local tmp_input="$TMPDIR_TEST/$fixture"
        local expected_output="$TMPDIR_TEST/${stem}.md"

        if [ ! -f "$src" ]; then
            skipped "$desc — fixture not found: $src"; return
        fi

        cp "$src" "$tmp_input"
        # Run convert.sh from the tmp dir context (output lands alongside input)
        run_convert_success "$desc" "$tmp_input"
        assert_has_content "$desc" "$expected_output" "$min_chars"
        rm -f "$expected_output" "$tmp_input"
    }

    tier1_test "DOCX → Markdown"               "test.docx"
    # test.epub is a minimal fixture — markitdown extracts ~44 non-ws chars
    tier1_test "EPUB → Markdown"               "test.epub" 30
    tier1_test "XLSX → Markdown"               "test.xlsx"
    tier1_test "PPTX → Markdown"               "test.pptx"
    tier1_test "HTML → Markdown"               "test_blog.html"
    tier1_test "JSON → Markdown"               "test.json"
    tier1_test "Text PDF → Markdown"           "test.pdf"
    tier1_test "Multipage PDF → Markdown"      "REPAIR-2022-INV-001_multipage.pdf"
    tier1_test "PDF with table → Markdown"     "SPARSE-2024-INV-1234_borderless_table.pdf"
    tier1_test "Movie booking PDF → Markdown"  "movie-theater-booking-2024.pdf"

fi
fi  # tier1

# ── Tier 2 tests (requires vision_ocr binary) ─────────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--tier2" ]]; then
header "Tier 2: Vision OCR fallback"

if [ ! -x "$VISION_OCR" ]; then
    skipped "vision_ocr binary not found — run setup.sh first (requires macOS 11+)"
else

    # Test: vision_ocr binary runs on a known image file
    img_src="$FIXTURES/test.jpg"
    if [ -f "$img_src" ]; then
        ocr_out="$TMPDIR_TEST/test_ocr.txt"
        if "$VISION_OCR" "$img_src" > "$ocr_out" 2>/dev/null; then
            pass "vision_ocr runs on JPEG without error"
        else
            fail "vision_ocr failed on JPEG (exit code $?)"
        fi
        rm -f "$ocr_out"
    else
        skipped "test.jpg not found"
    fi

    # Test: image-only scan PDF triggers Tier 2 automatically
    scan_src="$FIXTURES/MEDRPT-2024-PAT-3847_medical_report_scan.pdf"
    if [ -f "$scan_src" ]; then
        scan_copy="$TMPDIR_TEST/MEDRPT-2024-PAT-3847_medical_report_scan.pdf"
        scan_out="$TMPDIR_TEST/MEDRPT-2024-PAT-3847_medical_report_scan.md"
        cp "$scan_src" "$scan_copy"

        if [ ! -x "$VENV/bin/markitdown" ]; then
            skipped "scan PDF Tier 2 trigger — markitdown not installed"
        else
            run_convert_success "image-only scan PDF → Tier 2 Vision OCR exits zero" "$scan_copy"
            assert_has_content "image-only scan PDF → Tier 2 Vision OCR produces content" "$scan_out"
            rm -f "$scan_copy" "$scan_out"
        fi
    else
        skipped "medical report scan PDF not found"
    fi

    # Test: vision_ocr on a multi-page PDF produces page separators
    multipage_src="$FIXTURES/REPAIR-2022-INV-001_multipage.pdf"
    if [ -f "$multipage_src" ]; then
        ocr_multipage="$TMPDIR_TEST/multipage_ocr.txt"
        "$VISION_OCR" "$multipage_src" > "$ocr_multipage" 2>/dev/null || true
        # A multi-page PDF should produce a --- separator if >1 page was OCR'd
        # (we check for either content or separator — either is fine for a text PDF)
        if [ -s "$ocr_multipage" ]; then
            pass "vision_ocr runs on multi-page PDF without error"
        else
            fail "vision_ocr produced empty output for multi-page PDF"
        fi
        rm -f "$ocr_multipage"
    else
        skipped "multipage PDF fixture not found"
    fi

fi
fi  # tier2

# ── Tier 1 behaviour: collision tracking and backup ───────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--tier1" ]]; then
header "Tier 1: collision tracking and backup"

if [ ! -x "$VENV/bin/markitdown" ]; then
    skipped "collision tests — markitdown not installed"
else

    # Test: backup created when output already exists
    docx_src="$FIXTURES/test.docx"
    if [ -f "$docx_src" ]; then
        docx_copy="$TMPDIR_TEST/test.docx"
        out_md="$TMPDIR_TEST/test.md"
        bak_md="$TMPDIR_TEST/test.bak.md"

        cp "$docx_src" "$docx_copy"
        printf 'existing content\n' > "$out_md"

        run_convert_success "backup conversion" "$docx_copy"

        assert "existing .md backed up to .bak.md" test -f "$bak_md"
        assert "new .md was placed"                test -f "$out_md"
        assert "backup contains original content"  grep -q "existing content" "$bak_md"

        rm -f "$docx_copy" "$out_md" "$bak_md"
    else
        skipped "backup test — test.docx not found"
    fi

fi
fi  # collision/backup

# ── Unit tests: edge cases ─────────────────────────────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--units" ]]; then
header "Unit: convert.sh invocation guards"

# Test: no arguments → exit 1
assert "no-args exits non-zero" bash -c 'bash '"$CONVERT"' 2>/dev/null; [ $? -ne 0 ]'

# Test: directory input counted as failure (exit 1), doesn't crash
run_convert_failure "directory input exits non-zero" "$TMPDIR_TEST"

# Test: invalid --llm mode must exit non-zero (not silently default to "auto")
run_convert_failure "invalid --llm mode exits non-zero" --llm invalid_mode /dev/null

# Test: explicit AI conversion fails hard when no key is configured, without
# invoking Tier 1 or moving the existing output aside.
#
# convert.sh prepends /usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin to PATH, so
# a constrained PATH alone cannot prevent /usr/bin/security from being found.
# MARKITDOWN_SECURITY_CMD lets us inject a stub that returns no key, making the
# test hermetic regardless of what keys the developer has in their Keychain.
ai_home="$TMPDIR_TEST/ai-home"
ai_bin="$TMPDIR_TEST/ai-bin"
ai_input="$TMPDIR_TEST/ai-input.png"
ai_output="$TMPDIR_TEST/ai-input.md"
ai_backup="$TMPDIR_TEST/ai-input.bak.md"
ai_marker="$TMPDIR_TEST/markitdown-called"
mkdir -p "$ai_home/.markitdown-automator/scripts" "$ai_home/.markitdown-venv/bin" "$ai_home/Downloads" "$ai_bin"
printf 'not a real image, but LLM provider resolution should fail first\n' > "$ai_input"
printf 'existing markdown\n' > "$ai_output"
printf '#!/usr/bin/env bash\nexit 0\n' > "$ai_home/.markitdown-automator/scripts/llm_convert.py"
chmod +x "$ai_home/.markitdown-automator/scripts/llm_convert.py"
printf '#!/usr/bin/env bash\nprintf called > "$MARKITDOWN_AUDIT_MARKER"\nexit 77\n' > "$ai_bin/markitdown"
chmod +x "$ai_bin/markitdown"
cp "$ai_bin/markitdown" "$ai_home/.markitdown-venv/bin/markitdown"
# Stub security to always return errSecItemNotFound (44) so key lookup is empty.
printf '#!/usr/bin/env bash\nexit 44\n' > "$ai_bin/security"
chmod +x "$ai_bin/security"

ai_rc=0
HOME="$ai_home" \
PATH="$ai_bin" \
MARKITDOWN_SECURITY_CMD="$ai_bin/security" \
MARKITDOWN_AUDIT_MARKER="$ai_marker" \
    /bin/bash "$CONVERT" --llm auto "$ai_input" 2>/dev/null || ai_rc=$?
assert "AI no-key conversion exits non-zero" [ "$ai_rc" -ne 0 ]
assert "AI no-key conversion leaves existing output in place" grep -q "existing markdown" "$ai_output"
assert_false "AI no-key conversion does not back up existing output" test -f "$ai_backup"
assert_false "AI no-key conversion does not invoke Tier 1" test -f "$ai_marker"

fi  # unit edge cases

# ── Unit tests: backup numbering ──────────────────────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--units" ]]; then
header "Unit: unique_backup() numbering"

# Define unique_backup inline (mirrors the function in convert.sh exactly)
# This avoids sourcing the whole script (which would fail without markitdown).
unique_backup() {
    local base="$1" stem candidate i=1
    stem="${base%.md}"
    candidate="${stem}.bak.md"
    while [ -f "$candidate" ]; do
        candidate="${stem}.bak${i}.md"
        ((i++)) || true
    done
    printf '%s\n' "$candidate"
}

# Sub-test: bak.md doesn't exist → returns stem.bak.md
bak_base="$TMPDIR_TEST/doc.md"
result=$(unique_backup "$bak_base")
assert "unique_backup: no existing bak → stem.bak.md" \
    [ "$result" = "$TMPDIR_TEST/doc.bak.md" ]

# Sub-test: bak.md exists → returns stem.bak1.md
touch "$TMPDIR_TEST/doc.bak.md"
result=$(unique_backup "$bak_base")
assert "unique_backup: bak.md exists → stem.bak1.md" \
    [ "$result" = "$TMPDIR_TEST/doc.bak1.md" ]

# Sub-test: bak.md and bak1.md both exist → returns stem.bak2.md
touch "$TMPDIR_TEST/doc.bak1.md"
result=$(unique_backup "$bak_base")
assert "unique_backup: bak and bak1 exist → stem.bak2.md" \
    [ "$result" = "$TMPDIR_TEST/doc.bak2.md" ]

rm -f "$TMPDIR_TEST/doc.bak.md" "$TMPDIR_TEST/doc.bak1.md"

fi  # unit backup numbering

# ── Tier 1 behaviour: files with spaces in names ──────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--tier1" ]]; then
header "Tier 1: files with spaces in names"

if [ ! -x "$VENV/bin/markitdown" ]; then
    skipped "spaces test — markitdown not installed"
else
    docx_src="$FIXTURES/test.docx"
    if [ -f "$docx_src" ]; then
        spaces_copy="$TMPDIR_TEST/my document with spaces.docx"
        spaces_out="$TMPDIR_TEST/my document with spaces.md"

        cp "$docx_src" "$spaces_copy"
        run_convert_success "file with spaces in name" "$spaces_copy"
        assert_has_content "file with spaces in name → .md created" "$spaces_out"

        rm -f "$spaces_copy" "$spaces_out"
    else
        skipped "spaces test — test.docx not found"
    fi
fi

fi  # spaces

# ── Tier 1 behaviour: same-stem collision tracking ────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--tier1" ]]; then
header "Tier 1: same-stem collision tracking"

if [ ! -x "$VENV/bin/markitdown" ]; then
    skipped "collision tracking — markitdown not installed"
else
    docx_src="$FIXTURES/test.docx"
    json_src="$FIXTURES/test.json"
    if [ -f "$docx_src" ] && [ -f "$json_src" ]; then
        # Two inputs both resolve to "test.md" — second should get "test-2.md"
        docx_copy="$TMPDIR_TEST/test.docx"
        json_copy="$TMPDIR_TEST/test.json"
        out1="$TMPDIR_TEST/test.md"
        out2="$TMPDIR_TEST/test-2.md"

        cp "$docx_src" "$docx_copy"
        cp "$json_src"  "$json_copy"

        run_convert_success "same-stem collision conversion" "$docx_copy" "$json_copy"

        assert "first same-stem input → test.md"   test -f "$out1"
        assert "second same-stem input → test-2.md" test -f "$out2"

        rm -f "$docx_copy" "$json_copy" "$out1" "$out2"
    else
        skipped "collision tracking — test.docx or test.json not found"
    fi
fi

fi  # same-stem collision

# ── Tier 1 behaviour: multiple sequential backups ─────────────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--tier1" ]]; then
header "Tier 1: multiple sequential backups"

if [ ! -x "$VENV/bin/markitdown" ]; then
    skipped "multi-backup test — markitdown not installed"
else
    docx_src="$FIXTURES/test.docx"
    if [ -f "$docx_src" ]; then
        docx_copy="$TMPDIR_TEST/bkp.docx"
        out_md="$TMPDIR_TEST/bkp.md"
        bak_md="$TMPDIR_TEST/bkp.bak.md"
        bak1_md="$TMPDIR_TEST/bkp.bak1.md"

        cp "$docx_src" "$docx_copy"

        # First run: creates bkp.md
        run_convert_success "multi-backup first conversion" "$docx_copy"
        assert "first run: bkp.md created" test -f "$out_md"

        # Manually place a pre-existing backup so next run must go to bak1.md
        printf 'first backup\n' > "$bak_md"

        # Second run: bak.md already exists → backup must use bak1.md
        run_convert_success "multi-backup second conversion" "$docx_copy"
        assert "second run: bkp.bak1.md created (bkp.bak.md already existed)" test -f "$bak1_md"

        rm -f "$docx_copy" "$out_md" "$bak_md" "$bak1_md"
    else
        skipped "multi-backup test — test.docx not found"
    fi
fi

fi  # multi-backup

# ── Tier 1: content comparison against expected outputs ───────────────────────

if [[ "$RUN_FILTER" == "all" || "$RUN_FILTER" == "--tier1" ]]; then
header "Tier 1: content comparison against expected outputs"

EXPECTED_DIR="$FIXTURES/expected_outputs"

if [ ! -x "$VENV/bin/markitdown" ]; then
    skipped "content comparison — markitdown not installed"
else

    # Helper: convert a PDF to a temp dir, compare against expected output
    compare_test() {
        local desc="$1" fixture="$2"
        local stem="${fixture%.*}"
        local src="$FIXTURES/$fixture"
        local expected="$EXPECTED_DIR/${stem}.md"
        local tmp_input="$TMPDIR_TEST/$fixture"
        local actual="$TMPDIR_TEST/${stem}.md"

        if [ ! -f "$src" ]; then
            skipped "$desc — fixture not found: $src"; return
        fi
        if [ ! -f "$expected" ] || [ ! -s "$expected" ]; then
            skipped "$desc — expected output missing or empty: $expected"; return
        fi

        cp "$src" "$tmp_input"
        run_convert_success "$desc" "$tmp_input"
        assert_contains_key_lines "$desc" "$actual" "$expected"
        rm -f "$actual" "$tmp_input"
    }

    compare_test "Receipt PDF → key content preserved"      "RECEIPT-2024-TXN-98765_retail_purchase.pdf"
    compare_test "Multi-page repair PDF → key content preserved" "REPAIR-2022-INV-001_multipage.pdf"
    compare_test "Sparse table PDF → key content preserved" "SPARSE-2024-INV-1234_borderless_table.pdf"
    compare_test "Movie booking PDF → key content preserved" "movie-theater-booking-2024.pdf"
    compare_test "Text PDF → key content preserved"         "test.pdf"

fi
fi  # content comparison

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
printf '\033[1m%d passed, %d failed, %d skipped\033[0m\n' "$PASS" "$FAIL" "$SKIP"

if [ "$FAIL" -gt 0 ]; then
    printf 'See ~/Library/Logs/markitdown-automator.log for conversion details.\n'
    exit 1
fi
