# Implementation of `kicho build`.

kicho_command_build_summary() {
    printf 'Build the current LaTeX project.\n'
}

kicho_command_build() {
    kicho_require_project
    kicho_require_latexmk

    printf 'Building project...\n'

    if latexmk; then
        printf 'Build completed successfully.\n'
    else
        local status=$?
        kicho_error "build failed."
        exit "$status"
    fi
}
