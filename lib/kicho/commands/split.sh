# Implementation of `kicho split`.

kicho_command_split_summary() {
    printf 'Split a single-file project into multiple files.\n'
}

kicho_command_split_usage() {
    cat <<'USAGE'
Usage:
    kicho split
USAGE
}

kicho_command_split_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho split
EXAMPLES
}

kicho_command_split_requires_project() {
    return 0
}

kicho_command_split() {
    if [[ $# -ne 0 ]]; then
        kicho_error "split does not accept arguments."
        printf "Run 'kicho help split' for usage.\n" >&2
        return 1
    fi

    printf 'split: not implemented yet.\n'
}
