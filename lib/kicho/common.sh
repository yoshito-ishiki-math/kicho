# shellcheck shell=bash
# Common constants and functions for Kicho.

readonly KICHO_VERSION="0.2.0-alpha.3"

kicho_error() {
    printf 'Error: %s\n' "$1" >&2
}

# Produce only active text for static consumers, retaining one line per source line.
kicho_tex_active_file() {
    LC_ALL=C awk -f "$KICHO_LIB_DIR/tex-active.awk" "$1"
}

# Keep marker comments visible while masking literal ranges for transformations.
kicho_tex_nonliteral_file() {
    LC_ALL=C awk -v keep_comments=1 -v require_closed=1 \
        -f "$KICHO_LIB_DIR/tex-active.awk" "$1"
}

kicho_show_version() {
    printf 'kicho %s\n' "$KICHO_VERSION"
}

kicho_show_help() {
    cat <<'EOF'
Kicho — Workflow manager for LaTeX research projects.

Usage:
    kicho [--main FILE] [--build-dir DIR] COMMAND [ARGS]
    kicho help COMMAND
    kicho --help
    kicho --version

Commands:
EOF

    kicho_list_commands

    cat <<'EOF'

Options:
    -h, --help       Show this help message.
    -v, --version    Show version information.
    --main FILE      Select the project main TeX file.
    --build-dir DIR  Select the generated build directory.
EOF
}

kicho_require_project() {
    if [[ ! -f ".latexmkrc" ]]; then
        kicho_error "'.latexmkrc' not found."
        printf 'Run this command from the root of a Kicho project.\n' >&2
        exit 1
    fi
}

kicho_require_latexmk() {
    if ! command -v latexmk >/dev/null 2>&1; then
        kicho_error "'latexmk' is not installed or not available in PATH."
        exit 1
    fi
}

# Keep local package/class support with portable source snapshots.
kicho_copy_local_styles() {
    local destination="$1" source
    for source in ./*.sty ./*.cls ./*.bst; do
        if [[ -L "$source" ]]; then
            kicho_error "local style is a symbolic link: '$source'."
            return 1
        fi
        [[ -f "$source" ]] || continue
        cp "$source" "$destination/" || return 1
    done
    return 0
}

# Shared optional Python capability used by paraids, exports and provenance.
kicho_python_available() {
    command -v python3 >/dev/null 2>&1 &&
        python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1
}

kicho_require_python() {
    if ! kicho_python_available; then
        kicho_error 'Python 3.9 or later is required for paragraph-ID, archive, and submission operations.'
        return 1
    fi
}

kicho_copy_if_exists() {
    if [[ -e "$1" ]]; then
        cp -R "$1" "$2"
    else
        printf 'Warning: %s not found.\n' "$1" >&2
    fi
}
