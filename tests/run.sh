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
KICHO_TEST_BASH="${KICHO_TEST_BASH:-bash}"

status=0

if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'ShellCheck is required to run the test suite.\n' >&2
    status=1
elif ! shellcheck -x \
    "$KICHO_ROOT/bin/kicho" \
    "$KICHO_ROOT/lib/kicho/"*.sh \
    "$KICHO_ROOT/lib/kicho/commands/"*.sh \
    "$TEST_DIR/"*.sh; then
    status=1
fi

if ! "$KICHO_TEST_BASH" -n \
    "$KICHO_ROOT/bin/kicho" \
    "$KICHO_ROOT/lib/kicho/"*.sh \
    "$KICHO_ROOT/lib/kicho/commands/"*.sh \
    "$TEST_DIR/"*.sh; then
    status=1
fi

for test_file in \
    "$TEST_DIR/cli_test.sh" \
    "$TEST_DIR/doctor_test.sh" \
    "$TEST_DIR/check_test.sh" \
    "$TEST_DIR/archive_test.sh" \
    "$TEST_DIR/workflow_test.sh"; do
    if ! "$KICHO_TEST_BASH" "$test_file"; then
        status=1
    fi
done

if ((status != 0)); then
    printf 'Test suite failed.\n' >&2
    exit "$status"
fi

printf 'All tests passed.\n'
