# Common constants and functions for Kicho.

readonly KICHO_VERSION="0.1.0"

kicho_error() {
    printf 'Error: %s\n' "$1" >&2
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
