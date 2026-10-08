# shellcheck shell=bash
# Literal project paths; never source or evaluate project configuration.

KICHO_ENV_MAIN_SET="${KICHO_MAIN+x}"
KICHO_ENV_MAIN="${KICHO_MAIN-}"
KICHO_ENV_BUILD_SET="${KICHO_BUILD_DIR+x}"
KICHO_ENV_BUILD="${KICHO_BUILD_DIR-}"
KICHO_OPTION_MAIN_SET=''
KICHO_OPTION_BUILD_SET=''
KICHO_MAIN=main.tex
KICHO_BUILD_DIR=build
KICHO_JOBNAME=main

kicho_project_options() {
    local option value
    while [[ $# -gt 0 ]]; do
        option="$1"
        case "$option" in
            --main|--build-dir)
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    kicho_error "$option requires a path."
                    return 1
                fi
                value="$2"
                shift 2
                ;;
            --main=*|--build-dir=*)
                value="${option#*=}"
                option="${option%%=*}"
                shift
                ;;
            *) break ;;
        esac
        case "$option" in
            --main)
                [[ -z "$KICHO_OPTION_MAIN_SET" ]] || { kicho_error 'duplicate --main option.'; return 1; }
                KICHO_OPTION_MAIN_SET=true
                KICHO_OPTION_MAIN="$value"
                ;;
            --build-dir)
                [[ -z "$KICHO_OPTION_BUILD_SET" ]] || { kicho_error 'duplicate --build-dir option.'; return 1; }
                KICHO_OPTION_BUILD_SET=true
                KICHO_OPTION_BUILD="$value"
                ;;
        esac
    done
    # Remaining arguments are consumed by bin/kicho.
    # shellcheck disable=SC2034
    KICHO_ARGUMENTS=("$@")
}

kicho_project_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

kicho_project_normalize_path() {
    local component result='' components=()
    IFS='/' read -r -a components <<< "$1"
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . ]] || continue
        [[ -z "$result" ]] || result+='/'
        result+="$component"
    done
    printf '%s\n' "$result"
}

kicho_project_validate_path() {
    local path="$1" description="$2" component current='.'
    local components=()
    if [[ -z "$path" || "$path" == /* || "$path" == -* || "$path" == . || "$path" == *$'\n'* || "$path" == *$'\r'* ]] ||
        kicho_path_has_parent_component "$path"; then
        kicho_error "$description must be a nonempty project-relative path without '..': '$path'."
        return 1
    fi
    IFS='/' read -r -a components <<< "$path"
    for component in "${components[@]}"; do
        [[ -z "$component" || "$component" == . ]] && continue
        current+="/$component"
        if [[ -L "$current" ]]; then
            kicho_error "$description does not follow symbolic links: '$path'."
            return 1
        fi
    done
    case "/$path/" in
        */.git/*|*/.agents/*|*/.codex/*)
            kicho_error "$description uses a reserved directory: '$path'."
            return 1 ;;
    esac
}

kicho_project_load() {
    local line key value main_seen='' build_seen=''
    KICHO_MAIN=main.tex
    KICHO_BUILD_DIR=build
    if [[ -L kicho.conf || ( -e kicho.conf && ! -f kicho.conf ) ]]; then
        kicho_error 'kicho.conf must be a regular file, not a symbolic link.'
        return 1
    fi
    if [[ -f kicho.conf ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="$(kicho_project_trim "$line")"
            [[ -n "$line" && "$line" != \#* ]] || continue
            if [[ "$line" != *=* ]]; then
                kicho_error "invalid kicho.conf setting: '$line'."
                return 1
            fi
            key="$(kicho_project_trim "${line%%=*}")"
            value="$(kicho_project_trim "${line#*=}")"
            case "$key" in
                main)
                    [[ -z "$main_seen" ]] || { kicho_error 'duplicate main in kicho.conf.'; return 1; }
                    main_seen=true
                    KICHO_MAIN="$value" ;;
                build_dir)
                    [[ -z "$build_seen" ]] || { kicho_error 'duplicate build_dir in kicho.conf.'; return 1; }
                    build_seen=true
                    KICHO_BUILD_DIR="$value" ;;
                *) kicho_error "unknown kicho.conf key: '$key'."; return 1 ;;
            esac
            [[ -n "$value" ]] || { kicho_error "empty kicho.conf value for '$key'."; return 1; }
        done < kicho.conf
    fi
    [[ -z "$KICHO_ENV_MAIN_SET" ]] || KICHO_MAIN="$KICHO_ENV_MAIN"
    [[ -z "$KICHO_ENV_BUILD_SET" ]] || KICHO_BUILD_DIR="$KICHO_ENV_BUILD"
    [[ -z "$KICHO_OPTION_MAIN_SET" ]] || KICHO_MAIN="$KICHO_OPTION_MAIN"
    [[ -z "$KICHO_OPTION_BUILD_SET" ]] || KICHO_BUILD_DIR="$KICHO_OPTION_BUILD"
    kicho_project_validate_path "$KICHO_MAIN" 'main file' || return 1
    kicho_project_validate_path "$KICHO_BUILD_DIR" 'build directory' || return 1
    KICHO_MAIN="$(kicho_project_normalize_path "$KICHO_MAIN")"
    KICHO_BUILD_DIR="$(kicho_project_normalize_path "$KICHO_BUILD_DIR")"
    [[ -n "$KICHO_MAIN" && -n "$KICHO_BUILD_DIR" ]] || { kicho_error 'project paths must not name the project root.'; return 1; }
    if [[ "$KICHO_MAIN" != *.tex ]]; then
        kicho_error 'main file must have a .tex extension.'
        return 1
    fi
    case "$KICHO_BUILD_DIR" in
        archives|archives/*|submission|submission/*|submissions|submissions/*|dist|dist/*)
            kicho_error "build directory is reserved for exports: '$KICHO_BUILD_DIR'."; return 1 ;;
    esac
    if [[ "$KICHO_MAIN" == "$KICHO_BUILD_DIR"/* ]]; then
        kicho_error 'build directory must not contain the main source.'
        return 1
    fi
    KICHO_JOBNAME="${KICHO_MAIN##*/}"
    KICHO_JOBNAME="${KICHO_JOBNAME%.tex}"
}

kicho_project_output() {
    printf '%s/%s.%s\n' "$KICHO_BUILD_DIR" "$KICHO_JOBNAME" "$1"
}

kicho_project_write_config() {
    printf 'main = %s\nbuild_dir = %s\n' "$2" "$3" > "$1/kicho.conf"
}
