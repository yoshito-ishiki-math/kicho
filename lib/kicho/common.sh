#!/usr/bin/env bash

set -e

KICHO_BIN_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

KICHO_ROOT="$(
    cd -- "$KICHO_BIN_DIR/.." &&
    pwd
)"

KICHO_LIB_DIR="$KICHO_ROOT/lib/kicho"

source "$KICHO_LIB_DIR/common.sh"
source "$KICHO_LIB_DIR/init.sh"
source "$KICHO_LIB_DIR/build.sh"
source "$KICHO_LIB_DIR/clean.sh"

main() {
    case "${1:-}" in
        "")
            show_help
            ;;

        -h|--help)
            show_help
            ;;

        -v|--version)
            show_version
            ;;

        init)
            init_project "${2:-}"
            ;;

        build)
            build_project
            ;;

        clean)
            clean_project
            ;;

        *)
            error "unknown command '$1'."
            printf "Run 'kicho --help' for usage.\n" >&2
            exit 1
            ;;
    esac
}

main "$@"
