#!/usr/bin/env bash

# Shared assertions and command runner for Kicho shell tests.

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

assert_contains() {
    local expected="$1"
    local path="$2"
    local description="${3:-}"

    if [[ -z "$description" ]]; then
        description="'$expected' not found in $path"
    fi

    if ! grep -F -- "$expected" "$path" >/dev/null 2>&1; then
        fail "$description"
    fi
}

assert_not_contains() {
    local unexpected="$1"
    local path="$2"
    local description="${3:-}"

    if [[ -z "$description" ]]; then
        description="'$unexpected' unexpectedly found in $path"
    fi

    if grep -F -- "$unexpected" "$path" >/dev/null 2>&1; then
        fail "$description"
    fi
}

assert_file() {
    local path="$1"
    local description="${2:-file not found: $path}"

    if [[ ! -f "$path" ]]; then
        fail "$description"
    fi
}

assert_directory() {
    local path="$1"
    local description="${2:-directory not found: $path}"

    if [[ ! -d "$path" ]]; then
        fail "$description"
    fi
}

assert_not_exists() {
    local path="$1"
    local description="${2:-unexpected path: $path}"

    if [[ -e "$path" || -L "$path" ]]; then
        fail "$description"
    fi
}
