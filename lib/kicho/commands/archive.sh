# shellcheck shell=bash
# Implementation of `kicho archive`.

kicho_command_archive_summary() {
    printf 'Create a snapshot of the current project.\n'
}

kicho_command_archive_usage() {
    cat <<'USAGE'
Usage:
    kicho archive

Create an archive snapshot of the current project.
USAGE
}

kicho_command_archive_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho archive
EXAMPLES
}

kicho_command_archive_requires_project() {
    return 0
}

kicho_archive_timestamp() {
    date '+%Y-%m-%d_%H-%M-%S'
}

kicho_archive_root() {
    local timestamp="$1"
    printf 'archives/%s\n' "$timestamp"
}

kicho_archive_create_directories() {
    local root="$1"

    mkdir -p "${root%/*}"

    if ! mkdir "$root"; then
        kicho_error "archive already exists or could not be created: '$root'."
        return 1
    fi

    mkdir \
        "$root/source" \
        "$root/pdf" \
        "$root/metadata"
}

kicho_archive_copy_if_exists() {
    local source="$1"
    local destination="$2"

    if [[ -e "$source" ]]; then
        cp -R "$source" "$destination"
    else
        printf 'Warning: %s not found.\n' "$source" >&2
    fi
}

kicho_archive_copy_source() {
    local destination="$1"

    kicho_archive_copy_if_exists main.tex "$destination"
    kicho_archive_copy_if_exists sections "$destination"
    kicho_archive_copy_if_exists preamble "$destination"
    kicho_archive_copy_if_exists figures "$destination"
    kicho_archive_copy_if_exists bib "$destination"
    kicho_archive_copy_if_exists .latexmkrc "$destination"
}

kicho_archive_copy_pdf() {
    local destination="$1"

    if [[ -f "build/main.pdf" ]]; then
        cp "build/main.pdf" "$destination/main.pdf"
    else
        printf 'Warning: build/main.pdf not found.\n' >&2
    fi
}

kicho_archive_check_source() {
    local source="$1"
    local report
    if ! report="$(cd -- "$source" && kicho_command_check)"; then
        printf 'Warning: archived source may not be self-contained; static checks found missing or invalid dependencies.\n' >&2
        printf '%s\n' "$report" >&2
    fi
}

kicho_command_archive() {
    if [[ $# -ne 0 ]]; then
        kicho_error "archive does not accept arguments."
        printf "Run 'kicho help archive' for usage.\n" >&2
        return 1
    fi

    local timestamp
    timestamp="$(kicho_archive_timestamp)"

    local created_at
    created_at="$(kicho_metadata_created_at)"

    local project
    project="$(basename "$PWD")"

    local include_git="false"
    local git_branch=""
    local git_commit=""
    local git_dirty="false"

    if kicho_metadata_has_git; then
        include_git="true"
        git_branch="$(kicho_metadata_git_branch)"
        git_commit="$(kicho_metadata_git_commit)"
        git_dirty="$(kicho_metadata_git_dirty)"
    fi

    local archive_root
    archive_root="$(kicho_archive_root "$timestamp")"

    kicho_archive_create_directories "$archive_root"
    kicho_archive_copy_source "$archive_root/source"
    kicho_copy_source_dependencies "$archive_root/source" archive
    kicho_archive_check_source "$archive_root/source"
    kicho_archive_copy_pdf "$archive_root/pdf"
    kicho_metadata_write_manifest \
        "$archive_root/metadata/archive.json" \
        "$created_at" \
        "$project" \
        "$include_git" \
        "$git_branch" \
        "$git_commit" \
        "$git_dirty"

    printf 'Created archive:\n'
    printf '    %s\n' "$archive_root"
}
