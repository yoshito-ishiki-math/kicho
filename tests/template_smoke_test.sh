#!/usr/bin/env bash

set -eu

TEST_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"
KICHO_ROOT="$(
    cd -- "$TEST_DIR/.." &&
    pwd
)"
KICHO="$KICHO_ROOT/bin/kicho"

for command in latexmk lualatex biber perl python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Template smoke test requires %s.\n' "$command" >&2
        exit 1
    fi
done

test_root="$(mktemp -d "${TMPDIR:-/tmp}/kicho-template-smoke.XXXXXX")" || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

add_export_fixture() {
    local project="$1"
    mkdir -p "$project/styles" "$project/extras"
    printf '\\ProvidesPackage{styles/export-fixture}\n\\RequirePackage{styles/export-helper}\n' \
        > "$project/styles/export-fixture.sty"
    printf '\\ProvidesPackage{styles/export-helper}\n\\newcommand{\\kichoexporttest}{Portable style}\n' \
        > "$project/styles/export-helper.sty"
    printf 'Compiler-recorded input.\n' > "$project/extras/fixture.tex"
    cat >> "$project/preamble/packages.tex" <<'TEX'

\usepackage{styles/export-fixture}
\usepackage{graphicx}
\graphicspath{{figures/}}
\newcommand{\kichoFixtureInput}{extras/fixture}
TEX
    cat >> "$project/sections/introduction.tex" <<'TEX'

\kichoexporttest. \includegraphics[width=2mm]{export-dot}
Recorder: \input{\kichoFixtureInput}
TEX
    python3 - "$project/figures/export-dot.png" <<'PY'
from pathlib import Path
import struct
import sys
import zlib

def chunk(tag, data):
    return (struct.pack('>I', len(data)) + tag + data
            + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

Path(sys.argv[1]).write_bytes(b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress(b'\x00\xff\xff\xff')) + chunk(b'IEND', b''))
PY
}

english_project="$test_root/English Paper"
"$KICHO" init "$english_project"
add_export_fixture "$english_project"

perl -0pi -e \
    's/Write the abstract here\./For \$x \\in \\R\$, we have \\(\\abs\{x\} \\geq 0\\\)\.\n\\\[\\norm\{x\} = \\abs\{x\}\.\\\]/' \
    "$english_project/main.tex"

"$KICHO" paraids install --root "$english_project"
printf '\n\\usepackage{paragraphids}\n' >> "$english_project/preamble/packages.tex"
cat >> "$english_project/sections/introduction.tex" <<'TEX'

\paraid{p-111111111111}
\paranote{1}{Review this paragraph.}
This paragraph tests the release copy.
TEX

(
    cd -- "$english_project" &&
    "$KICHO" check --json &&
    "$KICHO" submit --build
)

if [[ ! -f "$english_project/build/main.pdf" ]]; then
    printf 'English template did not produce build/main.pdf.\n' >&2
    exit 1
fi

japanese_project="$test_root/日本語 論文"
"$KICHO" init --template japanese "$japanese_project"
add_export_fixture "$japanese_project"
"$KICHO" paraids install --root "$japanese_project"
printf '\n\\usepackage{paragraphids}\n' >> "$japanese_project/preamble/packages.tex"
cat >> "$japanese_project/sections/introduction.tex" <<'TEX'

\paraid{p-222222222222}
\paranote{2}{この説明の短縮を検討してください。}
この段落で投稿用コピーの生成を確認する。
TEX

(
    cd -- "$japanese_project" &&
    "$KICHO" check --json &&
    "$KICHO" submit --build
)

if [[ ! -f "$japanese_project/build/main.pdf" ]]; then
    printf 'Japanese template did not produce build/main.pdf.\n' >&2
    exit 1
fi

for project in "$english_project" "$japanese_project"; do
    if [[ ! -f "$project/submission/main.pdf" || -e "$project/submission/paragraphids.sty" ]]; then
        printf 'Submission did not produce a PDF without the editorial package: %s\n' "$project" >&2
        exit 1
    fi
    if ! grep -F '\paranote{' "$project/sections/introduction.tex" >/dev/null; then
        printf 'Submission changed the working annotations: %s\n' "$project" >&2
        exit 1
    fi
    if [[ ! -f "$project/submission/styles/export-helper.sty" ||
        ! -f "$project/submission/extras/fixture.tex" ]]; then
        printf 'Submission omitted a local or recorder dependency: %s\n' "$project" >&2
        exit 1
    fi
    # Compile using only the exported sources, independently of the live tree.
    if ! (cd -- "$project/submission" && "$KICHO" build); then
        printf 'Exported sources did not build independently: %s\n' "$project" >&2
        exit 1
    fi
    if ! (cd -- "$project" && "$KICHO" archive && "$KICHO" paraids check); then
        printf 'Paragraph-ID checks failed after archiving: %s\n' "$project" >&2
        exit 1
    fi
done

printf 'Template smoke tests passed.\n'
