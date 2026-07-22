# Implementation of `kicho flatten`.

kicho_command_flatten_summary() {
    printf 'Merge a multi-file project into a single file.\n'
}

kicho_command_flatten_usage() {
    cat <<'USAGE'
Usage:
    kicho flatten
USAGE
}

kicho_command_flatten_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho flatten
EXAMPLES
}

kicho_command_flatten_requires_project() {
    return 0
}

kicho_command_flatten() {
    if [[ $# -ne 0 ]]; then
        kicho_error "flatten does not accept arguments."
        printf "Run 'kicho help flatten' for usage.\n" >&2
        return 1
    fi

    printf 'flatten: not implemented yet.\n'
}
