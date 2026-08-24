# shellcheck shell=bash
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

kicho_build_prepare_texmfvar() {
    if [[ -n "${TEXMFVAR:-}" ]]; then
        printf 'Using configured LuaTeX cache:\n'
        printf '    %s\n' "$TEXMFVAR"
        return 0
    fi

    local cache_directory="$PWD/build/texmf-var"
    if ! mkdir -p "$cache_directory"; then
        kicho_error "could not create LuaTeX cache directory: '$cache_directory'."
        return 1
    fi

    export TEXMFVAR="$cache_directory"
    printf 'Using project LuaTeX cache:\n'
    printf '    %s\n' "$TEXMFVAR"
}

kicho_command_build() {
    if [[ $# -ne 0 ]]; then
        kicho_error "build does not accept arguments."
        printf "Run 'kicho help build' for usage.\n" >&2
        return 1
    fi

    if ! kicho_build_prepare_texmfvar; then
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
