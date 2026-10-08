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

    local authored
    if [[ -d "$KICHO_BUILD_DIR" ]]; then
        authored="$(find "$KICHO_BUILD_DIR" -type f \( -name '*.tex' -o -name '*.bib' -o -name '*.sty' -o -name '*.cls' -o -name '*.bst' \) -print -quit)"
        if [[ -n "$authored" ]]; then
            kicho_error "build directory contains source files; clean refused: '$authored'."
            return 1
        fi
    fi
    if latexmk -C "-outdir=$KICHO_BUILD_DIR" "-auxdir=$KICHO_BUILD_DIR" "$KICHO_MAIN"; then
        rm -rf -- "$KICHO_BUILD_DIR"
        printf 'Clean completed successfully.\n'
    else
        local status=$?
        kicho_error "clean failed."
        exit "$status"
    fi
}
