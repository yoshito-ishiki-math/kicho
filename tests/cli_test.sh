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

assert_contains() {
    local expected="$1"
    local path="$2"
    local description="$3"

    if ! grep -F -- "$expected" "$path" >/dev/null 2>&1; then
        fail "$description: '$expected' not found"
    fi
}

assert_not_exists() {
    local path="$1"
    local description="$2"

    if [[ -e "$path" ]]; then
        fail "$description: unexpected path $path"
    fi
}

assert_file() {
    local path="$1"
    local description="$2"

    if [[ ! -f "$path" ]]; then
        fail "$description: file not found $path"
    fi
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/kicho-cli-test.XXXXXX")" || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

run_in "$test_root" "$KICHO" --version
assert_status 0 '--version'
assert_contains 'kicho 0.2.0-alpha.1' "$command_stdout" '--version output'

run_in "$test_root" "$KICHO"
assert_status 0 'empty command'
assert_contains 'Kicho — Workflow manager for LaTeX research projects.' "$command_stdout" 'general help heading'

for command in archive build check clean doctor flatten init split submit; do
    run_in "$test_root" "$KICHO" help "$command"
    assert_status 0 "help $command"
    assert_contains "kicho $command" "$command_stdout" "help $command usage"
done

for command in archive build check clean doctor flatten init split submit; do
    for help_option in -h --help; do
        run_in "$test_root" "$KICHO" "$command" "$help_option"
        assert_status 0 "$command $help_option outside a project"
        assert_contains "kicho $command" "$command_stdout" "$command $help_option usage"
    done
done

run_in "$test_root" "$KICHO" --version unexpected
assert_status 1 '--version with argument'
assert_contains "'--version' does not accept arguments" "$command_stderr" '--version argument error'

run_in "$test_root" "$KICHO" --help unexpected
assert_status 1 '--help with argument'
assert_contains "'--help' does not accept arguments" "$command_stderr" '--help argument error'

run_in "$test_root" "$KICHO" help build unexpected
assert_status 1 'help with extra argument'
assert_contains 'help accepts only one command name' "$command_stderr" 'help argument error'

run_in "$test_root" "$KICHO" missing
assert_status 1 'unknown command'
assert_contains "unknown command 'missing'" "$command_stderr" 'unknown command error'

run_in "$test_root" "$KICHO" 'Invalid!'
assert_status 1 'invalid command name'
assert_contains "invalid command name 'Invalid!'" "$command_stderr" 'invalid command error'

run_in "$test_root" "$KICHO" help missing
assert_status 1 'unknown help command'
assert_contains "unknown command 'missing'" "$command_stderr" 'unknown help command error'

run_in "$test_root" "$KICHO" init
assert_status 1 'init without project'
assert_contains 'project name required' "$command_stderr" 'init missing-project error'

run_in "$test_root" "$KICHO" init One Two
assert_status 1 'init with extra argument'
assert_contains 'init accepts exactly one project name' "$command_stderr" 'init extra-argument error'

project="$test_root/Paper With Spaces"
run_in "$test_root" "$KICHO" init "$project"
assert_status 0 'init project with spaces'
assert_contains "Created project: $project" "$command_stdout" 'init success output'
assert_file "$project/main.tex" 'initialized main.tex'
assert_file "$project/.latexmkrc" 'initialized .latexmkrc'
assert_file "$project/build/.gitkeep" 'initialized build placeholder'
assert_contains '{amsart}' "$project/main.tex" 'default English template'
assert_not_exists "$project/build/main.pdf" 'init excludes ignored PDF artifact'
assert_not_exists "$project/build/main.aux" 'init excludes ignored auxiliary artifact'

run_in "$test_root" "$KICHO" init "$project"
assert_status 1 'init existing destination'
assert_contains 'already exists' "$command_stderr" 'init existing-destination error'

japanese_project="$test_root/日本語 論文"
run_in "$test_root" "$KICHO" init --template japanese "$japanese_project"
assert_status 0 'init Japanese project'
assert_file "$japanese_project/main.tex" 'Japanese main.tex'
assert_file "$japanese_project/preamble/packages.tex" 'Japanese packages.tex'
assert_file "$japanese_project/preamble/macros.tex" 'Japanese macros.tex'
assert_file "$japanese_project/preamble/theorem.tex" 'Japanese theorem.tex'
assert_file "$japanese_project/sections/introduction.tex" 'Japanese introduction.tex'
assert_file "$japanese_project/build/.gitkeep" 'Japanese build placeholder'
assert_contains '{jlreq}' "$japanese_project/main.tex" 'Japanese document class'
assert_contains 'luatexja-fontspec' "$japanese_project/preamble/packages.tex" 'LuaLaTeX-ja package'
assert_contains 'HaranoAjiMincho' "$japanese_project/preamble/packages.tex" 'Japanese main font'
assert_contains '\newtheorem{theorem}{定理}' "$japanese_project/preamble/theorem.tex" 'Japanese theorem label'
assert_not_exists "$japanese_project/build/main.pdf" 'Japanese init excludes PDF artifact'

run_in "$test_root" "$KICHO" init --template unknown "$test_root/UnknownTemplate"
assert_status 1 'init unknown template'
assert_contains "unknown project template 'unknown'" "$command_stderr" 'unknown template error'
assert_not_exists "$test_root/UnknownTemplate" 'unknown template destination'

run_in "$test_root" "$KICHO" init --template
assert_status 1 'init missing template value'
assert_contains 'requires a template name' "$command_stderr" 'missing template value error'

for command in build clean archive split flatten submit; do
    run_in "$test_root" "$KICHO" "$command"
    assert_status 1 "$command outside a project"
    assert_contains "'.latexmkrc' not found" "$command_stderr" "$command project requirement"
done

run_in "$test_root" "$KICHO" doctor --help
assert_status 0 'doctor help outside a project'
assert_contains 'The doctor command can be run inside or outside a Kicho project.' "$command_stdout" 'doctor help text'

path_without_latexmk="$test_root/path-without-latexmk"
mkdir -p "$path_without_latexmk"
ln -s "$(command -v bash)" "$path_without_latexmk/bash"
ln -s "$(command -v basename)" "$path_without_latexmk/basename"
ln -s "$(command -v dirname)" "$path_without_latexmk/dirname"

run_in "$project" env \
    PATH="$path_without_latexmk" \
    "$KICHO" build
assert_status 1 'build without latexmk'
assert_contains "'latexmk' is not installed" "$command_stderr" 'missing latexmk error'

fake_bin="$test_root/fake-bin"
latexmk_log="$test_root/latexmk.log"
mkdir -p "$fake_bin"
# The single-quoted strings below are the literal contents of the fake command.
# shellcheck disable=SC2016
{
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> "$KICHO_TEST_LATEXMK_LOG"\n'
    printf 'exit "${KICHO_TEST_LATEXMK_STATUS:-0}"\n'
} > "$fake_bin/latexmk"
chmod +x "$fake_bin/latexmk"

run_in "$project" env \
    PATH="$fake_bin:$PATH" \
    KICHO_TEST_LATEXMK_LOG="$latexmk_log" \
    "$KICHO" build
assert_status 0 'build with latexmk'
assert_contains 'Build completed successfully.' "$command_stdout" 'build success output'

run_in "$project" env \
    PATH="$fake_bin:$PATH" \
    KICHO_TEST_LATEXMK_LOG="$latexmk_log" \
    "$KICHO" build unexpected
assert_status 1 'build with argument'
assert_contains 'build does not accept arguments' "$command_stderr" 'build argument error'

run_in "$project" env \
    PATH="$fake_bin:$PATH" \
    KICHO_TEST_LATEXMK_LOG="$latexmk_log" \
    KICHO_TEST_LATEXMK_STATUS=7 \
    "$KICHO" build
assert_status 7 'failed build preserves latexmk status'
assert_contains 'build failed' "$command_stderr" 'failed build error'

printf 'generated file\n' > "$project/build/generated.aux"
run_in "$project" env \
    PATH="$fake_bin:$PATH" \
    KICHO_TEST_LATEXMK_LOG="$latexmk_log" \
    KICHO_TEST_LATEXMK_STATUS=8 \
    "$KICHO" clean
assert_status 8 'failed clean preserves latexmk status'
assert_file "$project/build/generated.aux" 'failed clean preserves build directory'

run_in "$project" env \
    PATH="$fake_bin:$PATH" \
    KICHO_TEST_LATEXMK_LOG="$latexmk_log" \
    "$KICHO" clean unexpected
assert_status 1 'clean with argument'
assert_contains 'clean does not accept arguments' "$command_stderr" 'clean argument error'

run_in "$project" env \
    PATH="$fake_bin:$PATH" \
    KICHO_TEST_LATEXMK_LOG="$latexmk_log" \
    "$KICHO" clean
assert_status 0 'clean with latexmk'
assert_contains 'Clean completed successfully.' "$command_stdout" 'clean success output'
assert_not_exists "$project/build" 'successful clean removes build directory'
assert_contains '-C' "$latexmk_log" 'clean invokes latexmk -C'

for command in split flatten submit; do
    run_in "$project" "$KICHO" "$command" unexpected
    assert_status 1 "$command with argument"
    assert_contains "$command does not accept arguments" "$command_stderr" "$command argument error"
done

run_in "$project" "$KICHO" archive unexpected
assert_status 1 'archive with argument'
assert_contains 'archive does not accept arguments' "$command_stderr" 'archive argument error'

if ((failures > 0)); then
    printf '%d CLI test(s) failed.\n' "$failures" >&2
    exit 1
fi

printf 'CLI tests passed.\n'
