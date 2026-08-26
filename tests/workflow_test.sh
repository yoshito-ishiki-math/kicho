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

assert_zip_contains() {
    local expected="$1"
    local archive="$2"

    if ! unzip -Z1 "$archive" | grep -Fx -- "$expected" >/dev/null 2>&1; then
        fail "'$expected' not found in $archive"
    fi
}

assert_zip_not_contains() {
    local unexpected="$1"
    local archive="$2"

    if unzip -Z1 "$archive" | grep -Fx -- "$unexpected" >/dev/null 2>&1; then
        fail "'$unexpected' unexpectedly found in $archive"
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

{
    printf 'Introduction opening.\n'
    printf '%% kicho:section background\n'
    printf '\\section{Background}\n'
    printf 'Background text.\n'
    printf '%% kicho:end\n'
    printf 'Introduction closing.\n'
} > "$split_project/sections/introduction.tex"
cp "$split_project/sections/introduction.tex" "$test_root/original-introduction.tex"

run_in "$split_project" "$KICHO" split sections/introduction.tex
assert_status 0 'split an existing section file'
assert_file "$split_project/sections/introduction.tex.kicho-backup"
assert_file "$split_project/sections/background.tex"
assert_same \
    "$test_root/original-introduction.tex" \
    "$split_project/sections/introduction.tex.kicho-backup" \
    'section split backup differs from original'
assert_contains '\input{sections/background}' "$split_project/sections/introduction.tex"
assert_contains '\section{Background}' "$split_project/sections/background.tex"
assert_contains 'Background text.' "$split_project/sections/background.tex"
assert_not_contains 'Background text.' "$split_project/sections/introduction.tex"

run_in "$split_project" "$KICHO" split ../outside.tex
assert_status 1 'split rejects parent-path source'
assert_contains "does not allow '..'" "$command_stderr"

run_in "$split_project" "$KICHO" split /tmp/outside.tex
assert_status 1 'split rejects absolute source'
assert_contains 'does not allow absolute source paths' "$command_stderr"

printf 'outside\n' > "$test_root/outside-split.tex"
ln -s "$test_root/outside-split.tex" "$split_project/linked.tex"
run_in "$split_project" "$KICHO" split linked.tex
assert_status 1 'split rejects symbolic-link source'
assert_contains 'does not follow symbolic-link sources' "$command_stderr"

symlink_sections_project="$test_root/SymlinkSections"
create_project_root "$symlink_sections_project"
mkdir -p "$test_root/outside-sections"
ln -s "$test_root/outside-sections" "$symlink_sections_project/sections"
{
    printf '%% kicho:section escaped\n'
    printf 'must stay inside\n'
    printf '%% kicho:end\n'
} > "$symlink_sections_project/main.tex"

run_in "$symlink_sections_project" "$KICHO" split
assert_status 1 'split rejects symbolic-link sections directory'
assert_contains 'does not use a symbolic-link sections directory' "$command_stderr"
assert_not_exists "$test_root/outside-sections/escaped.tex"
assert_not_exists "$symlink_sections_project/main.tex.kicho-backup"

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

run_in "$submit_project" "$KICHO" submit --output submissions/revision-2
assert_status 0 'submit supports a custom nested output'
assert_file "$submit_project/submissions/revision-2/main.tex"
assert_file "$submit_project/submissions/revision-2/manifest.json"

run_in "$submit_project" "$KICHO" submit -o submissions/revision-2
assert_status 1 'submit refuses overwrite at custom output'
assert_contains "destination already exists: 'submissions/revision-2'" "$command_stderr"

submit_without_pdf="$test_root/SubmitWithoutPDF"
create_project_root "$submit_without_pdf"
printf 'standalone\n' > "$submit_without_pdf/main.tex"

run_in "$submit_without_pdf" "$KICHO" submit
assert_status 0 'submit without PDF'
assert_contains 'Warning: build/main.pdf not found.' "$command_stderr"
assert_file "$submit_without_pdf/submission/main.tex"
assert_file "$submit_without_pdf/submission/manifest.json"
assert_not_exists "$submit_without_pdf/submission/main.pdf"

run_in "$submit_without_pdf" "$KICHO" submit --output ../outside-submission
assert_status 1 'submit rejects parent output path'
assert_contains "does not allow '..'" "$command_stderr"
assert_not_exists "$test_root/outside-submission"

run_in "$submit_without_pdf" "$KICHO" submit --output "$test_root/absolute-submission"
assert_status 1 'submit rejects absolute output path'
assert_contains 'must be a relative path' "$command_stderr"
assert_not_exists "$test_root/absolute-submission"

ln -s "$test_root" "$submit_without_pdf/escape"
run_in "$submit_without_pdf" "$KICHO" submit --output escape/outside-submission
assert_status 1 'submit rejects symlink output outside project'
assert_contains 'resolves outside the project' "$command_stderr"
assert_not_exists "$test_root/outside-submission"

arxiv_project="$test_root/Arxiv Paper"
create_project_root "$arxiv_project"
mkdir -p "$arxiv_project/parts" "$arxiv_project/bib" \
    "$arxiv_project/figures" "$arxiv_project/build"
{
    printf '\\documentclass{amsart}\n'
    printf '\\title{A Submission Title}\n'
    printf '\\author{First Author}\n'
    printf '\\author{Second Author}\n'
    printf '\\subjclass[2020]{Primary 54E35; Secondary 54B20}\n'
    printf '\\keywords{metric geometry, hyperspaces}\n'
    printf '\\begin{document}\n'
    printf '\\begin{abstract}\n'
    printf 'A submission abstract.\n'
    printf '\\end{abstract}\n'
    printf '\\input{parts/body}\n'
    printf '\\printbibliography\n'
    printf '\\end{document}\n'
} > "$arxiv_project/main.tex"
printf 'BODY\n' > "$arxiv_project/parts/body.tex"
printf 'BIB SOURCE\n' > "$arxiv_project/bib/references.bib"
printf 'BBL OUTPUT\n' > "$arxiv_project/build/main.bbl"
printf 'FIGURE\n' > "$arxiv_project/figures/figure.txt"
printf 'hidden\n' > "$arxiv_project/figures/.gitkeep"

run_in "$arxiv_project" "$KICHO" submit --arxiv
assert_status 0 'arXiv submit package creation'
assert_file "$arxiv_project/submission/arxiv-source.zip"
assert_file "$arxiv_project/submission/arxiv-metadata.txt"
assert_file "$arxiv_project/submission/manifest.json"
assert_file "$arxiv_project/arxiv-metadata.txt"
assert_contains 'A Submission Title' "$arxiv_project/arxiv-metadata.txt"
assert_contains 'First Author, Second Author' "$arxiv_project/arxiv-metadata.txt"
assert_contains 'A submission abstract.' "$arxiv_project/arxiv-metadata.txt"
assert_contains 'Primary 54E35; Secondary 54B20' "$arxiv_project/arxiv-metadata.txt"
assert_contains 'metric geometry, hyperspaces' "$arxiv_project/arxiv-metadata.txt"
assert_zip_contains 'main.tex' "$arxiv_project/submission/arxiv-source.zip"
assert_zip_contains 'main.bbl' "$arxiv_project/submission/arxiv-source.zip"
assert_zip_contains 'figures/figure.txt' "$arxiv_project/submission/arxiv-source.zip"
assert_zip_not_contains 'bib/references.bib' "$arxiv_project/submission/arxiv-source.zip"
assert_zip_not_contains 'main.pdf' "$arxiv_project/submission/arxiv-source.zip"
assert_zip_not_contains '.latexmkrc' "$arxiv_project/submission/arxiv-source.zip"
assert_zip_not_contains 'figures/.gitkeep' "$arxiv_project/submission/arxiv-source.zip"
assert_zip_not_contains 'arxiv-metadata.txt' "$arxiv_project/submission/arxiv-source.zip"

arxiv_existing_metadata="$test_root/ArxivExistingMetadata"
create_project_root "$arxiv_existing_metadata"
{
    printf '\\documentclass{article}\n'
    printf '\\begin{document}\n'
    printf 'No metadata commands.\n'
    printf '\\end{document}\n'
} > "$arxiv_existing_metadata/main.tex"
{
    printf 'Title:\nCurated Title\n\n'
    printf 'Authors:\nCurated Author\n\n'
    printf 'Abstract:\nCurated abstract.\n\n'
    printf 'Comments:\n12 pages\n\n'
    printf 'MSC-class:\n54E35 (Primary)\n\n'
    printf 'Keywords:\nmetric spaces\n'
} > "$arxiv_existing_metadata/arxiv-metadata.txt"

run_in "$arxiv_existing_metadata" "$KICHO" submit --arxiv \
    --output packages/revision-2
assert_status 0 'arXiv submit reuses curated metadata'
assert_same \
    "$arxiv_existing_metadata/arxiv-metadata.txt" \
    "$arxiv_existing_metadata/packages/revision-2/arxiv-metadata.txt" \
    'arXiv submission metadata differs from curated source'

arxiv_missing_bbl="$test_root/ArxivMissingBbl"
create_project_root "$arxiv_missing_bbl"
{
    printf '\\documentclass{article}\n'
    printf '\\begin{document}\n'
    printf '\\bibliography{bib/references}\n'
    printf '\\end{document}\n'
} > "$arxiv_missing_bbl/main.tex"

run_in "$arxiv_missing_bbl" "$KICHO" submit --arxiv
assert_status 1 'arXiv submit requires bbl for bibliography'
assert_contains 'build/main.bbl was not found' "$command_stderr"
assert_not_exists "$arxiv_missing_bbl/submission"

if ((failures > 0)); then
    printf '%d workflow test(s) failed.\n' "$failures" >&2
    exit 1
fi

printf 'Workflow tests passed.\n'
