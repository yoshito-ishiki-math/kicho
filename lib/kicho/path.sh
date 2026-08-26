# shellcheck shell=bash
# Small shared predicates for project-local path validation.

kicho_path_has_parent_component() {
    case "/$1/" in
        */../*) return 0 ;;
        *) return 1 ;;
    esac
}

kicho_path_is_within_root() {
    local root="$1"
    local physical_path="$2"

    case "$physical_path" in
        "$root"|"$root"/*) return 0 ;;
        *) return 1 ;;
    esac
}
