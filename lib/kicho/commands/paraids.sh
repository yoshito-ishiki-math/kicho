# shellcheck shell=bash
# Kicho owns paragraphids.sty and the shared literal-ID helper.

kicho_command_paraids_summary() {
    printf 'Install, issue, find, and check stable paragraph IDs.\n'
}

kicho_command_paraids_usage() {
    cat <<'USAGE'
Usage:
    kicho paraids install [--root DIRECTORY]
    kicho paraids new [--root PATH] [--count N]
    kicho paraids find ID [--root PATH] [--include-comments]
    kicho paraids check [--root PATH] [--include-comments]

The root defaults to the current directory. Requires Python 3.9 or later.
Installation never overwrites a different package or edits manuscript text.
New-ID generation reserves commented IDs. Scope searches to the active draft.
Submission commands disable the marks in their staging copy automatically.
USAGE
}

kicho_command_paraids_accepts_arguments() {
    return 0
}

kicho_paraids_run() {
    kicho_require_python || return 1
    python3 "$KICHO_LIB_DIR/paraids.py" "$@"
}

kicho_command_paraids() {
    case "${1:-}" in
        install|new|find|check) kicho_paraids_run "$@" ;;
        *)
            kicho_error 'paraids requires install, new, find, or check.'
            printf "Run 'kicho help paraids' for usage.\n" >&2
            return 1
            ;;
    esac
}
