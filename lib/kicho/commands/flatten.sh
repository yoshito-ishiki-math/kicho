# shellcheck shell=bash
# Implementation of `kicho flatten`.

kicho_command_flatten_summary() {
    printf 'Merge a multi-file project into a single file.\n'
}

kicho_command_flatten_usage() {
    cat <<'USAGE'
Usage:
    kicho flatten

Recursively expand full-line \input and \include commands into dist/main.tex.
USAGE
}

kicho_command_flatten_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho flatten
EXAMPLES
}

kicho_command_flatten_requires_project() {
    return 0
}

kicho_flatten_reference() {
    local line="$1"
    local pattern='^[[:space:]]*\\(input|include)\{([^{}]+)\}[[:space:]]*(%.*)?$'

    if [[ "$line" =~ $pattern ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

kicho_flatten_resolve_path() {
    local reference="$1"
    local project_root="$2"

    case "$reference" in
        /*)
            kicho_error "flatten does not allow absolute input paths: '$reference'."
            return 1
            ;;
    esac

    case "/$reference/" in
        */../*)
            kicho_error "flatten does not allow '..' path components: '$reference'."
            return 1
            ;;
    esac

    while [[ "$reference" == ./* ]]; do
        reference="${reference#./}"
    done

    case "${reference##*/}" in
        *.*) ;;
        *) reference+=".tex" ;;
    esac

    local directory="${reference%/*}"
    local filename="${reference##*/}"
    if [[ "$directory" == "$reference" ]]; then
        directory="."
    fi

    local physical_directory
    if ! physical_directory="$(cd -- "$directory" 2>/dev/null && pwd -P)"; then
        kicho_error "flatten input directory was not found: '$directory'."
        return 1
    fi

    case "$physical_directory" in
        "$project_root"|"$project_root"/*) ;;
        *)
            kicho_error "flatten input resolves outside the project: '$reference'."
            return 1
            ;;
    esac

    local resolved_path="$physical_directory/$filename"
    if [[ -L "$resolved_path" ]]; then
        kicho_error "flatten does not follow symbolic-link inputs: '$reference'."
        return 1
    fi

    if [[ ! -f "$resolved_path" ]]; then
        kicho_error "flatten input file was not found: '$reference'."
        return 1
    fi

    printf '%s\n' "$resolved_path"
}

kicho_flatten_file() {
    local source_file="$1"
    local project_root="$2"
    local stack="$3"
    local line
    local reference
    local resolved_path

    while IFS= read -r line || [[ -n "$line" ]]; do
        reference=""
        if reference="$(kicho_flatten_reference "$line")"; then
            if ! resolved_path="$(kicho_flatten_resolve_path "$reference" "$project_root")"; then
                return 1
            fi

            if [[ "$stack" == *"|$resolved_path|"* ]]; then
                kicho_error "flatten include cycle detected at '$reference'."
                return 1
            fi

            if ! kicho_flatten_file \
                "$resolved_path" \
                "$project_root" \
                "$stack$resolved_path|"; then
                return 1
            fi
        else
            printf '%s\n' "$line"
        fi
    done < "$source_file"
}

kicho_flatten_write() {
    local destination="$1"

    if [[ ! -f "main.tex" ]]; then
        kicho_error "main.tex was not found."
        return 1
    fi

    local project_root
    project_root="$(pwd -P)"

    if ! kicho_flatten_file \
        "$project_root/main.tex" \
        "$project_root" \
        "|$project_root/main.tex|" > "$destination"; then
        rm -f "$destination"
        return 1
    fi
}

kicho_command_flatten() {
    if [[ $# -ne 0 ]]; then
        kicho_error "flatten does not accept arguments."
        printf "Run 'kicho help flatten' for usage.\n" >&2
        return 1
    fi

    if [[ -e "dist/main.tex" ]]; then
        kicho_error "flatten destination already exists: 'dist/main.tex'."
        return 1
    fi

    local temporary_file
    temporary_file="$(mktemp "${TMPDIR:-/tmp}/kicho-flatten.XXXXXX")" || {
        kicho_error "could not create temporary flatten file."
        return 1
    }

    if ! kicho_flatten_write "$temporary_file"; then
        rm -f "$temporary_file"
        return 1
    fi

    mkdir -p "dist"
    if ! mv "$temporary_file" "dist/main.tex"; then
        rm -f "$temporary_file"
        kicho_error "could not create dist/main.tex."
        return 1
    fi

    printf 'Created flattened document:\n'
    printf '    dist/main.tex\n'
}
