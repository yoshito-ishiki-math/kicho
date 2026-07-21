# Implementation of `kicho build`.

build_project() {
    require_kicho_project
    require_latexmk

    printf 'Building project...\n'

    if latexmk; then
        printf 'Build completed successfully.\n'
    else
        local status=$?
        error "build failed."
        exit "$status"
    fi
}
