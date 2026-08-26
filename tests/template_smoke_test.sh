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

for command in latexmk lualatex biber perl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Template smoke test requires %s.\n' "$command" >&2
        exit 1
    fi
done

test_root="$(mktemp -d "${TMPDIR:-/tmp}/kicho-template-smoke.XXXXXX")" || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

english_project="$test_root/English Paper"
"$KICHO" init "$english_project"

perl -0pi -e \
    's/Write the abstract here\./For \$x \\in \\R\$, we have \\(\\abs\{x\} \\geq 0\\\)\.\n\\\[\\norm\{x\} = \\abs\{x\}\.\\\]/' \
    "$english_project/main.tex"

(
    cd -- "$english_project" &&
    "$KICHO" build
)

if [[ ! -f "$english_project/build/main.pdf" ]]; then
    printf 'English template did not produce build/main.pdf.\n' >&2
    exit 1
fi

japanese_project="$test_root/日本語 論文"
"$KICHO" init --template japanese "$japanese_project"

(
    cd -- "$japanese_project" &&
    "$KICHO" build
)

if [[ ! -f "$japanese_project/build/main.pdf" ]]; then
    printf 'Japanese template did not produce build/main.pdf.\n' >&2
    exit 1
fi

printf 'Template smoke tests passed.\n'
