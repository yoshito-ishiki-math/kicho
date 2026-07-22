# Implementation of `kicho clean`.

kicho_command_clean_summary() {
    printf 'Remove generated LaTeX files.\n'
}

kicho_command_clean() {
    kicho_require_project
    kicho_require_latexmk

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
