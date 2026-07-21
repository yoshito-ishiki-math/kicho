# Implementation of `kicho init`.

kicho_init() {
    local project="${1:-}"

    if [[ -z "$project" ]]; then
        kicho_error "project name required."
        printf '\nUsage:\n    kicho init PROJECT\n' >&2
        exit 1
    fi

    if [[ -e "$project" ]]; then
        kicho_error "directory '$project' already exists."
        exit 1
    fi

    local template_dir="$KICHO_ROOT/templates/english-paper"

    if [[ ! -d "$template_dir" ]]; then
        kicho_error "template directory not found: '$template_dir'."
        exit 1
    fi

    cp -R "$template_dir" "$project"
    printf 'Created project: %s\n' "$project"
}
