# shellcheck shell=bash
# Shared metadata helpers for archives and submission packages.

kicho_metadata_created_at() {
    local timestamp
    local offset

    timestamp="$(date '+%Y-%m-%dT%H:%M:%S')"
    offset="$(date '+%z')"

    printf '%s%s:%s\n' "$timestamp" "${offset%??}" "${offset#???}"
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
            \\) result+="\\\\" ;;
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

kicho_metadata_has_git() {
    command -v git >/dev/null 2>&1 &&
        git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        git rev-parse --verify HEAD >/dev/null 2>&1
}

kicho_metadata_git_branch() {
    git symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'HEAD\n'
}

kicho_metadata_git_commit() {
    git rev-parse HEAD
}

kicho_metadata_git_dirty() {
    if [[ -n "$(git status --porcelain)" ]]; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

kicho_metadata_write_manifest() {
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
