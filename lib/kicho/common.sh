# shellcheck shell=bash
# Common constants and functions for Kicho.

readonly KICHO_VERSION="0.2.0-alpha.3"

kicho_error() {
    printf 'Error: %s\n' "$1" >&2
}

# Under ordinary TeX catcodes, a backslash consumes the following control
# symbol. Thus an odd run of backslashes escapes %, while an even run does not.
kicho_tex_strip_comment() {
    local text="$1"
    local result=""
    local character
    while [[ -n "$text" ]]; do
        character="${text:0:1}"
        text="${text:1}"
        case "$character" in
            '%') break ;;
            \\)
                result+="$character"
                if [[ -n "$text" ]]; then
                    result+="${text:0:1}"
                    text="${text:1}"
                fi
                ;;
            *) result+="$character" ;;
        esac
    done
    printf '%s\n' "$result"
}

kicho_tex_literal_environment() {
    local pattern='\\begin[[:space:]]*\{(verbatim\*?|Verbatim\*?|BVerbatim|LVerbatim|lstlisting|minted)\}'
    if [[ "$1" =~ $pattern ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

kicho_show_version() {
    printf 'kicho %s\n' "$KICHO_VERSION"
}

kicho_show_help() {
    cat <<'EOF'
Kicho — Workflow manager for LaTeX research projects.

Usage:
    kicho COMMAND [ARGS]
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
