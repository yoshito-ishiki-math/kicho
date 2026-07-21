# Implementation of `kicho clean`.

clean_project() {
    require_kicho_project
    require_latexmk

    printf 'Cleaning project...\n'

    if latexmk -C; then
        rm -rf build
        printf 'Clean completed successfully.\n'
    else
        local status=$?
        error "clean failed."
        exit "$status"
    fi
}
