# shellcheck shell=bash
# Implementation of `kicho split`.

kicho_command_split_summary() {
    printf 'Split a single-file project into multiple files.\n'
}

kicho_command_split_usage() {
    cat <<'USAGE'
Usage:
    kicho split

Move blocks delimited by "% kicho:section NAME" and "% kicho:end"
from main.tex into sections/NAME.tex.
USAGE
}

kicho_command_split_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho split
EXAMPLES
}

kicho_command_split_requires_project() {
    return 0
}

kicho_split_section_name() {
    local line="$1"

    if [[ "$line" =~ ^[[:space:]]*%[[:space:]]*kicho:section[[:space:]]+([a-z0-9][a-z0-9-]*)[[:space:]]*$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

kicho_split_is_end_marker() {
    [[ "$1" =~ ^[[:space:]]*%[[:space:]]*kicho:end[[:space:]]*$ ]]
}

kicho_split_validate() {
    local current_section=""
    local line
    local section_count=0
    local section_name
    local section_names=" "

    if [[ ! -f "main.tex" ]]; then
        kicho_error "main.tex was not found."
        return 1
    fi

    if [[ -e "main.tex.kicho-backup" ]]; then
        kicho_error "backup already exists: 'main.tex.kicho-backup'."
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        section_name=""
        if section_name="$(kicho_split_section_name "$line")"; then
            if [[ -n "$current_section" ]]; then
                kicho_error "nested split marker found inside '$current_section'."
                return 1
            fi

            if [[ "$section_names" == *" $section_name "* ]]; then
                kicho_error "duplicate split section '$section_name'."
                return 1
            fi

            if [[ -e "sections/$section_name.tex" ]]; then
                kicho_error "split destination already exists: 'sections/$section_name.tex'."
                return 1
            fi

            current_section="$section_name"
            section_names+="$section_name "
            section_count=$((section_count + 1))
        elif kicho_split_is_end_marker "$line"; then
            if [[ -z "$current_section" ]]; then
                kicho_error "split end marker found without an open section."
                return 1
            fi

            current_section=""
        elif [[ "$line" =~ ^[[:space:]]*%[[:space:]]*kicho:(section|end) ]]; then
            kicho_error "invalid split marker: '$line'."
            return 1
        fi
    done < "main.tex"

    if [[ -n "$current_section" ]]; then
        kicho_error "split section '$current_section' has no end marker."
        return 1
    fi

    if ((section_count == 0)); then
        kicho_error "no split markers were found in main.tex."
        return 1
    fi
}

kicho_split_render() {
    local destination="$1"
    local current_section=""
    local line
    local section_name

    mkdir -p "$destination/sections"
    : > "$destination/main.tex"

    while IFS= read -r line || [[ -n "$line" ]]; do
        section_name=""
        if section_name="$(kicho_split_section_name "$line")"; then
            current_section="$section_name"
            : > "$destination/sections/$section_name.tex"
            printf '\\input{sections/%s}\n' "$section_name" >> "$destination/main.tex"
        elif kicho_split_is_end_marker "$line"; then
            current_section=""
        elif [[ -n "$current_section" ]]; then
            printf '%s\n' "$line" >> "$destination/sections/$current_section.tex"
        else
            printf '%s\n' "$line" >> "$destination/main.tex"
        fi
    done < "main.tex"
}

kicho_command_split() {
    if [[ $# -ne 0 ]]; then
        kicho_error "split does not accept arguments."
        printf "Run 'kicho help split' for usage.\n" >&2
        return 1
    fi

    if ! kicho_split_validate; then
        return 1
    fi

    local temporary_directory
    temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/kicho-split.XXXXXX")" || {
        kicho_error "could not create temporary split directory."
        return 1
    }

    if ! kicho_split_render "$temporary_directory"; then
        rm -rf "$temporary_directory"
        kicho_error "could not prepare split output."
        return 1
    fi

    if ! cp "main.tex" "main.tex.kicho-backup"; then
        rm -rf "$temporary_directory"
        kicho_error "could not create main.tex backup."
        return 1
    fi

    mkdir -p "sections"

    local section_file
    for section_file in "$temporary_directory/sections/"*.tex; do
        if ! cp "$section_file" "sections/"; then
            rm -rf "$temporary_directory"
            kicho_error "could not copy split section files."
            return 1
        fi
    done

    if ! cp "$temporary_directory/main.tex" "main.tex"; then
        rm -rf "$temporary_directory"
        kicho_error "could not update main.tex."
        return 1
    fi

    rm -rf "$temporary_directory"

    printf 'Split completed successfully.\n'
    printf 'Backup: main.tex.kicho-backup\n'
}
