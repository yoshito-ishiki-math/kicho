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

kicho_archive_created_at() {
    local timestamp
    local offset

    timestamp="$(date '+%Y-%m-%dT%H:%M:%S')"
    offset="$(date '+%z')"

    printf '%s%s:%s\n' "$timestamp" "${offset%??}" "${offset#???}"
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

kicho_json_escape() {
    local value="$1"
    local result=""
    local character
    local encoded
    local code
    local index
    local LC_ALL=C

    for ((index = 0; index < ${#value}; index += 1)); do
        character="${value:index:1}"

        case "$character" in
            '"') result+='\"' ;;
            \\) result+='\\' ;;
            $'\b') result+='\b' ;;
            $'\f') result+='\f' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)
                printf -v code '%d' "'$character"
                if ((code >= 0 && code < 32)); then
                    printf -v encoded '\\u%04x' "$code"
                    result+="$encoded"
                else
                    result+="$character"
                fi
                ;;
        esac
    done

    printf '%s' "$result"
}

kicho_archive_has_git_metadata() {
    command -v git >/dev/null 2>&1 &&
        git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        git rev-parse --verify HEAD >/dev/null 2>&1
}

kicho_archive_git_branch() {
    git symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'HEAD\n'
}

kicho_archive_git_commit() {
    git rev-parse HEAD
}

kicho_archive_git_dirty() {
    if [[ -n "$(git status --porcelain)" ]]; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

kicho_archive_write_metadata() {
    local destination="$1"
    local created_at="$2"
    local project="$3"
    local include_git="$4"
    local git_branch="$5"
    local git_commit="$6"
    local git_dirty="$7"

    local escaped_version
    local escaped_created_at
    local escaped_project
    local escaped_git_branch
    local escaped_git_commit

    escaped_version="$(kicho_json_escape "$KICHO_VERSION")"
    escaped_created_at="$(kicho_json_escape "$created_at")"
    escaped_project="$(kicho_json_escape "$project")"

    {
        printf '{\n'
        printf '  "kicho_version": "%s",\n' "$escaped_version"
        printf '  "created_at": "%s",\n' "$escaped_created_at"

        if [[ "$include_git" == "true" ]]; then
            escaped_git_branch="$(kicho_json_escape "$git_branch")"
            escaped_git_commit="$(kicho_json_escape "$git_commit")"

            printf '  "project": "%s",\n' "$escaped_project"
            printf '  "git": {\n'
            printf '    "branch": "%s",\n' "$escaped_git_branch"
            printf '    "commit": "%s",\n' "$escaped_git_commit"
            printf '    "dirty": %s\n' "$git_dirty"
            printf '  }\n'
        else
            printf '  "project": "%s"\n' "$escaped_project"
        fi

        printf '}\n'
    } > "$destination"
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
    created_at="$(kicho_archive_created_at)"

    local project
    project="$(basename "$PWD")"

    local include_git="false"
    local git_branch=""
    local git_commit=""
    local git_dirty="false"

    if kicho_archive_has_git_metadata; then
        include_git="true"
        git_branch="$(kicho_archive_git_branch)"
        git_commit="$(kicho_archive_git_commit)"
        git_dirty="$(kicho_archive_git_dirty)"
    fi

    local archive_root
    archive_root="$(kicho_archive_root "$timestamp")"

    kicho_archive_create_directories "$archive_root"
    kicho_archive_copy_source "$archive_root/source"
    kicho_archive_copy_pdf "$archive_root/pdf"
    kicho_archive_write_metadata \
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
