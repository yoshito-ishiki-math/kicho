# shellcheck shell=bash
# Implementation of `kicho doctor`.

kicho_command_doctor_summary() {
    printf 'Check the Kicho installation, LaTeX environment, and current project.\n'
}

kicho_command_doctor_usage() {
    cat <<'USAGE'
Usage:
    kicho doctor
    kicho doctor --help

The doctor command can be run inside or outside a Kicho project.
USAGE
}

kicho_command_doctor_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho doctor
    kicho help doctor
EXAMPLES
}

kicho_doctor_ok() {
    printf '  OK    %s\n' "$1"
}

kicho_doctor_warn() {
    printf '  WARN  %s\n' "$1"
}

kicho_doctor_fail() {
    printf '  FAIL  %s\n' "$1"
}

kicho_doctor_check_command() {
    local command_name="$1"
    local command_path

    if command_path="$(command -v "$command_name" 2>/dev/null)"; then
        kicho_doctor_ok "$command_name: $command_path"
        return 0
    fi

    kicho_doctor_fail "$command_name was not found."
    return 1
}

kicho_command_doctor() {
    local failures=0
    local warnings=0
    local command_count=0

    case "${1:-}" in
        "")
            ;;

        -h|--help)
            kicho_show_command_help doctor
            return 0
            ;;

        *)
            kicho_error "doctor does not accept arguments."
            printf "Run 'kicho help doctor' for usage.\n" >&2
            return 1
            ;;
    esac

    printf 'Kicho doctor\n'
    printf '============\n'

    printf '\nKicho installation\n'

    if [[ -n "${KICHO_ROOT:-}" && -d "$KICHO_ROOT" ]]; then
        kicho_doctor_ok "Kicho root: $KICHO_ROOT"
    else
        kicho_doctor_fail 'Kicho root could not be determined.'
        ((failures += 1))
    fi

    if [[ -n "${KICHO_LIB_DIR:-}" && -d "$KICHO_LIB_DIR" ]]; then
        kicho_doctor_ok "Library directory: $KICHO_LIB_DIR"
    else
        kicho_doctor_fail 'Kicho library directory was not found.'
        ((failures += 1))
    fi

    if [[ -n "${KICHO_COMMAND_DIR:-}" && -d "$KICHO_COMMAND_DIR" ]]; then
        kicho_doctor_ok "Command directory: $KICHO_COMMAND_DIR"

        while IFS= read -r _command; do
            ((command_count += 1))
        done < <(kicho_command_names)

        kicho_doctor_ok "Loaded commands: $command_count"
    else
        kicho_doctor_fail 'Kicho command directory was not found.'
        ((failures += 1))
    fi

    if [[ -n "${KICHO_ROOT:-}" && -x "$KICHO_ROOT/bin/kicho" ]]; then
        kicho_doctor_ok "Executable: $KICHO_ROOT/bin/kicho"
    else
        kicho_doctor_fail 'The Kicho executable was not found or is not executable.'
        ((failures += 1))
    fi

    if [[ -n "${KICHO_ROOT:-}" && -d "$KICHO_ROOT/templates" ]]; then
        kicho_doctor_ok "Template directory: $KICHO_ROOT/templates"
    else
        kicho_doctor_warn 'Template directory was not found.'
        ((warnings += 1))
    fi

    printf '\nRequired environment\n'

    if ! kicho_doctor_check_command bash; then
        ((failures += 1))
    fi

    if ! kicho_doctor_check_command latexmk; then
        ((failures += 1))
    fi

    if ! kicho_doctor_check_command lualatex; then
        ((failures += 1))
    fi

    if ! kicho_doctor_check_command biber; then
        ((failures += 1))
    fi

    printf '\nOptional environment\n'

    if command -v git >/dev/null 2>&1; then
        kicho_doctor_ok "git: $(command -v git)"
    else
        kicho_doctor_warn 'git was not found.'
        ((warnings += 1))
    fi

    printf '\nCurrent directory\n'
    printf '  Path:  %s\n' "$PWD"

    local project_markers=0

    if [[ -f ".latexmkrc" ]]; then
        kicho_doctor_ok '.latexmkrc found.'
        ((project_markers += 1))
    else
        kicho_doctor_warn '.latexmkrc was not found.'
        ((warnings += 1))
    fi

    if [[ -f "main.tex" ]]; then
        kicho_doctor_ok 'main.tex found.'
        ((project_markers += 1))
    else
        kicho_doctor_warn 'main.tex was not found.'
        ((warnings += 1))
    fi

    if [[ -d "bib" ]]; then
        kicho_doctor_ok 'bib directory found.'
    else
        kicho_doctor_warn 'bib directory was not found.'
        ((warnings += 1))
    fi

    if [[ -d "build" ]]; then
        kicho_doctor_ok 'build directory found.'
    else
        kicho_doctor_warn 'build directory was not found.'
        ((warnings += 1))
    fi

    if ((project_markers == 0)); then
        printf '\n'
        kicho_doctor_warn 'The current directory does not appear to be a Kicho project.'
    elif ((project_markers < 2)); then
        printf '\n'
        kicho_doctor_warn 'The current directory appears to be an incomplete Kicho project.'
    else
        printf '\n'
        kicho_doctor_ok 'The current directory appears to be a Kicho project.'
    fi

    printf '\nSummary\n'
    printf '  Failures: %d\n' "$failures"
    printf '  Warnings: %d\n' "$warnings"

    if ((failures > 0)); then
        printf '\nKicho doctor found required problems.\n'
        return 1
    fi

    if ((warnings > 0)); then
        printf '\nRequired checks passed, with warnings.\n'
        return 0
    fi

    printf '\nAll checks passed.\n'
    return 0
}
