# shellcheck shell=bash
# Implementation of `kicho split`.

kicho_command_split_summary() {
    printf 'Split marked source blocks into section files.\n'
}

kicho_command_split_usage() {
    cat <<'USAGE'
Usage:
    kicho split [FILE]

Move blocks delimited by "% kicho:section NAME" and "% kicho:end"
from FILE into sections/NAME.tex. FILE defaults to main.tex.
USAGE
}

kicho_command_split_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho split
    kicho split sections/introduction.tex
EXAMPLES
}

kicho_command_split_requires_project() {
    return 0
}

kicho_command_split_accepts_arguments() {
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

kicho_split_resolve_source() {
    local source="$1"
    local project_root="$2"

    if [[ -z "$source" ]]; then
        kicho_error "split source path must not be empty."
        return 1
    fi

    case "$source" in
        /*)
            kicho_error "split does not allow absolute source paths: '$source'."
            return 1
            ;;
    esac

    if kicho_path_has_parent_component "$source"; then
        kicho_error "split does not allow '..' path components: '$source'."
        return 1
    fi

    while [[ "$source" == ./* ]]; do
        source="${source#./}"
    done

    case "$source" in
        *.tex) ;;
        *)
            kicho_error "split source must be a .tex file: '$source'."
            return 1
            ;;
    esac

    local directory="${source%/*}"
    local filename="${source##*/}"
    if [[ "$directory" == "$source" ]]; then
        directory="."
    fi

    local physical_directory
    if ! physical_directory="$(cd -- "$directory" 2>/dev/null && pwd -P)"; then
        kicho_error "split source directory was not found: '$directory'."
        return 1
    fi

    if ! kicho_path_is_within_root "$project_root" "$physical_directory"; then
        kicho_error "split source resolves outside the project: '$source'."
        return 1
    fi

    local resolved_path="$physical_directory/$filename"
    if [[ -L "$resolved_path" ]]; then
        kicho_error "split does not follow symbolic-link sources: '$source'."
        return 1
    fi

    if [[ ! -f "$resolved_path" ]]; then
        kicho_error "split source file was not found: '$source'."
        return 1
    fi

    printf '%s\n' "$source"
}

kicho_split_validate() {
    local source_file="$1"
    local current_section=""
    local line
    local section_count=0
    local section_name
    local section_names=" "

    if [[ -L "sections" ]]; then
        kicho_error "split does not use a symbolic-link sections directory."
        return 1
    fi

    if [[ -e "sections" && ! -d "sections" ]]; then
        kicho_error "split output directory is not a directory: 'sections'."
        return 1
    fi

    if [[ -e "$source_file.kicho-backup" || -L "$source_file.kicho-backup" ]]; then
        kicho_error "backup already exists: '$source_file.kicho-backup'."
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

            if [[ -e "sections/$section_name.tex" || -L "sections/$section_name.tex" ]]; then
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
    done < "$source_file"

    if [[ -n "$current_section" ]]; then
        kicho_error "split section '$current_section' has no end marker."
        return 1
    fi

    if ((section_count == 0)); then
        kicho_error "no split markers were found in '$source_file'."
        return 1
    fi
}

kicho_split_render() {
    local destination="$1"
    local source_file="$2"
    local current_section=""
    local line
    local section_name

    mkdir -p "$destination/sections"
    : > "$destination/source.tex"

    while IFS= read -r line || [[ -n "$line" ]]; do
        section_name=""
        if section_name="$(kicho_split_section_name "$line")"; then
            current_section="$section_name"
            : > "$destination/sections/$section_name.tex"
            printf '\\input{sections/%s}\n' "$section_name" >> "$destination/source.tex"
        elif kicho_split_is_end_marker "$line"; then
            current_section=""
        elif [[ -n "$current_section" ]]; then
            printf '%s\n' "$line" >> "$destination/sections/$current_section.tex"
        else
            printf '%s\n' "$line" >> "$destination/source.tex"
        fi
    done < "$source_file"
}

kicho_split_rollback() {
    local source_file="$1"
    local remove_sections_directory="$2"
    shift 2

    local created_section
    local rollback_status=0
    for created_section in "$@"; do
        if ! rm -f -- "$created_section"; then
            rollback_status=1
        fi
    done

    if [[ -f "$source_file.kicho-backup" ]]; then
        if cp "$source_file.kicho-backup" "$source_file" >/dev/null 2>&1; then
            if ! rm -f -- "$source_file.kicho-backup"; then
                rollback_status=1
            fi
        else
            rollback_status=1
        fi
    fi

    if [[ "$remove_sections_directory" == "true" && -d "sections" ]]; then
        if ! rmdir "sections" >/dev/null 2>&1; then
            rollback_status=1
        fi
    fi

    return "$rollback_status"
}

kicho_command_split() {
    if [[ $# -gt 1 ]]; then
        kicho_error "split accepts at most one source file."
        printf "Run 'kicho help split' for usage.\n" >&2
        return 1
    fi

    local source_file="${1:-main.tex}"
    local project_root
    project_root="$(pwd -P)"

    if ! source_file="$(kicho_split_resolve_source "$source_file" "$project_root")"; then
        return 1
    fi

    if ! kicho_split_validate "$source_file"; then
        return 1
    fi

    local temporary_directory
    temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/kicho-split.XXXXXX")" || {
        kicho_error "could not create temporary split directory."
        return 1
    }

    if ! kicho_split_render "$temporary_directory" "$source_file"; then
        rm -rf "$temporary_directory"
        kicho_error "could not prepare split output."
        return 1
    fi

    local remove_sections_directory="false"
    if [[ ! -d "sections" ]]; then
        remove_sections_directory="true"
    fi

    if ! cp "$source_file" "$source_file.kicho-backup"; then
        rm -rf "$temporary_directory"
        kicho_error "could not create source backup: '$source_file.kicho-backup'."
        return 1
    fi

    if ! mkdir -p "sections"; then
        rm -rf "$temporary_directory"
        if ! kicho_split_rollback "$source_file" "$remove_sections_directory"; then
            kicho_error "split rollback was incomplete; inspect the source and its backup."
        fi
        kicho_error "could not create split output directory: 'sections'."
        return 1
    fi

    local section_file
    local section_name
    local created_sections=()
    for section_file in "$temporary_directory/sections/"*.tex; do
        section_name="${section_file##*/}"
        if ! cp "$section_file" "sections/$section_name"; then
            rm -rf "$temporary_directory"
            if ! kicho_split_rollback \
                "$source_file" \
                "$remove_sections_directory" \
                "${created_sections[@]}"; then
                kicho_error "split rollback was incomplete; inspect the source and its backup."
            fi
            kicho_error "could not copy split section files."
            return 1
        fi
        created_sections+=("sections/$section_name")
    done

    if ! cp "$temporary_directory/source.tex" "$source_file"; then
        rm -rf "$temporary_directory"
        if ! kicho_split_rollback \
            "$source_file" \
            "$remove_sections_directory" \
            "${created_sections[@]}"; then
            kicho_error "split rollback was incomplete; inspect the source and its backup."
        fi
        kicho_error "could not update split source: '$source_file'."
        return 1
    fi

    rm -rf "$temporary_directory"

    printf 'Split completed successfully.\n'
    printf 'Backup: %s.kicho-backup\n' "$source_file"
}
