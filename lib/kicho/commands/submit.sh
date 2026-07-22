# Implementation of `kicho submit`.

kicho_command_submit_summary() {
    printf 'Prepare a submission package.\n'
}

kicho_command_submit_usage() {
    cat <<'USAGE'
Usage:
    kicho submit
USAGE
}

kicho_command_submit_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho submit
EXAMPLES
}

kicho_command_submit_requires_project() {
    return 0
}

kicho_command_submit() {
    if [[ $# -ne 0 ]]; then
        kicho_error "submit does not accept arguments."
        printf "Run 'kicho help submit' for usage.\n" >&2
        return 1
    fi

    printf 'submit: not implemented yet.\n'
}
