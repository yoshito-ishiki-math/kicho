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

# Do not follow symlinks copied with a conventional directory into an export.
kicho_prepare_dependency_destination() {
    local destination="$1" relative="$2" root parent component current
    local components=()
    root="$(cd -- "$destination" && pwd -P)" || return 1
    parent="$(dirname "$relative")"
    IFS='/' read -r -a components <<< "$parent"
    current="$destination"
    for component in "${components[@]}"; do
        [[ "$component" == . || -z "$component" ]] && continue
        current+="/$component"
        if [[ -L "$current" ]]; then
            kicho_error "export dependency directory is a symbolic link: '$relative'."
            return 1
        fi
    done
    if [[ -L "$destination/$relative" ]]; then
        kicho_error "export dependency destination is a symbolic link: '$relative'."
        return 1
    fi
    mkdir -p "$destination/$parent" || return 1
    current="$(cd -- "$destination/$parent" && pwd -P)" || return 1
    kicho_path_is_within_root "$root" "$current"
}
