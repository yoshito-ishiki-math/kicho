# shellcheck shell=bash
# Implementation of `kicho check`.

kicho_command_check_summary() {
    printf 'Validate the current Kicho project.\n'
}

kicho_command_check_usage() {
    cat <<'USAGE'
Usage:
    kicho check [--log] [--json]

Check project files and literal TeX file references without building.
--log also summarizes undefined citations/references from the existing TeX log.
--json writes structured errors and warnings with source locations.
USAGE
}

kicho_command_check_accepts_arguments() {
    return 0
}

kicho_command_check_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho check
    kicho check --json
    kicho check --help
EXAMPLES
}

kicho_command_check() {
    local KICHO_SOURCE_JSON=false use_log=false option
    for option in "$@"; do
        case "$option" in
            --json)
                [[ "$KICHO_SOURCE_JSON" == false ]] || { kicho_error 'duplicate --json option.'; return 1; }
                KICHO_SOURCE_JSON=true ;;
            --log)
                [[ "$use_log" == false ]] || { kicho_error 'duplicate --log option.'; return 1; }
                use_log=true ;;
            *) kicho_error "check does not accept arguments other than '--json' and '--log'."; return 1 ;;
        esac
    done
    if ! kicho_project_load; then return 1; fi
    kicho_source_init

    if [[ "$KICHO_SOURCE_JSON" != true ]]; then
        printf 'Kicho check\n===========\n\nProject files\n'
    fi

    if [[ -f '.latexmkrc' ]]; then
        kicho_source_ok '.latexmkrc found.'
    else
        kicho_source_fail '.latexmkrc was not found.'
    fi

    if [[ -f "$KICHO_MAIN" ]]; then
        kicho_source_ok "$KICHO_MAIN found."
    else
        kicho_source_fail "$KICHO_MAIN was not found."
    fi

    if [[ -d 'bib' ]]; then
        kicho_source_ok 'bib directory found.'
    else
        kicho_source_warn 'bib directory was not found.'
    fi

    if [[ -d 'figures' ]]; then
        kicho_source_ok 'figures directory found.'
    else
        kicho_source_warn 'figures directory was not found.'
    fi

    if [[ -f "$KICHO_MAIN" ]]; then
        [[ "$KICHO_SOURCE_JSON" == true ]] || printf '\nReferences\n'
        kicho_source_scan_tex_file "$KICHO_SOURCE_ROOT/$KICHO_MAIN"
    fi

    if [[ "$use_log" == true ]]; then
        kicho_log_diagnostics
    fi
    if [[ "$KICHO_SOURCE_JSON" == true ]]; then
        kicho_source_write_json
        ((KICHO_SOURCE_ERRORS == 0))
        return
    fi
    printf '\nSummary\n'
    printf '  Errors:   %d\n' "$KICHO_SOURCE_ERRORS"
    printf '  Warnings: %d\n' "$KICHO_SOURCE_WARNINGS"

    if ((KICHO_SOURCE_ERRORS > 0)); then
        printf '\nKicho check found project errors.\n'
        return 1
    fi

    if ((KICHO_SOURCE_WARNINGS > 0)); then
        printf '\nProject checks passed, with warnings.\n'
        return 0
    fi

    printf '\nAll project checks passed.\n'
    return 0
}
