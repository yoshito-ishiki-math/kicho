# shellcheck shell=bash
# Implementation of `kicho clean`.

kicho_command_clean_summary() {
    printf 'Remove generated LaTeX files.\n'
}

kicho_command_clean_usage() {
    printf 'Usage:\n    kicho clean\n'
}

kicho_command_clean_examples() {
    printf 'Examples:\n    kicho clean\n'
}

kicho_command_clean_requires_project() {
    return 0
}

kicho_command_clean_requires_latexmk() {
    return 0
}

kicho_command_clean() {
    if [[ $# -ne 0 ]]; then
        kicho_error "clean does not accept arguments."
        printf "Run 'kicho help clean' for usage.\n" >&2
        return 1
    fi

    printf 'Cleaning project...\n'

    if latexmk -C; then
        rm -rf build
        printf 'Clean completed successfully.\n'
    else
        local status=$?
        kicho_error "clean failed."
        exit "$status"
    fi
}
