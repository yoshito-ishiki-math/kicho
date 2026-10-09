# shellcheck shell=bash
# Ordered traversal of supported literal TeX references and diagnostics.

kicho_source_init() {
    KICHO_SOURCE_FILES=()
    KICHO_SOURCE_KINDS=()
    KICHO_SOURCE_ERRORS=0
    KICHO_SOURCE_WARNINGS=0
    KICHO_SOURCE_VISITED=''
    KICHO_SOURCE_STACK=''
    KICHO_SOURCE_DIAGNOSTICS=()
    KICHO_SOURCE_GRAPHICS_PATHS=()
    KICHO_SOURCE_GRAPHICS_DYNAMIC=false
    KICHO_SOURCE_GROUP_COUNTS=()
    KICHO_SOURCE_GROUP_PATHS=()
    KICHO_SOURCE_GROUP_DYNAMIC=()
    KICHO_SOURCE_USES_BIBLIOGRAPHY=false
    KICHO_SOURCE_FILE=''
    KICHO_SOURCE_LINE=0
    KICHO_SOURCE_ROOT="$(pwd -P)"
}

kicho_source_ok() {
    [[ "${KICHO_SOURCE_QUIET:-false}" == true ]] && return 0
    [[ "${KICHO_SOURCE_JSON:-false}" == true ]] && return 0
    printf '  OK    %s\n' "$1"
}

kicho_source_diagnostic() {
    local severity="$1" message="$2" file_json=null line_json=null location=''
    if [[ -n "${KICHO_SOURCE_FILE:-}" ]]; then
        location="${KICHO_SOURCE_FILE#"$KICHO_SOURCE_ROOT/"}"
        file_json="\"$(kicho_json_escape "$location")\""
        if [[ "${KICHO_SOURCE_LINE:-0}" -gt 0 ]]; then
            line_json="$KICHO_SOURCE_LINE"
            location+=":$KICHO_SOURCE_LINE"
        fi
        location+=': '
    fi
    KICHO_SOURCE_DIAGNOSTICS+=("{\"severity\":\"$severity\",\"message\":\"$(kicho_json_escape "$message")\",\"file\":$file_json,\"line\":$line_json}")
    if [[ "${KICHO_SOURCE_JSON:-false}" != true ]]; then
        local label=WARN
        [[ "$severity" == error ]] && label=FAIL
        printf '  %s  %s%s\n' "$label" "$location" "$message"
    fi
}

kicho_source_warn() {
    local KICHO_SOURCE_LINE="${2:-${KICHO_SOURCE_LINE:-0}}"
    KICHO_SOURCE_WARNINGS=$((KICHO_SOURCE_WARNINGS + 1))
    kicho_source_diagnostic warning "$1"
}

kicho_source_fail() {
    KICHO_SOURCE_ERRORS=$((KICHO_SOURCE_ERRORS + 1))
    kicho_source_diagnostic error "$1"
}

kicho_source_is_dynamic_reference() {
    case "$1" in
        *\\*|*'#'*|*'$'*|*'{'*|*'}'*) return 0 ;;
        *) return 1 ;;
    esac
}

kicho_source_prepare_reference() {
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

kicho_source_resolve_reference() {
    local reference="$1"
    local kind="$2"
    local prepared
    local directory
    local filename
    local physical_directory

    KICHO_SOURCE_RESOLVED=''

    if kicho_source_is_dynamic_reference "$reference"; then
        kicho_source_warn "dynamic $kind reference was not checked: '$reference'."
        return 2
    fi

    case "$reference" in
        /*)
            kicho_source_fail "absolute $kind reference is not allowed: '$reference'."
            return 1
            ;;
    esac

    if kicho_path_has_parent_component "$reference"; then
        kicho_source_fail "parent-path $kind reference is not allowed: '$reference'."
        return 1
    fi

    prepared="$(kicho_source_prepare_reference "$reference" "$kind")"

    local candidate graphics_path extension
    local candidates=("$prepared")
    if [[ "$kind" == figure ]]; then
        for graphics_path in "${KICHO_SOURCE_GRAPHICS_PATHS[@]}"; do
            candidates+=("${graphics_path%/}/$prepared")
        done
    fi
    for candidate in "${candidates[@]}"; do
        if [[ "$candidate" == /* ]] || kicho_path_has_parent_component "$candidate"; then
            kicho_source_fail "unsafe $kind search path: '$candidate'."
            return 1
        fi
        if kicho_path_has_symlink_component "$candidate"; then
            kicho_source_fail "$kind reference is a symbolic link: '$candidate'."
            return 1
        fi
        directory="${candidate%/*}"
        filename="${candidate##*/}"
        [[ "$directory" != "$candidate" ]] || directory='.'
        if ! physical_directory="$(cd -- "$directory" 2>/dev/null && pwd -P)"; then
            continue
        fi
        if ! kicho_path_is_within_root "$KICHO_SOURCE_ROOT" "$physical_directory"; then
            kicho_source_fail "$kind reference resolves outside the project: '$candidate'."
            return 1
        fi
        if [[ -L "$candidate" ]]; then
            kicho_source_fail "$kind reference is a symbolic link: '$candidate'."
            return 1
        fi
        if [[ -f "$physical_directory/$filename" ]]; then
            KICHO_SOURCE_RESOLVED="$physical_directory/$filename"
        elif [[ "$kind" == figure && "$filename" != *.* ]]; then
            for extension in pdf png jpg jpeg eps; do
                if [[ -L "$candidate.$extension" ]]; then
                    kicho_source_fail "figure reference is a symbolic link: '$candidate.$extension'."
                    return 1
                fi
                if [[ -f "$physical_directory/$filename.$extension" ]]; then
                    KICHO_SOURCE_RESOLVED="$physical_directory/$filename.$extension"
                    break
                fi
            done
        fi
        if [[ -n "$KICHO_SOURCE_RESOLVED" ]]; then
            KICHO_SOURCE_FILES+=("$KICHO_SOURCE_RESOLVED")
            KICHO_SOURCE_KINDS+=("$kind")
            return 0
        fi
    done

    if [[ "$kind" == figure && "${KICHO_SOURCE_GRAPHICS_DYNAMIC:-false}" == true ]]; then
        kicho_source_warn "figure search path is dynamic; '$reference' was not checked."
        return 2
    fi
    kicho_source_fail "$kind file was not found: '$prepared'."
    return 1
}

kicho_source_scan_graphicspath() {
    local text="$1" paths path
    local KICHO_SOURCE_LINE="${2:-${KICHO_SOURCE_LINE:-0}}"
    local pattern='\\graphicspath[[:space:]]*\{((\{[^{}]*\}[[:space:]]*)*)\}'
    local item_pattern='\{([^{}]*)\}'
    if [[ ! "$text" =~ $pattern ]]; then
        return 1
    fi
    paths="${BASH_REMATCH[1]}"
    KICHO_SOURCE_GRAPHICS_PATHS=()
    KICHO_SOURCE_GRAPHICS_DYNAMIC=false
    while [[ "$paths" =~ $item_pattern ]]; do
        path="${BASH_REMATCH[1]}"
        paths="${paths#*"${BASH_REMATCH[0]}"}"
        if kicho_source_is_dynamic_reference "$path"; then
            KICHO_SOURCE_GRAPHICS_DYNAMIC=true
            kicho_source_warn "dynamic graphicspath was not checked: '$path'."
        elif [[ -n "$path" ]]; then
            KICHO_SOURCE_GRAPHICS_PATHS+=("$path")
        fi
    done
    return 0
}

kicho_source_scan_local_styles() {
    local command="$1" value="$2" reference prepared kind
    local references=()
    case "$command" in
        documentclass|LoadClass*) kind=class ;;
        bibliographystyle) kind=bst ;;
        *) kind=package ;;
    esac
    IFS=',' read -r -a references <<< "$value"
    for reference in "${references[@]}"; do
        reference="${reference#"${reference%%[![:space:]]*}"}"
        reference="${reference%"${reference##*[![:space:]]}"}"
        prepared="$(kicho_source_prepare_reference "$reference" "$kind")"
        # Bare names absent from the project belong to the TeX installation.
        if [[ "$reference" != */* && ! -e "$prepared" && ! -L "$prepared" ]]; then
            continue
        fi
        if kicho_source_resolve_reference "$reference" "$kind"; then
            kicho_source_ok "$kind: $reference"
            [[ "$kind" == bst ]] || kicho_source_scan_tex_file "$KICHO_SOURCE_RESOLVED" "$kind"
        fi
    done
    return 0
}

kicho_source_scan_bibliography() {
    local value="$1"
    local reference
    local references=()
    local IFS=','

    read -r -a references <<< "$value"
    for reference in "${references[@]}"; do
        reference="${reference#"${reference%%[![:space:]]*}"}"
        reference="${reference%"${reference##*[![:space:]]}"}"
        if [[ -z "$reference" ]]; then
            kicho_source_warn 'empty bibliography reference was not checked.'
        elif kicho_source_resolve_reference "$reference" bib; then
            kicho_source_ok "bibliography: $reference"
        fi
    done
}

# Group state is shared across recursive inputs because TeX groups may start
# and end in different files. Path counts preserve spaces without delimiters.
kicho_source_push_group() {
    KICHO_SOURCE_GROUP_COUNTS+=("${#KICHO_SOURCE_GRAPHICS_PATHS[@]}")
    KICHO_SOURCE_GROUP_PATHS+=("${KICHO_SOURCE_GRAPHICS_PATHS[@]}")
    KICHO_SOURCE_GROUP_DYNAMIC+=("$KICHO_SOURCE_GRAPHICS_DYNAMIC")
}

kicho_source_pop_group() {
    local last count offset
    last=$((${#KICHO_SOURCE_GROUP_COUNTS[@]} - 1))
    [[ "$last" -ge 0 ]] || return 0
    count="${KICHO_SOURCE_GROUP_COUNTS[$last]}"
    offset=$((${#KICHO_SOURCE_GROUP_PATHS[@]} - count))
    KICHO_SOURCE_GRAPHICS_PATHS=("${KICHO_SOURCE_GROUP_PATHS[@]:offset:count}")
    KICHO_SOURCE_GRAPHICS_DYNAMIC="${KICHO_SOURCE_GROUP_DYNAMIC[$last]}"
    KICHO_SOURCE_GROUP_PATHS=("${KICHO_SOURCE_GROUP_PATHS[@]:0:offset}")
    unset 'KICHO_SOURCE_GROUP_COUNTS[last]' 'KICHO_SOURCE_GROUP_DYNAMIC[last]'
}

# Bibliography-use state is consumed by dependencies.sh.
# shellcheck disable=SC2034
kicho_source_scan_tex_file() {
    local source_file="$1" edge_kind="${2:-input}" command value
    if [[ "${KICHO_SOURCE_STACK:-}" == *"|$source_file|"* && "$edge_kind" == input ]]; then
        kicho_source_fail "input/include cycle detected at '${source_file#"$KICHO_SOURCE_ROOT/"}'."
        return 0
    fi
    # TeX reexecutes input files, but loads each package/class only once.
    if [[ "$edge_kind" != input && "$KICHO_SOURCE_VISITED" == *"|$source_file|"* ]]; then
        return 0
    fi
    KICHO_SOURCE_VISITED+="|$source_file|"
    local KICHO_SOURCE_STACK="${KICHO_SOURCE_STACK:-}|$source_file|"
    local KICHO_SOURCE_FILE="$source_file" KICHO_SOURCE_LINE=0
    while IFS=$'\t' read -r KICHO_SOURCE_LINE command value; do
        case "$command" in
            open) kicho_source_push_group ;;
            close) kicho_source_pop_group ;;
            graphicspath)
                if ! kicho_source_scan_graphicspath "\graphicspath{$value}"; then
                    KICHO_SOURCE_GRAPHICS_DYNAMIC=true
                    KICHO_SOURCE_GRAPHICS_PATHS=()
                    kicho_source_warn 'macro-generated or unsupported graphicspath was not checked.'
                fi ;;
            input|include)
                if kicho_source_resolve_reference "$value" input; then
                    kicho_source_ok "input: $value"
                    kicho_source_scan_tex_file "$KICHO_SOURCE_RESOLVED"
                fi ;;
            includegraphics)
                if kicho_source_resolve_reference "$value" figure; then
                    kicho_source_ok "figure: $value"
                fi ;;
            addbibresource|bibliography)
                KICHO_SOURCE_USES_BIBLIOGRAPHY=true
                kicho_source_scan_bibliography "$value" ;;
            printbibliography) KICHO_SOURCE_USES_BIBLIOGRAPHY=true ;;
            unsupported)
                [[ "$value" != graphicspath ]] || KICHO_SOURCE_GRAPHICS_DYNAMIC=true
                case "$value" in
                    addbibresource|bibliography) KICHO_SOURCE_USES_BIBLIOGRAPHY=true ;;
                esac
                kicho_source_warn "unsupported or unclosed $value was not checked." ;;
            *) kicho_source_scan_local_styles "$command" "$value" ;;
        esac
    done < <(kicho_tex_active_file "$source_file" | LC_ALL=C awk -f "$KICHO_LIB_DIR/tex-events.awk")
    return 0
}

kicho_source_write_json() {
    local record separator=''
    printf '{"schema_version":1,"errors":%d,"warnings":%d,"diagnostics":[' \
        "$KICHO_SOURCE_ERRORS" "$KICHO_SOURCE_WARNINGS"
    for record in "${KICHO_SOURCE_DIAGNOSTICS[@]}"; do
        printf '%s%s' "$separator" "$record"
        separator=,
    done
    printf ']}\n'
}
