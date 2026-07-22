# Implementation of `kicho init`.

kicho_command_init_summary() {
    printf 'Create a new LaTeX research project.\n'
}

kicho_command_init_usage() {
    printf 'Usage:\n    kicho init PROJECT\n'
}

kicho_command_init_examples() {
    printf 'Examples:\n    kicho init MyPaper\n'
}

kicho_command_init() {
    local project="${1:-}"

    if [[ $# -eq 0 ]]; then
        kicho_error "project name required."
        printf '\nUsage:\n    kicho init PROJECT\n' >&2
        return 1
    fi

    if [[ $# -ne 1 ]]; then
        kicho_error "init accepts exactly one project name."
        printf "Run 'kicho help init' for usage.\n" >&2
        return 1
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

    rm -rf "$project/build"
    mkdir -p "$project/build"
    if [[ -f "$template_dir/build/.gitkeep" ]]; then
        cp "$template_dir/build/.gitkeep" "$project/build/.gitkeep"
    fi

    printf 'Created project: %s\n' "$project"
}
