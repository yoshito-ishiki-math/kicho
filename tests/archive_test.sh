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

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

assert_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        fail "file not found: $path"
    fi
}

assert_directory() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        fail "directory not found: $path"
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

assert_equal() {
    local expected="$1"
    local actual="$2"
    local description="$3"

    if [[ "$expected" != "$actual" ]]; then
        fail "$description: expected '$expected', got '$actual'"
    fi
}

archive_directory() {
    local project="$1"
    local archive_directories

    archive_directories=("$project"/archives/*)
    if [[ ${#archive_directories[@]} -ne 1 || ! -d "${archive_directories[0]}" ]]; then
        return 1
    fi

    printf '%s\n' "${archive_directories[0]}"
}

create_project() {
    local project="$1"

    mkdir -p \
        "$project/sections" \
        "$project/preamble" \
        "$project/figures" \
        "$project/bib" \
        "$project/build"

    printf 'main source\n' > "$project/main.tex"
    printf 'latexmk configuration\n' > "$project/.latexmkrc"
    printf 'section source\n' > "$project/sections/introduction.tex"
    printf 'preamble source\n' > "$project/preamble/packages.tex"
    printf 'figure data\n' > "$project/figures/figure.txt"
    printf 'bibliography data\n' > "$project/bib/references.bib"
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/kicho-archive-test.XXXXXX")" || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

project_name='Paper "Notes"\Draft'
project="$test_root/$project_name"
create_project "$project"
printf 'compiled pdf\n' > "$project/build/main.pdf"

git_available=false
git_branch=""
git_commit=""

if command -v git >/dev/null 2>&1; then
    git_available=true
    git -C "$project" init -q
    git -C "$project" config user.name 'Kicho Test'
    git -C "$project" config user.email 'kicho-test@example.invalid'
    git -C "$project" add .
    git -C "$project" commit -qm 'Create archive fixture'
    git_branch="$(git -C "$project" symbolic-ref --short HEAD)"
    git_commit="$(git -C "$project" rev-parse HEAD)"
fi

if ! (
    cd -- "$project" &&
    "$KICHO" archive > "$test_root/archive.stdout" 2> "$test_root/archive.stderr"
); then
    fail 'archive command failed for a complete project'
fi

archive_root="$(archive_directory "$project")" || {
    fail 'exactly one archive directory was not created'
    archive_root="$project/archives/missing"
}

assert_file "$archive_root/source/main.tex"
assert_file "$archive_root/source/sections/introduction.tex"
assert_file "$archive_root/source/preamble/packages.tex"
assert_file "$archive_root/source/figures/figure.txt"
assert_file "$archive_root/source/bib/references.bib"
assert_file "$archive_root/source/.latexmkrc"
assert_file "$archive_root/pdf/main.pdf"
assert_file "$archive_root/metadata/archive.json"

if [[ -f "$archive_root/pdf/main.pdf" ]] &&
    ! cmp -s "$project/build/main.pdf" "$archive_root/pdf/main.pdf"; then
    fail 'archived PDF differs from build/main.pdf'
fi

metadata="$archive_root/metadata/archive.json"
assert_contains '"kicho_version": "0.1.0"' "$metadata"
assert_contains '"project": "Paper \"Notes\"\\Draft"' "$metadata"

if ! grep -E '"created_at": "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}"' "$metadata" >/dev/null 2>&1; then
    fail 'created_at is not an ISO 8601 timestamp with a colonized offset'
fi

if [[ "$git_available" == "true" ]]; then
    assert_contains '"git": {' "$metadata"
    assert_contains "\"branch\": \"$git_branch\"" "$metadata"
    assert_contains "\"commit\": \"$git_commit\"" "$metadata"
    assert_contains '"dirty": false' "$metadata"
else
    assert_not_contains '"git": {' "$metadata"
fi

if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$metadata"; then
        fail 'archive.json is not valid JSON'
    fi
fi

if [[ "$git_available" == "true" ]]; then
    dirty_project="$test_root/DirtyPaper"
    create_project "$dirty_project"
    git -C "$dirty_project" init -q
    git -C "$dirty_project" config user.name 'Kicho Test'
    git -C "$dirty_project" config user.email 'kicho-test@example.invalid'
    git -C "$dirty_project" add .
    git -C "$dirty_project" commit -qm 'Create dirty archive fixture'
    printf 'uncommitted change\n' >> "$dirty_project/main.tex"

    if ! (
        cd -- "$dirty_project" &&
        "$KICHO" archive > "$test_root/dirty.stdout" 2> "$test_root/dirty.stderr"
    ); then
        fail 'archive command failed for a dirty Git project'
    fi

    dirty_archive="$(archive_directory "$dirty_project")" || {
        fail 'archive directory was not created for the dirty Git case'
        dirty_archive="$dirty_project/archives/missing"
    }

    assert_contains '"dirty": true' "$dirty_archive/metadata/archive.json"
fi

missing_pdf_project="$test_root/NoPDF"
create_project "$missing_pdf_project"

if ! (
    cd -- "$missing_pdf_project" &&
    "$KICHO" archive > "$test_root/missing-pdf.stdout" 2> "$test_root/missing-pdf.stderr"
); then
    fail 'archive command failed when the PDF was missing'
fi

missing_pdf_archive="$(archive_directory "$missing_pdf_project")" || {
    fail 'archive directory was not created for the missing-PDF case'
    missing_pdf_archive="$missing_pdf_project/archives/missing"
}

assert_directory "$missing_pdf_archive/pdf"
assert_contains 'Warning: build/main.pdf not found.' "$test_root/missing-pdf.stderr"
assert_file "$missing_pdf_archive/metadata/archive.json"
assert_not_contains '"git": {' "$missing_pdf_archive/metadata/archive.json"

# shellcheck source=/dev/null
source "$KICHO_ROOT/lib/kicho/common.sh"
# shellcheck source=/dev/null
source "$KICHO_ROOT/lib/kicho/commands/archive.sh"

json_input=$'論文 quote" slash\\ line\n tab\t control\001'
json_expected='論文 quote\" slash\\ line\n tab\t control\u0001'
json_actual="$(kicho_json_escape "$json_input")"
assert_equal "$json_expected" "$json_actual" 'JSON escaping'

if ((failures > 0)); then
    printf '%d archive test(s) failed.\n' "$failures" >&2
    exit 1
fi

printf 'Archive tests passed.\n'
