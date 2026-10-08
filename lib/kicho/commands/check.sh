# shellcheck shell=bash
# Implementation of `kicho check`.

kicho_command_check_summary() {
    printf 'Validate the current Kicho project.\n'
}

kicho_command_check_usage() {
    cat <<'USAGE'
Usage:
    kicho check [--json]

Check project files and literal TeX file references without building.
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

kicho_check_ok() {
    [[ "${KICHO_CHECK_QUIET:-false}" == true ]] && return 0
    [[ "${KICHO_CHECK_JSON:-false}" == true ]] && return 0
    printf '  OK    %s\n' "$1"
}

kicho_check_diagnostic() {
    local severity="$1" message="$2" file_json=null line_json=null location=''
    if [[ -n "${KICHO_CHECK_SOURCE_FILE:-}" ]]; then
        location="${KICHO_CHECK_SOURCE_FILE#"$KICHO_CHECK_ROOT/"}"
        file_json="\"$(kicho_json_escape "$location")\""
        if [[ "${KICHO_CHECK_SOURCE_LINE:-0}" -gt 0 ]]; then
            line_json="$KICHO_CHECK_SOURCE_LINE"
            location+=":$KICHO_CHECK_SOURCE_LINE"
        fi
        location+=': '
    fi
    KICHO_CHECK_DIAGNOSTICS+=("{\"severity\":\"$severity\",\"message\":\"$(kicho_json_escape "$message")\",\"file\":$file_json,\"line\":$line_json}")
    if [[ "${KICHO_CHECK_JSON:-false}" != true ]]; then
        local label=WARN
        [[ "$severity" == error ]] && label=FAIL
        printf '  %s  %s%s\n' "$label" "$location" "$message"
    fi
}

kicho_check_warn() {
    local KICHO_CHECK_SOURCE_LINE="${2:-${KICHO_CHECK_SOURCE_LINE:-0}}"
    KICHO_CHECK_WARNINGS=$((KICHO_CHECK_WARNINGS + 1))
    kicho_check_diagnostic warning "$1"
}

kicho_check_fail() {
    KICHO_CHECK_ERRORS=$((KICHO_CHECK_ERRORS + 1))
    kicho_check_diagnostic error "$1"
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
        package) [[ "$reference" == *.sty ]] || reference+='.sty' ;;
        class) [[ "$reference" == *.cls ]] || reference+='.cls' ;;
        bst) [[ "$reference" == *.bst ]] || reference+='.bst' ;;
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

    if kicho_path_has_parent_component "$reference"; then
        kicho_check_fail "parent-path $kind reference is not allowed: '$reference'."
        return 1
    fi

    prepared="$(kicho_check_prepare_reference "$reference" "$kind")"

    local candidate graphics_path extension
    local candidates=("$prepared")
    if [[ "$kind" == figure ]]; then
        for graphics_path in "${KICHO_CHECK_GRAPHICS_PATHS[@]}"; do
            candidates+=("${graphics_path%/}/$prepared")
        done
    fi
    for candidate in "${candidates[@]}"; do
        if [[ "$candidate" == /* ]] || kicho_path_has_parent_component "$candidate"; then
            kicho_check_fail "unsafe $kind search path: '$candidate'."
            return 1
        fi
        directory="${candidate%/*}"
        filename="${candidate##*/}"
        [[ "$directory" != "$candidate" ]] || directory='.'
        if ! physical_directory="$(cd -- "$directory" 2>/dev/null && pwd -P)"; then
            continue
        fi
        if ! kicho_path_is_within_root "$KICHO_CHECK_ROOT" "$physical_directory"; then
            kicho_check_fail "$kind reference resolves outside the project: '$candidate'."
            return 1
        fi
        if [[ -L "$candidate" ]]; then
            kicho_check_fail "$kind reference is a symbolic link: '$candidate'."
            return 1
        fi
        if [[ -f "$physical_directory/$filename" ]]; then
            KICHO_CHECK_RESOLVED="$physical_directory/$filename"
        elif [[ "$kind" == figure && "$filename" != *.* ]]; then
            for extension in pdf png jpg jpeg eps; do
                if [[ -L "$candidate.$extension" ]]; then
                    kicho_check_fail "figure reference is a symbolic link: '$candidate.$extension'."
                    return 1
                fi
                if [[ -f "$physical_directory/$filename.$extension" ]]; then
                    KICHO_CHECK_RESOLVED="$physical_directory/$filename.$extension"
                    break
                fi
            done
        fi
        if [[ -n "$KICHO_CHECK_RESOLVED" ]]; then
            KICHO_CHECK_FILES+=("$KICHO_CHECK_RESOLVED")
            KICHO_CHECK_KINDS+=("$kind")
            return 0
        fi
    done

    if [[ "$kind" == figure && "${KICHO_CHECK_GRAPHICS_DYNAMIC:-false}" == true ]]; then
        kicho_check_warn "figure search path is dynamic; '$reference' was not checked."
        return 2
    fi
    kicho_check_fail "$kind file was not found: '$prepared'."
    return 1
}

kicho_check_scan_graphicspath() {
    local text="$1" paths path
    local KICHO_CHECK_SOURCE_LINE="${2:-${KICHO_CHECK_SOURCE_LINE:-0}}"
    local pattern='\\graphicspath[[:space:]]*\{((\{[^{}]*\}[[:space:]]*)*)\}'
    local item_pattern='\{([^{}]*)\}'
    if [[ ! "$text" =~ $pattern ]]; then
        return 1
    fi
    paths="${BASH_REMATCH[1]}"
    KICHO_CHECK_GRAPHICS_PATHS=()
    KICHO_CHECK_GRAPHICS_DYNAMIC=false
    while [[ "$paths" =~ $item_pattern ]]; do
        path="${BASH_REMATCH[1]}"
        paths="${paths#*"${BASH_REMATCH[0]}"}"
        if kicho_check_is_dynamic_reference "$path"; then
            KICHO_CHECK_GRAPHICS_DYNAMIC=true
            kicho_check_warn "dynamic graphicspath was not checked: '$path'."
        elif [[ -n "$path" ]]; then
            KICHO_CHECK_GRAPHICS_PATHS+=("$path")
        fi
    done
    return 0
}

kicho_check_scan_local_styles() {
    local line="$1" command value reference prepared kind
    local pattern='\\(usepackage|RequirePackageWithOptions|RequirePackage|documentclass|LoadClassWithOptions|LoadClass|bibliographystyle)([[:space:]]*\[[^]]*\])?[[:space:]]*\{([^{}]+)\}'
    local references=()
    while [[ "$line" =~ $pattern ]]; do
        command="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[3]}"
        line="${line#*"${BASH_REMATCH[0]}"}"
        case "$command" in
            documentclass|LoadClass*) kind=class ;;
            bibliographystyle) kind=bst ;;
            *) kind=package ;;
        esac
        IFS=',' read -r -a references <<< "$value"
        for reference in "${references[@]}"; do
            reference="${reference#"${reference%%[![:space:]]*}"}"
            reference="${reference%"${reference##*[![:space:]]}"}"
            prepared="$(kicho_check_prepare_reference "$reference" "$kind")"
            # Bare names absent from the project belong to the TeX installation.
            if [[ "$reference" != */* && ! -e "$prepared" && ! -L "$prepared" ]]; then
                continue
            fi
            if kicho_check_resolve_reference "$reference" "$kind"; then
                kicho_check_ok "$kind: $reference"
                [[ "$kind" == bst ]] || kicho_check_scan_tex_file "$KICHO_CHECK_RESOLVED" "$kind"
            fi
        done
    done
    return 0
}

kicho_check_scan_line_reference() {
    local line="$1"
    local pattern="$2"
    local kind="$3"
    local reference

    while [[ "$line" =~ $pattern ]]; do
        reference="${BASH_REMATCH[2]}"
        # Save the unscanned suffix before recursive checks replace BASH_REMATCH.
        line="${line#*"${BASH_REMATCH[0]}"}"
        if kicho_check_resolve_reference "$reference" "$kind"; then
            kicho_check_ok "$kind: $reference"
            if [[ "$kind" == "input" ]]; then
                kicho_check_scan_tex_file "$KICHO_CHECK_RESOLVED"
            fi
        fi
    done

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
    local edge_kind="${2:-input}"
    local line
    local input_pattern='\\(input|include)[[:space:]]*\{([^{}]+)\}'
    local addbib_pattern='\\addbibresource([[:space:]]*\[[^]]*\])?[[:space:]]*\{([^{}]+)\}'
    local bibliography_pattern='\\bibliography([[:space:]]*)\{([^{}]+)\}'
    local usage_pattern='\\(addbibresource|bibliography|printbibliography)(\{|\[|[[:space:]]|$)'
    local figure_pattern='\\includegraphics([[:space:]]*\[[^]]*\])?[[:space:]]*\{([^{}]+)\}'

    if [[ "${KICHO_CHECK_STACK:-}" == *"|$source_file|"* && "$edge_kind" == input ]]; then
        kicho_check_fail "input/include cycle detected at '${source_file#"$KICHO_CHECK_ROOT/"}'."
        return 0
    fi
    if [[ "$KICHO_CHECK_VISITED" == *"|$source_file|"* ]]; then
        return 0
    fi
    KICHO_CHECK_VISITED+="|$source_file|"
    local KICHO_CHECK_STACK="${KICHO_CHECK_STACK:-}|$source_file|"
    local KICHO_CHECK_SOURCE_FILE="$source_file" KICHO_CHECK_SOURCE_LINE=0
    local graphics_pending='' graphics_start=0
    local graphics_command='\\graphicspath[[:space:]]*\{'
    local graphics_dynamic='\\graphicspath[[:space:]]*\{[^{}]*\}'

    while IFS= read -r line || [[ -n "$line" ]]; do
        KICHO_CHECK_SOURCE_LINE=$((KICHO_CHECK_SOURCE_LINE + 1))
        if [[ -n "$graphics_pending" ]]; then
            graphics_pending+=" $line"
        elif [[ "$line" =~ $graphics_command ]]; then
            graphics_pending="$line"
            graphics_start="$KICHO_CHECK_SOURCE_LINE"
        fi
        if [[ -n "$graphics_pending" ]]; then
            if kicho_check_scan_graphicspath "$graphics_pending" "$graphics_start"; then
                graphics_pending=''
            elif [[ "$graphics_pending" =~ $graphics_dynamic ]]; then
                KICHO_CHECK_GRAPHICS_DYNAMIC=true
                KICHO_CHECK_GRAPHICS_PATHS=()
                kicho_check_warn 'macro-generated graphicspath was not checked.' "$graphics_start"
                graphics_pending=''
            fi
        fi
        if [[ "$line" =~ $usage_pattern ]]; then
            KICHO_CHECK_USES_BIBLIOGRAPHY=true
        fi
        kicho_check_scan_line_reference "$line" "$input_pattern" input || true
        kicho_check_scan_local_styles "$line"

        local remaining="$line"
        while [[ "$remaining" =~ $addbib_pattern ]]; do
            local value="${BASH_REMATCH[2]}"
            remaining="${remaining#*"${BASH_REMATCH[0]}"}"
            kicho_check_scan_bibliography "$value"
        done
        remaining="$line"
        while [[ "$remaining" =~ $bibliography_pattern ]]; do
            local value="${BASH_REMATCH[2]}"
            remaining="${remaining#*"${BASH_REMATCH[0]}"}"
            kicho_check_scan_bibliography "$value"
        done

        kicho_check_scan_line_reference "$line" "$figure_pattern" figure || true
    done < <(kicho_tex_active_file "$source_file")
    if [[ -n "$graphics_pending" ]]; then
        KICHO_CHECK_SOURCE_LINE="$graphics_start"
        KICHO_CHECK_GRAPHICS_DYNAMIC=true
        kicho_check_warn 'unsupported or unclosed graphicspath was not checked.'
    fi
    return 0
}

kicho_check_write_json() {
    local record separator=''
    printf '{"schema_version":1,"errors":%d,"warnings":%d,"diagnostics":[' \
        "$KICHO_CHECK_ERRORS" "$KICHO_CHECK_WARNINGS"
    for record in "${KICHO_CHECK_DIAGNOSTICS[@]}"; do
        printf '%s%s' "$separator" "$record"
        separator=,
    done
    printf ']}\n'
}

kicho_command_check() {
    local KICHO_CHECK_JSON=false
    if [[ $# -eq 1 && "$1" == --json ]]; then
        KICHO_CHECK_JSON=true
    elif [[ $# -ne 0 ]]; then
        kicho_error "check does not accept arguments other than '--json'."
        printf "Run 'kicho help check' for usage.\n" >&2
        return 1
    fi

    KICHO_CHECK_FILES=()
    KICHO_CHECK_KINDS=()
    KICHO_CHECK_ERRORS=0
    KICHO_CHECK_WARNINGS=0
    KICHO_CHECK_VISITED=''
    KICHO_CHECK_STACK=''
    KICHO_CHECK_DIAGNOSTICS=()
    KICHO_CHECK_GRAPHICS_PATHS=()
    KICHO_CHECK_GRAPHICS_DYNAMIC=false
    KICHO_CHECK_USES_BIBLIOGRAPHY=false
    local KICHO_CHECK_SOURCE_FILE='' KICHO_CHECK_SOURCE_LINE=0
    KICHO_CHECK_ROOT="$(pwd -P)"

    if [[ "$KICHO_CHECK_JSON" != true ]]; then
        printf 'Kicho check\n===========\n\nProject files\n'
    fi

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
        [[ "$KICHO_CHECK_JSON" == true ]] || printf '\nReferences\n'
        kicho_check_scan_tex_file "$KICHO_CHECK_ROOT/main.tex"
    fi

    if [[ "$KICHO_CHECK_JSON" == true ]]; then
        kicho_check_write_json
        ((KICHO_CHECK_ERRORS == 0))
        return
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

# Resolve in the live project before copying, never in the destination tree.
kicho_copy_source_dependencies() {
    local destination="$1" mode="$2"
    local KICHO_CHECK_QUIET=true KICHO_CHECK_USES_BIBLIOGRAPHY=false
    local KICHO_CHECK_JSON=false KICHO_CHECK_DIAGNOSTICS=()
    local KICHO_CHECK_GRAPHICS_PATHS=() KICHO_CHECK_GRAPHICS_DYNAMIC=false
    local KICHO_CHECK_STACK='' KICHO_CHECK_SOURCE_FILE='' KICHO_CHECK_SOURCE_LINE=0
    local KICHO_CHECK_ROOT KICHO_CHECK_VISITED='' KICHO_CHECK_RESOLVED=''
    local KICHO_CHECK_ERRORS=0 KICHO_CHECK_WARNINGS=0
    local KICHO_CHECK_FILES=() KICHO_CHECK_KINDS=()
    KICHO_CHECK_ROOT="$(pwd -P)"
    if [[ -f main.tex ]]; then
        kicho_check_scan_tex_file "$KICHO_CHECK_ROOT/main.tex" >&2
    fi
    if ((KICHO_CHECK_ERRORS > 0)) && [[ "$mode" != archive ]]; then
        kicho_error 'submission has missing or unsafe source dependencies.'
        return 1
    fi
    if [[ "$mode" == arxiv && "$KICHO_CHECK_USES_BIBLIOGRAPHY" == true && ! -f build/main.bbl ]]; then
        kicho_error 'build/main.bbl was not found for an included document that uses a bibliography.'
        return 1
    fi
    local i file relative
    for ((i=0; i<${#KICHO_CHECK_FILES[@]}; i++)); do
        [[ "$mode" == arxiv && "${KICHO_CHECK_KINDS[i]}" == bib ]] && continue
        file="${KICHO_CHECK_FILES[i]}"
        relative="${file#"$KICHO_CHECK_ROOT/"}"
        # main.tex in submission is the flattened document.
        [[ "$relative" == main.tex ]] && continue
        if ! kicho_prepare_dependency_destination "$destination" "$relative" ||
            ! cp "$file" "$destination/$relative"; then
            kicho_error "could not preserve dependency: '$relative'."
            return 1
        fi
    done
    kicho_copy_recorded_dependencies "$destination" "$mode" || return 1
    return 0
}

kicho_submit_warn_stale_output() {
    local output="$1" root file
    [[ -f "$output" ]] || return 0
    root="$(pwd -P)"
    local KICHO_CHECK_ROOT="$root" KICHO_CHECK_VISITED='' KICHO_CHECK_STACK=''
    local KICHO_CHECK_SOURCE_FILE='' KICHO_CHECK_SOURCE_LINE=0 KICHO_CHECK_RESOLVED=''
    local KICHO_CHECK_JSON=true KICHO_CHECK_QUIET=true KICHO_CHECK_DIAGNOSTICS=()
    local KICHO_CHECK_ERRORS=0 KICHO_CHECK_WARNINGS=0 KICHO_CHECK_USES_BIBLIOGRAPHY=false
    local KICHO_CHECK_GRAPHICS_PATHS=() KICHO_CHECK_GRAPHICS_DYNAMIC=false
    local KICHO_CHECK_FILES=() KICHO_CHECK_KINDS=() KICHO_RECORDED_FILES=()
    if [[ -f main.tex ]]; then kicho_check_scan_tex_file "$root/main.tex"; fi
    kicho_collect_recorded_dependencies || return 1
    for file in main.tex .latexmkrc "${KICHO_CHECK_FILES[@]}" "${KICHO_RECORDED_FILES[@]}"; do
        if [[ -f "$file" && "$file" -nt "$output" ]]; then
            printf "Warning: '%s' may be stale; '%s' is newer. Run 'kicho submit --build' to refresh outputs.\n" \
                "$output" "${file#"$root/"}" >&2
            return 0
        fi
    done
    return 0
}
