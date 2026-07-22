# Implementation of `kicho build`.

kicho_command_build_summary() {
    printf 'Build the current LaTeX project.\n'
}

kicho_command_build_usage() {
    printf 'Usage:\n    kicho build\n'
}

kicho_command_build_examples() {
    printf 'Examples:\n    kicho build\n'
}

kicho_command_build_requires_project() {
    return 0
}

kicho_command_build_requires_latexmk() {
    return 0
}

kicho_command_build() {
    if [[ $# -ne 0 ]]; then
        kicho_error "build does not accept arguments."
        printf "Run 'kicho help build' for usage.\n" >&2
        return 1
    fi

    printf 'Building project...\n'

    if latexmk; then
        printf 'Build completed successfully.\n'
    else
        local status=$?
        kicho_error "build failed."
        exit "$status"
    fi
}
