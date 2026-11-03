# shellcheck shell=bash
# Literal author corrections and explicit approval; no inferred approval.

kicho_command_proofread_summary() {
    printf 'Mark corrections in red and apply recorded author approvals.\n'
}

kicho_command_proofread_usage() {
    cat <<'USAGE'
Usage:
    kicho proofread install [--root DIRECTORY]
    kicho proofread new --kind add --new TEXT [--root DIRECTORY]
    kicho proofread new --kind delete --old TEXT [--root DIRECTORY]
    kicho proofread new --kind replace --old TEXT --new TEXT [--root DIRECTORY]
    kicho proofread list [--root DIRECTORY]
    kicho proofread check [--root DIRECTORY]
    kicho proofread approve ID [ID ...] --author NAME [--root DIRECTORY]
    kicho proofread approve --all --author NAME [--root DIRECTORY]

Requires Python 3.9+. Add \usepackage{kichoproof} after installation.
new prints a snippet to insert into your source. Pending corrections stay red.
approve replaces selected marks with accepted text and preserves originals and
an approval manifest in archives/proofread/. Rebuild the PDF after approval.
USAGE
}

kicho_command_proofread_accepts_arguments() {
    return 0
}

kicho_command_proofread() {
    case "${1:-}" in
        install|new|list|check|approve)
            kicho_require_python || return 1
            local build_options=()
            if [[ -n "$KICHO_OPTION_BUILD_SET" ]]; then
                build_options=(--build-dir "$KICHO_OPTION_BUILD")
            elif [[ -n "$KICHO_ENV_BUILD_SET" ]]; then
                build_options=(--build-dir "$KICHO_ENV_BUILD")
            fi
            python3 "$KICHO_LIB_DIR/proofread.py" "$@" "${build_options[@]}"
            ;;
        *)
            kicho_error 'proofread requires install, new, list, check, or approve.'
            printf "Run 'kicho help proofread' for usage.\n" >&2
            return 1
            ;;
    esac
}
