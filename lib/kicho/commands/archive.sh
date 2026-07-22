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

    mkdir -p \
        "$root/source" \
        "$root/pdf" \
        "$root/metadata"
}

kicho_command_archive() {
    if [[ $# -ne 0 ]]; then
        kicho_error "archive does not accept arguments."
        printf "Run 'kicho help archive' for usage.\n" >&2
        return 1
    fi

    local timestamp
    timestamp="$(kicho_archive_timestamp)"

    local archive_root
    archive_root="$(kicho_archive_root "$timestamp")"

    kicho_archive_create_directories "$archive_root"

    printf 'Created archive:\n'
    printf '    %s\n' "$archive_root"
}
