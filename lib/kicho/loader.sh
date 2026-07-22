# Command discovery and dispatch for Kicho.

readonly KICHO_COMMAND_DIR="$KICHO_LIB_DIR/commands"

kicho_command_function_name() {
    local command="$1"
    command="${command//-/_}"
    printf 'kicho_command_%s\n' "$command"
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
}

kicho_list_commands() {
    local command_file
    local command
    local summary_function

    shopt -s nullglob
    for command_file in "$KICHO_COMMAND_DIR"/*.sh; do
        command="$(basename "$command_file" .sh)"
        summary_function="$(kicho_command_function_name "$command")_summary"

        if declare -F "$summary_function" >/dev/null 2>&1; then
            printf '    %-16s ' "$command"
            "$summary_function"
        else
            printf '    %s\n' "$command"
        fi
    done
    shopt -u nullglob
}

kicho_dispatch() {
    local command="${1:-}"

    case "$command" in
        "")
            kicho_show_help
            return
            ;;

        -h|--help|help)
            kicho_show_help
            return
            ;;

        -v|--version|version)
            kicho_show_version
            return
            ;;
    esac

    if [[ ! "$command" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        kicho_error "invalid command name '$command'."
        exit 1
    fi

    local command_function
    command_function="$(kicho_command_function_name "$command")"

    if ! declare -F "$command_function" >/dev/null 2>&1; then
        kicho_error "unknown command '$command'."
        printf "Run 'kicho --help' for usage.\n" >&2
        exit 1
    fi

    shift
    "$command_function" "$@"
}
