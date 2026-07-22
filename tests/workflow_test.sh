#!/usr/bin/env bash

set -u

TEST_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"
KICHO_ROOT="$(
    cd -- "$TEST_DIR/.." &&
    pwd
)"
KICHO="$KICHO_ROOT/bin/kicho"

failures=0
command_status=0
command_stdout=""
command_stderr=""

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

run_in() {
    local directory="$1"
    shift

    command_stdout="$test_root/stdout"
    command_stderr="$test_root/stderr"
    (
        cd -- "$directory" &&
        "$@"
    ) > "$command_stdout" 2> "$command_stderr"
    command_status=$?
}

assert_status() {
    local expected="$1"
    local description="$2"

    if [[ "$command_status" -ne "$expected" ]]; then
        fail "$description: expected status $expected, got $command_status"
    fi
}

assert_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        fail "file not found: $path"
    fi
}

assert_not_exists() {
    local path="$1"

    if [[ -e "$path" ]]; then
        fail "unexpected path: $path"
    fi
}

assert_contains() {
    local expected="$1"
    local path="$2"

    if ! grep -F -- "$expected" "$path" >/dev/null 2>&1; then
        fail "'$expected' not found in $path"
    fi
}

assert_not_contains() {
    local unexpected="$1"
    local path="$2"

    if grep -F -- "$unexpected" "$path" >/dev/null 2>&1; then
        fail "'$unexpected' unexpectedly found in $path"
    fi
}

assert_same() {
    local expected="$1"
    local actual="$2"
    local description="$3"

    if ! cmp -s "$expected" "$actual"; then
        fail "$description"
    fi
}

create_project_root() {
    local project="$1"

    mkdir -p "$project"
    printf 'latexmk configuration\n' > "$project/.latexmkrc"
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/kicho-workflow-test.XXXXXX")" || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

split_project="$test_root/Split Paper"
create_project_root "$split_project"
{
    printf 'before\n'
    printf '%% kicho:section introduction\n'
    printf 'Introduction text.\n'
    printf '%% kicho:end\n'
    printf 'between\n'
    printf '%% kicho:section main-results\n'
    printf 'Main result text.\n'
    printf '%% kicho:end\n'
    printf 'after\n'
} > "$split_project/main.tex"
cp "$split_project/main.tex" "$test_root/original-main.tex"

run_in "$split_project" "$KICHO" split
assert_status 0 'split valid markers'
assert_file "$split_project/main.tex.kicho-backup"
assert_file "$split_project/sections/introduction.tex"
assert_file "$split_project/sections/main-results.tex"
assert_same "$test_root/original-main.tex" "$split_project/main.tex.kicho-backup" 'split backup differs from original'
assert_contains '\input{sections/introduction}' "$split_project/main.tex"
assert_contains '\input{sections/main-results}' "$split_project/main.tex"
assert_contains 'Introduction text.' "$split_project/sections/introduction.tex"
assert_contains 'Main result text.' "$split_project/sections/main-results.tex"
assert_not_contains 'kicho:section' "$split_project/main.tex"
assert_not_contains 'Introduction text.' "$split_project/main.tex"

invalid_split="$test_root/InvalidSplit"
create_project_root "$invalid_split"
{
    printf 'before\n'
    printf '%% kicho:section open-section\n'
    printf 'never closed\n'
} > "$invalid_split/main.tex"
cp "$invalid_split/main.tex" "$test_root/invalid-main.tex"

run_in "$invalid_split" "$KICHO" split
assert_status 1 'split rejects unclosed marker'
assert_contains 'has no end marker' "$command_stderr"
assert_same "$test_root/invalid-main.tex" "$invalid_split/main.tex" 'failed split changed main.tex'
assert_not_exists "$invalid_split/main.tex.kicho-backup"

existing_split="$test_root/ExistingSplit"
create_project_root "$existing_split"
mkdir -p "$existing_split/sections"
{
    printf '%% kicho:section introduction\n'
    printf 'new contents\n'
    printf '%% kicho:end\n'
} > "$existing_split/main.tex"
printf 'existing contents\n' > "$existing_split/sections/introduction.tex"

run_in "$existing_split" "$KICHO" split
assert_status 1 'split refuses existing section file'
assert_contains 'destination already exists' "$command_stderr"
assert_contains 'existing contents' "$existing_split/sections/introduction.tex"
assert_not_exists "$existing_split/main.tex.kicho-backup"

flatten_project="$test_root/Flatten Paper"
create_project_root "$flatten_project"
mkdir -p "$flatten_project/parts"
{
    printf 'START\n'
    printf '\\input{parts/one}\n'
    printf 'END\n'
} > "$flatten_project/main.tex"
{
    printf 'ONE\n'
    printf '\\include{parts/two.tex}\n'
} > "$flatten_project/parts/one.tex"
printf 'TWO\n' > "$flatten_project/parts/two.tex"
{
    printf 'START\n'
    printf 'ONE\n'
    printf 'TWO\n'
    printf 'END\n'
} > "$test_root/expected-flat.tex"

run_in "$flatten_project" "$KICHO" flatten
assert_status 0 'flatten nested inputs'
assert_file "$flatten_project/dist/main.tex"
assert_same "$test_root/expected-flat.tex" "$flatten_project/dist/main.tex" 'flattened output was incorrect'
assert_contains '\input{parts/one}' "$flatten_project/main.tex"

run_in "$flatten_project" "$KICHO" flatten
assert_status 1 'flatten refuses overwrite'
assert_contains 'destination already exists' "$command_stderr"

cycle_project="$test_root/CyclePaper"
create_project_root "$cycle_project"
mkdir -p "$cycle_project/parts"
printf '\\input{parts/a}\n' > "$cycle_project/main.tex"
printf '\\input{parts/b}\n' > "$cycle_project/parts/a.tex"
printf '\\input{parts/a}\n' > "$cycle_project/parts/b.tex"

run_in "$cycle_project" "$KICHO" flatten
assert_status 1 'flatten rejects include cycle'
assert_contains 'include cycle detected' "$command_stderr"
assert_not_exists "$cycle_project/dist/main.tex"

outside_project="$test_root/OutsidePaper"
create_project_root "$outside_project"
printf '\\input{../outside}\n' > "$outside_project/main.tex"
printf 'outside\n' > "$test_root/outside.tex"

run_in "$outside_project" "$KICHO" flatten
assert_status 1 'flatten rejects parent path'
assert_contains "does not allow '..'" "$command_stderr"
assert_not_exists "$outside_project/dist/main.tex"

missing_project="$test_root/MissingInputPaper"
create_project_root "$missing_project"
printf '\\input{parts/missing}\n' > "$missing_project/main.tex"

run_in "$missing_project" "$KICHO" flatten
assert_status 1 'flatten rejects missing input'
assert_contains 'input directory was not found' "$command_stderr"
assert_not_exists "$missing_project/dist/main.tex"

submit_project="$test_root/Submit Paper"
create_project_root "$submit_project"
mkdir -p "$submit_project/parts" "$submit_project/bib" "$submit_project/figures" "$submit_project/build"
{
    printf 'SUBMIT START\n'
    printf '\\input{parts/body}\n'
    printf 'SUBMIT END\n'
} > "$submit_project/main.tex"
printf 'BODY\n' > "$submit_project/parts/body.tex"
printf 'BIB\n' > "$submit_project/bib/references.bib"
printf 'FIGURE\n' > "$submit_project/figures/figure.txt"
printf 'PDF\n' > "$submit_project/build/main.pdf"

run_in "$submit_project" "$KICHO" submit
assert_status 0 'submit package creation'
assert_file "$submit_project/submission/main.tex"
assert_file "$submit_project/submission/bib/references.bib"
assert_file "$submit_project/submission/figures/figure.txt"
assert_file "$submit_project/submission/main.pdf"
assert_file "$submit_project/submission/.latexmkrc"
assert_file "$submit_project/submission/manifest.json"
assert_contains 'BODY' "$submit_project/submission/main.tex"
assert_not_contains '\input{parts/body}' "$submit_project/submission/main.tex"
assert_contains '"project": "Submit Paper"' "$submit_project/submission/manifest.json"

if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' \
        "$submit_project/submission/manifest.json"; then
        fail 'submission manifest is not valid JSON'
    fi
fi

run_in "$submit_project" "$KICHO" submit
assert_status 1 'submit refuses overwrite'
assert_contains 'destination already exists' "$command_stderr"

submit_without_pdf="$test_root/SubmitWithoutPDF"
create_project_root "$submit_without_pdf"
printf 'standalone\n' > "$submit_without_pdf/main.tex"

run_in "$submit_without_pdf" "$KICHO" submit
assert_status 0 'submit without PDF'
assert_contains 'Warning: build/main.pdf not found.' "$command_stderr"
assert_file "$submit_without_pdf/submission/main.tex"
assert_file "$submit_without_pdf/submission/manifest.json"
assert_not_exists "$submit_without_pdf/submission/main.pdf"

if ((failures > 0)); then
    printf '%d workflow test(s) failed.\n' "$failures" >&2
    exit 1
fi

printf 'Workflow tests passed.\n'
