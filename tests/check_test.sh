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
command_stdout=''
command_stderr=''

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

run_check() {
    local directory="$1"
    shift

    command_stdout="$test_root/stdout"
    command_stderr="$test_root/stderr"
    (
        cd -- "$directory" &&
        "$KICHO" check "$@"
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

assert_contains() {
    local expected="$1"
    local path="$2"
    local description="$3"
    if ! grep -F -- "$expected" "$path" >/dev/null 2>&1; then
        fail "$description: '$expected' not found"
    fi
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/kicho-check-test.XXXXXX")" || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

valid_project="$test_root/Valid 日本語 Project"
mkdir -p \
    "$valid_project/sections" \
    "$valid_project/preamble" \
    "$valid_project/bib" \
    "$valid_project/figures"
: > "$valid_project/.latexmkrc"
: > "$valid_project/bib/references.bib"
: > "$valid_project/figures/plot.pdf"

{
    printf '\\input{preamble/packages}\n'
    printf '\\input{sections/introduction}\n'
    printf '\\includegraphics[width=1cm]{figures/plot}\n'
} > "$valid_project/main.tex"
printf '\\addbibresource{bib/references.bib}\n' > "$valid_project/preamble/packages.tex"
printf 'Introduction.\n' > "$valid_project/sections/introduction.tex"

run_check "$valid_project"
assert_status 0 'valid project'
assert_contains 'All project checks passed.' "$command_stdout" 'valid project summary'
assert_contains 'input: sections/introduction' "$command_stdout" 'input reference report'
assert_contains 'bibliography: bib/references.bib' "$command_stdout" 'bibliography reference report'
assert_contains 'figure: figures/plot' "$command_stdout" 'figure reference report'

missing_input="$test_root/Missing Input"
cp -R "$valid_project" "$missing_input"
printf '\\input{sections/missing}\n' >> "$missing_input/main.tex"
run_check "$missing_input"
assert_status 1 'missing input'
assert_contains "input file was not found: 'sections/missing.tex'" "$command_stdout" 'missing input report'

missing_bibliography="$test_root/Missing Bibliography"
cp -R "$valid_project" "$missing_bibliography"
printf '\\addbibresource{bib/missing.bib}\n' >> "$missing_bibliography/main.tex"
run_check "$missing_bibliography"
assert_status 1 'missing bibliography'
assert_contains "bib file was not found: 'bib/missing.bib'" "$command_stdout" 'missing bibliography report'

missing_figure="$test_root/Missing Figure"
cp -R "$valid_project" "$missing_figure"
printf '\\includegraphics{figures/missing}\n' >> "$missing_figure/main.tex"
run_check "$missing_figure"
assert_status 1 'missing figure'
assert_contains "figure file was not found: 'figures/missing'" "$command_stdout" 'missing figure report'

warning_project="$test_root/Warnings"
mkdir -p "$warning_project"
: > "$warning_project/.latexmkrc"
printf '\\documentclass{article}\n' > "$warning_project/main.tex"
run_check "$warning_project"
assert_status 0 'warning-only project'
assert_contains 'Warnings: 2' "$command_stdout" 'warning count'
assert_contains 'Project checks passed, with warnings.' "$command_stdout" 'warning exit summary'

incomplete_project="$test_root/Incomplete Project"
mkdir -p "$incomplete_project/bib" "$incomplete_project/figures"
: > "$incomplete_project/.latexmkrc"
run_check "$incomplete_project"
assert_status 1 'incomplete project'
assert_contains 'main.tex was not found' "$command_stdout" 'incomplete project report'
assert_contains 'Errors:   1' "$command_stdout" 'incomplete project error count'

dynamic_project="$test_root/Dynamic Reference"
cp -R "$valid_project" "$dynamic_project"
printf '\\input{\\jobname}\n' >> "$dynamic_project/main.tex"
run_check "$dynamic_project"
assert_status 0 'dynamic reference warning'
assert_contains 'dynamic input reference was not checked' "$command_stdout" 'dynamic reference report'

outside_project="$test_root/Outside Reference"
cp -R "$valid_project" "$outside_project"
printf '\\input{../secret}\n' >> "$outside_project/main.tex"
run_check "$outside_project"
assert_status 1 'outside reference'
assert_contains 'parent-path input reference is not allowed' "$command_stdout" 'outside reference report'

run_check "$test_root"
assert_status 1 'missing project files'
assert_contains '.latexmkrc was not found' "$command_stdout" 'missing project marker report'
assert_contains 'main.tex was not found' "$command_stdout" 'missing main report'

run_check "$test_root" unexpected
assert_status 1 'check argument error'
assert_contains 'check does not accept arguments' "$command_stderr" 'check argument stderr'

if ((failures > 0)); then
    printf '%d check test(s) failed.\n' "$failures" >&2
    exit 1
fi

printf 'Check tests passed.\n'
