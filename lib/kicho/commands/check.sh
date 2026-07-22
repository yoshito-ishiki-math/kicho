# shellcheck shell=bash
# Implementation of `kicho check`.

kicho_command_check_summary() {
    printf 'Validate the current Kicho project.\n'
}

kicho_command_check_usage() {
    cat <<'USAGE'
Usage:
    kicho check

Check project files and literal TeX file references without building.
USAGE
}

kicho_command_check_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho check
    kicho check --help
EXAMPLES
}

kicho_check_ok() {
    printf '  OK    %s\n' "$1"
}

kicho_check_warn() {
    printf '  WARN  %s\n' "$1"
    KICHO_CHECK_WARNINGS=$((KICHO_CHECK_WARNINGS + 1))
}

kicho_check_fail() {
    printf '  FAIL  %s\n' "$1"
    KICHO_CHECK_ERRORS=$((KICHO_CHECK_ERRORS + 1))
}

kicho_check_is_dynamic_reference() {
    case "$1" in
        *\\*|*'#'*|*'$'*|*'{'*|*'}'*) return 0 ;;
        *) return 1 ;;
    esac
}

kicho_check_prepare_reference() {
    local reference="$1"
    local kind="$2"

    while [[ "$reference" == ./* ]]; do
        reference="${reference#./}"
    done

    case "$kind" in
        input)
            case "${reference##*/}" in
                *.*) ;;
                *) reference+='.tex' ;;
            esac
            ;;
        bib)
            case "$reference" in
                *.bib) ;;
                *) reference+='.bib' ;;
            esac
            ;;
    esac

    printf '%s\n' "$reference"
}

kicho_check_resolve_reference() {
    local reference="$1"
    local kind="$2"
    local prepared
    local directory
    local filename
    local physical_directory

    KICHO_CHECK_RESOLVED=''

    if kicho_check_is_dynamic_reference "$reference"; then
        kicho_check_warn "dynamic $kind reference was not checked: '$reference'."
        return 2
    fi

    case "$reference" in
        /*)
            kicho_check_fail "absolute $kind reference is not allowed: '$reference'."
            return 1
            ;;
    esac

    case "/$reference/" in
        */../*)
            kicho_check_fail "parent-path $kind reference is not allowed: '$reference'."
            return 1
            ;;
    esac

    prepared="$(kicho_check_prepare_reference "$reference" "$kind")"

    directory="${prepared%/*}"
    filename="${prepared##*/}"
    if [[ "$directory" == "$prepared" ]]; then
        directory='.'
    fi

    if ! physical_directory="$(cd -- "$directory" 2>/dev/null && pwd -P)"; then
        kicho_check_fail "$kind file was not found: '$prepared'."
        return 1
    fi

    case "$physical_directory" in
        "$KICHO_CHECK_ROOT"|"$KICHO_CHECK_ROOT"/*) ;;
        *)
            kicho_check_fail "$kind reference resolves outside the project: '$reference'."
            return 1
            ;;
    esac

    if [[ -L "$prepared" ]]; then
        kicho_check_fail "$kind reference is a symbolic link: '$prepared'."
        return 1
    fi

    if [[ -f "$physical_directory/$filename" ]]; then
        KICHO_CHECK_RESOLVED="$physical_directory/$filename"
        return 0
    fi

    if [[ "$kind" == "figure" && "${prepared##*/}" != *.* ]]; then
        local extension
        for extension in pdf png jpg jpeg eps; do
            if [[ -L "$prepared.$extension" ]]; then
                kicho_check_fail "figure reference is a symbolic link: '$prepared.$extension'."
                return 1
            fi

            if [[ -f "$physical_directory/$filename.$extension" ]]; then
                KICHO_CHECK_RESOLVED="$physical_directory/$filename.$extension"
                return 0
            fi
        done
    fi

    kicho_check_fail "$kind file was not found: '$prepared'."
    return 1
}

kicho_check_scan_line_reference() {
    local line="$1"
    local pattern="$2"
    local kind="$3"
    local reference

    if [[ "$line" =~ $pattern ]]; then
        reference="${BASH_REMATCH[2]}"
        if kicho_check_resolve_reference "$reference" "$kind"; then
            kicho_check_ok "$kind: $reference"
            if [[ "$kind" == "input" ]]; then
                kicho_check_scan_tex_file "$KICHO_CHECK_RESOLVED"
            fi
        fi
    fi

    return 0
}

kicho_check_scan_bibliography() {
    local value="$1"
    local reference
    local references=()
    local IFS=','

    read -r -a references <<< "$value"
    for reference in "${references[@]}"; do
        reference="${reference#"${reference%%[![:space:]]*}"}"
        reference="${reference%"${reference##*[![:space:]]}"}"
        if [[ -z "$reference" ]]; then
            kicho_check_warn 'empty bibliography reference was not checked.'
        elif kicho_check_resolve_reference "$reference" bib; then
            kicho_check_ok "bibliography: $reference"
        fi
    done
}

kicho_check_scan_tex_file() {
    local source_file="$1"
    local relative_file="${source_file#"$KICHO_CHECK_ROOT/"}"
    local line
    local input_pattern='\\(input|include)[[:space:]]*\{([^{}]+)\}'
    local addbib_pattern='\\addbibresource([[:space:]]*\[[^]]*\])?[[:space:]]*\{([^{}]+)\}'
    local bibliography_pattern='\\bibliography[[:space:]]*\{([^{}]+)\}'
    local figure_pattern='\\includegraphics([[:space:]]*\[[^]]*\])?[[:space:]]*\{([^{}]+)\}'

    if [[ "$KICHO_CHECK_VISITED" == *"|$source_file|"* ]]; then
        return 0
    fi
    KICHO_CHECK_VISITED+="|$source_file|"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%\%*}"

        kicho_check_scan_line_reference "$line" "$input_pattern" input || true

        if [[ "$line" =~ $addbib_pattern ]]; then
            kicho_check_scan_bibliography "${BASH_REMATCH[2]}"
        elif [[ "$line" =~ $bibliography_pattern ]]; then
            kicho_check_scan_bibliography "${BASH_REMATCH[1]}"
        fi

        if [[ "$line" =~ $figure_pattern ]]; then
            local figure_reference="${BASH_REMATCH[2]}"
            if kicho_check_resolve_reference "$figure_reference" figure; then
                kicho_check_ok "figure: $figure_reference"
            fi
        fi
    done < "$relative_file"
}

kicho_command_check() {
    if [[ $# -ne 0 ]]; then
        kicho_error "check does not accept arguments."
        printf "Run 'kicho help check' for usage.\n" >&2
        return 1
    fi

    KICHO_CHECK_ERRORS=0
    KICHO_CHECK_WARNINGS=0
    KICHO_CHECK_VISITED=''
    KICHO_CHECK_ROOT="$(pwd -P)"

    printf 'Kicho check\n'
    printf '===========\n'
    printf '\nProject files\n'

    if [[ -f '.latexmkrc' ]]; then
        kicho_check_ok '.latexmkrc found.'
    else
        kicho_check_fail '.latexmkrc was not found.'
    fi

    if [[ -f 'main.tex' ]]; then
        kicho_check_ok 'main.tex found.'
    else
        kicho_check_fail 'main.tex was not found.'
    fi

    if [[ -d 'bib' ]]; then
        kicho_check_ok 'bib directory found.'
    else
        kicho_check_warn 'bib directory was not found.'
    fi

    if [[ -d 'figures' ]]; then
        kicho_check_ok 'figures directory found.'
    else
        kicho_check_warn 'figures directory was not found.'
    fi

    if [[ -f 'main.tex' ]]; then
        printf '\nReferences\n'
        kicho_check_scan_tex_file "$KICHO_CHECK_ROOT/main.tex"
    fi

    printf '\nSummary\n'
    printf '  Errors:   %d\n' "$KICHO_CHECK_ERRORS"
    printf '  Warnings: %d\n' "$KICHO_CHECK_WARNINGS"

    if ((KICHO_CHECK_ERRORS > 0)); then
        printf '\nKicho check found project errors.\n'
        return 1
    fi

    if ((KICHO_CHECK_WARNINGS > 0)); then
        printf '\nProject checks passed, with warnings.\n'
        return 0
    fi

    printf '\nAll project checks passed.\n'
    return 0
}
