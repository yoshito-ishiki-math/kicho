# Implementation of `kicho init`.

init_project() {
    local project="${1:-}"

    if [[ -z "$project" ]]; then
        error "project name required."
        printf '\nUsage:\n    kicho init PROJECT\n' >&2
        exit 1
    fi

    if [[ -e "$project" ]]; then
        error "directory '$project' already exists."
        exit 1
    fi

    local template_dir="$KICHO_ROOT/templates/english-paper"

    if [[ ! -d "$template_dir" ]]; then
        error "template directory not found: '$template_dir'."
        exit 1
    fi

    cp -R "$template_dir" "$project"
    printf 'Created project: %s\n' "$project"
}
