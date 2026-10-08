# shellcheck shell=bash
# Implementation of `kicho build`.

kicho_command_build_summary() {
    printf 'Build the current LaTeX project.\n'
}

kicho_command_build_usage() {
    printf 'Usage:\n    kicho build [--strict]\n'
}

kicho_command_build_examples() {
    printf 'Examples:\n    kicho build\n    kicho build --strict\n'
}

kicho_command_build_accepts_arguments() {
    return 0
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

    local cache_directory="$PWD/$KICHO_BUILD_DIR/texmf-var"
    if ! mkdir -p "$cache_directory"; then
        kicho_error "could not create LuaTeX cache directory: '$cache_directory'."
        return 1
    fi

    export TEXMFVAR="$cache_directory"
    printf 'Using project LuaTeX cache:\n'
    printf '    %s\n' "$TEXMFVAR"
}

kicho_command_build() {
    local strict=false
    if [[ $# -eq 1 && "$1" == --strict ]]; then
        strict=true
    elif [[ $# -ne 0 ]]; then
        kicho_error "build does not accept arguments other than '--strict'."
        printf "Run 'kicho help build' for usage.\n" >&2
        return 1
    fi

    if ! kicho_build_prepare_texmfvar; then
        return 1
    fi

    printf 'Building project...\n'

    if latexmk -recorder "-outdir=$KICHO_BUILD_DIR" "-auxdir=$KICHO_BUILD_DIR" "$KICHO_MAIN"; then
        # Output controls are read by the shared scanner.
        # shellcheck disable=SC2034
        local KICHO_SOURCE_JSON=false KICHO_SOURCE_QUIET=false
        kicho_source_init
        kicho_log_diagnostics
        printf 'TeX log diagnostics: %d\n' "$KICHO_SOURCE_WARNINGS"
        if [[ "$strict" == true ]] && ((KICHO_SOURCE_WARNINGS > 0)); then
            kicho_error 'strict build requires a fresh log without unresolved citations or references.'
            return 1
        fi
        printf 'Build completed successfully.\n'
    else
        local status=$?
        kicho_error "build failed."
        exit "$status"
    fi
}
