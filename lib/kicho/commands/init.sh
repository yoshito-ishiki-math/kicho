# shellcheck shell=bash
# Implementation of `kicho init`.

kicho_command_init_summary() {
    printf 'Create a new LaTeX research project.\n'
}

kicho_command_init_usage() {
    cat <<'USAGE'
Usage:
    kicho init PROJECT
    kicho init --template TEMPLATE PROJECT

Templates:
    english     English amsart paper (default)
    japanese    Japanese jlreq paper using LuaLaTeX-ja
USAGE
}

kicho_command_init_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho init MyPaper
    kicho init --template japanese MyJapanesePaper
EXAMPLES
}

kicho_init_template_directory() {
    case "$1" in
        english) printf '%s\n' "$KICHO_ROOT/templates/english-paper" ;;
        japanese) printf '%s\n' "$KICHO_ROOT/templates/japanese-paper" ;;
        *) return 1 ;;
    esac
}

kicho_command_init() {
    local project=""
    local template="english"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--template)
                if [[ $# -lt 2 || -z "${2:-}" ]]; then
                    kicho_error "option '$1' requires a template name."
                    return 1
                fi
                template="$2"
                shift 2
                ;;

            --template=*)
                template="${1#*=}"
                if [[ -z "$template" ]]; then
                    kicho_error "option '--template' requires a template name."
                    return 1
                fi
                shift
                ;;

            -*)
                kicho_error "unknown init option '$1'."
                printf "Run 'kicho help init' for usage.\n" >&2
                return 1
                ;;

            *)
                if [[ -n "$project" ]]; then
                    kicho_error "init accepts exactly one project name."
                    printf "Run 'kicho help init' for usage.\n" >&2
                    return 1
                fi
                project="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$project" ]]; then
        kicho_error "project name required."
        printf '\nUsage:\n    kicho init PROJECT\n' >&2
        return 1
    fi

    local template_dir
    if ! template_dir="$(kicho_init_template_directory "$template")"; then
        kicho_error "unknown project template '$template'."
        printf "Available templates: english, japanese.\n" >&2
        return 1
    fi

    if [[ -e "$project" ]]; then
        kicho_error "directory '$project' already exists."
        exit 1
    fi

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
