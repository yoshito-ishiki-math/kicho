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

    local authored file root
    root="$(pwd -P)"
    if [[ -d "$KICHO_BUILD_DIR" ]]; then
        if ! authored="$(find "$KICHO_BUILD_DIR" -type f \( -name '*.tex' -o -name '*.bib' -o -name '*.sty' -o -name '*.cls' -o -name '*.bst' \) -print -quit)"; then
            kicho_error 'could not inspect the build directory; clean refused.'
            return 1
        fi
        if [[ -n "$authored" ]]; then
            kicho_error "build directory contains source files; clean refused: '$authored'."
            return 1
        fi
    fi
    kicho_dependencies_collect quiet || return 1
    if ((KICHO_DEPENDENCY_ERRORS > 0)); then
        kicho_error 'could not establish source dependency safety; clean refused.'
        return 1
    fi
    for file in "${KICHO_DEPENDENCY_FILES[@]}"; do
        if [[ "$file" == "$root/$KICHO_BUILD_DIR/"* ]]; then
            kicho_error "build directory contains a source dependency; clean refused: '${file#"$root/"}'."
            return 1
        fi
    done
    if latexmk -C "-outdir=$KICHO_BUILD_DIR" "-auxdir=$KICHO_BUILD_DIR" "$KICHO_MAIN"; then
        if [[ -d "$KICHO_BUILD_DIR" ]]; then
            find "$KICHO_BUILD_DIR" -depth -type d -empty -exec rmdir {} \; || return 1
            if [[ -d "$KICHO_BUILD_DIR" ]]; then
                printf 'Retained other files or cached data in %s.\n' "$KICHO_BUILD_DIR"
            fi
        fi
        printf 'Clean completed successfully.\n'
    else
        local status=$?
        kicho_error "clean failed."
        exit "$status"
    fi
}
