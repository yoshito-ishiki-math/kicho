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

run_doctor() {
    local directory="$1"
    local path="$2"
    shift 2

    command_stdout="$test_root/stdout"
    command_stderr="$test_root/stderr"
    (
        cd -- "$directory" &&
        PATH="$path" "$KICHO" doctor "$@"
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

make_tool_path() {
    local destination="$1"
    shift

    mkdir -p "$destination"
    ln -s "$(command -v bash)" "$destination/bash"
    ln -s "$(command -v basename)" "$destination/basename"
    ln -s "$(command -v dirname)" "$destination/dirname"

    local tool
    for tool in "$@"; do
        ln -s /usr/bin/true "$destination/$tool"
    done
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/kicho-doctor-test.XXXXXX")" || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

complete_project="$test_root/Complete Project"
mkdir -p "$complete_project/bib" "$complete_project/build"
: > "$complete_project/.latexmkrc"
: > "$complete_project/main.tex"

incomplete_project="$test_root/Incomplete Project"
mkdir -p "$incomplete_project"
: > "$incomplete_project/.latexmkrc"

all_tools="$test_root/all-tools"
make_tool_path "$all_tools" latexmk lualatex biber git

run_doctor "$complete_project" "$all_tools"
assert_status 0 'doctor in a complete environment'
assert_contains 'All checks passed.' "$command_stdout" 'doctor success summary'
assert_contains 'Failures: 0' "$command_stdout" 'doctor success failures'
assert_contains 'Warnings: 0' "$command_stdout" 'doctor success warnings'

missing_biber="$test_root/missing-biber"
make_tool_path "$missing_biber" latexmk lualatex git

run_doctor "$complete_project" "$missing_biber"
assert_status 1 'doctor with a missing required tool'
assert_contains 'FAIL  biber was not found.' "$command_stdout" 'missing biber report'
assert_contains 'Failures: 1' "$command_stdout" 'missing tool failure count'
assert_contains 'found required problems' "$command_stdout" 'doctor failure summary'

warning_tools="$test_root/warning-tools"
make_tool_path "$warning_tools" latexmk lualatex biber

run_doctor "$complete_project" "$warning_tools"
assert_status 0 'doctor warning exit status'
assert_contains 'WARN  git was not found.' "$command_stdout" 'optional tool warning'
assert_contains 'Required checks passed, with warnings.' "$command_stdout" 'warning summary'

run_doctor "$incomplete_project" "$all_tools"
assert_status 0 'doctor is independent of incomplete project structure'
assert_contains 'All checks passed.' "$command_stdout" 'doctor ignores project completeness'
assert_contains 'Warnings: 0' "$command_stdout" 'incomplete project does not affect doctor warnings'

run_doctor "$complete_project" "$all_tools" unexpected
assert_status 1 'doctor argument error'
assert_contains 'doctor does not accept arguments' "$command_stderr" 'doctor argument stderr'

if ((failures > 0)); then
    printf '%d doctor test(s) failed.\n' "$failures" >&2
    exit 1
fi

printf 'Doctor tests passed.\n'
