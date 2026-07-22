# shellcheck shell=bash
# Command discovery and dispatch for Kicho.

readonly KICHO_COMMAND_DIR="$KICHO_LIB_DIR/commands"

kicho_command_function_name() {
    local command="$1"
    command="${command//-/_}"
    printf 'kicho_command_%s\n' "$command"
}

kicho_command_metadata_function_name() {
    local command="$1"
    local metadata="$2"

    printf '%s_%s\n' "$(kicho_command_function_name "$command")" "$metadata"
}

kicho_command_has_implementation() {
    local command_function
    command_function="$(kicho_command_function_name "$1")"

    declare -F "$command_function" >/dev/null 2>&1
}

kicho_command_query() {
    local command="$1"
    local metadata="$2"
    local metadata_function
    metadata_function="$(kicho_command_metadata_function_name "$command" "$metadata")"

    if ! declare -F "$metadata_function" >/dev/null 2>&1; then
        return 1
    fi

    "$metadata_function"
}

kicho_command_names() {
    local command_file

    shopt -s nullglob
    for command_file in "$KICHO_COMMAND_DIR"/*.sh; do
        basename "$command_file" .sh
    done
    shopt -u nullglob
}

kicho_validate_commands() {
    local command
    local alias
    local aliases
    local registered_names=" help version "

    while IFS= read -r command; do
        if [[ ! "$command" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
            kicho_error "invalid command filename '$command.sh'."
            exit 1
        fi

        if [[ "$registered_names" == *" $command "* ]]; then
            kicho_error "command name '$command' is reserved or already in use."
            exit 1
        fi

        if ! kicho_command_has_implementation "$command"; then
            kicho_error "command '$command' has no implementation."
            exit 1
        fi

        registered_names+="$command "
    done < <(kicho_command_names)

    while IFS= read -r command; do
        aliases=""
        if aliases="$(kicho_command_query "$command" aliases)"; then
            for alias in $aliases; do
                if [[ ! "$alias" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
                    kicho_error "command '$command' has invalid alias '$alias'."
                    exit 1
                fi

                if [[ "$registered_names" == *" $alias "* ]]; then
                    kicho_error "command alias '$alias' is already in use."
                    exit 1
                fi

                registered_names+="$alias "
            done
        fi
    done < <(kicho_command_names)
}

kicho_load_commands() {
    local command_file

    if [[ ! -d "$KICHO_COMMAND_DIR" ]]; then
        kicho_error "command directory not found: '$KICHO_COMMAND_DIR'."
        exit 1
    fi

    shopt -s nullglob
    for command_file in "$KICHO_COMMAND_DIR"/*.sh; do
        # shellcheck source=/dev/null
        source "$command_file"
    done
    shopt -u nullglob

    kicho_validate_commands
}

kicho_list_commands() {
    local command
    local summary

    while IFS= read -r command; do
        summary=""
        if summary="$(kicho_command_query "$command" summary)"; then
            printf '    %-16s %s\n' "$command" "$summary"
        else
            printf '    %s\n' "$command"
        fi
    done < <(kicho_command_names)
}

kicho_resolve_command() {
    local requested="$1"
    local command
    local alias
    local aliases

    if kicho_command_has_implementation "$requested"; then
        printf '%s\n' "$requested"
        return
    fi

    while IFS= read -r command; do
        aliases=""
        if aliases="$(kicho_command_query "$command" aliases)"; then
            for alias in $aliases; do
                if [[ "$alias" == "$requested" ]]; then
                    printf '%s\n' "$command"
                    return
                fi
            done
        fi
    done < <(kicho_command_names)

    return 1
}

kicho_show_command_help() {
    local requested="$1"
    local command
    local aliases
    local examples
    local summary
    local usage

    if ! command="$(kicho_resolve_command "$requested")"; then
        kicho_error "unknown command '$requested'."
        printf "Run 'kicho --help' for usage.\n" >&2
        exit 1
    fi

    summary=""
    if summary="$(kicho_command_query "$command" summary)"; then
        printf '%s\n\n' "$summary"
    fi

    usage=""
    if usage="$(kicho_command_query "$command" usage)"; then
        printf '%s\n' "$usage"
    else
        printf 'Usage:\n    kicho %s\n' "$command"
    fi

    examples=""
    if examples="$(kicho_command_query "$command" examples)"; then
        printf '\n%s\n' "$examples"
    fi

    aliases=""
    if aliases="$(kicho_command_query "$command" aliases)"; then
        printf '\nAliases:\n    %s\n' "$aliases"
    fi
}

kicho_check_command_requirements() {
    local command="$1"

    if kicho_command_query "$command" requires_project; then
        kicho_require_project
    fi

    if kicho_command_query "$command" requires_latexmk; then
        kicho_require_latexmk
    fi
}

kicho_dispatch() {
    local command="${1:-}"

    case "$command" in
        "")
            kicho_show_help
            return
            ;;

        -h|--help)
            if [[ -n "${2:-}" ]]; then
                kicho_error "'$command' does not accept arguments."
                printf "Run 'kicho --help' for usage.\n" >&2
                return 1
            fi
            kicho_show_help
            return
            ;;

        help)
            shift
            if [[ -z "${1:-}" ]]; then
                kicho_show_help
                return
            fi

            if [[ -n "${2:-}" ]]; then
                kicho_error "help accepts only one command name."
                exit 1
            fi

            kicho_show_command_help "$1"
            return
            ;;

        -v|--version|version)
            if [[ -n "${2:-}" ]]; then
                kicho_error "'$command' does not accept arguments."
                printf "Run 'kicho --help' for usage.\n" >&2
                return 1
            fi
            kicho_show_version
            return
            ;;
    esac

    if [[ ! "$command" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        kicho_error "invalid command name '$command'."
        exit 1
    fi

    local resolved_command
    if ! resolved_command="$(kicho_resolve_command "$command")"; then
        kicho_error "unknown command '$command'."
        printf "Run 'kicho --help' for usage.\n" >&2
        exit 1
    fi

    local command_function
    command_function="$(kicho_command_function_name "$resolved_command")"

    shift

    case "${1:-}" in
        -h|--help)
            if [[ $# -ne 1 ]]; then
                kicho_error "'$resolved_command --help' does not accept arguments."
                printf "Run 'kicho help %s' for usage.\n" "$resolved_command" >&2
                return 1
            fi

            kicho_show_command_help "$resolved_command"
            return
            ;;
    esac

    if [[ $# -gt 0 ]] &&
        ! kicho_command_query "$resolved_command" accepts_arguments; then
        kicho_error "$resolved_command does not accept arguments."
        printf "Run 'kicho help %s' for usage.\n" "$resolved_command" >&2
        return 1
    fi

    kicho_check_command_requirements "$resolved_command"
    "$command_function" "$@"
}
