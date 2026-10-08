# shellcheck shell=bash
# Preserve project-local inputs recorded by the compiler, without parsing TeX.

kicho_collect_recorded_dependencies() {
    local root recorder recorded_root line file relative directory physical_directory
    root="$(pwd -P)"
    recorder=build/main.fls
    KICHO_RECORDED_FILES=()
    [[ -e "$recorder" || -L "$recorder" ]] || return 0
    if [[ -L "$recorder" || ! -f "$recorder" ]]; then
        kicho_error "compiler dependency record is not a regular file: '$recorder'."
        return 1
    fi
    recorded_root="$(awk '/^PWD / { sub(/^PWD /, ""); print; exit }' "$recorder")"
    if [[ -z "$recorded_root" ]] ||
        ! recorded_root="$(cd -- "$recorded_root" 2>/dev/null && pwd -P)" ||
        [[ "$recorded_root" != "$root" ]]; then
        printf "Warning: build/main.fls belongs to another project root; run 'kicho build' to refresh it.\n" >&2
        return 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == 'INPUT '* ]] || continue
        file="${line#INPUT }"
        if [[ "$file" == /* ]]; then
            kicho_path_is_within_root "$root" "$file" || continue
            relative="${file#"$root/"}"
        else
            relative="$file"
            while [[ "$relative" == ./* ]]; do relative="${relative#./}"; done
        fi
        case "$relative" in
            main.tex|build/texmf-var/*|*.aux|*.bbl|*.blg|*.log|*.fls|*.fdb_latexmk|*.bcf|*.run.xml|*.toc|*.lof|*.lot|*.out|*.synctex|*.synctex.gz) continue ;;
        esac
        if kicho_path_has_parent_component "$relative"; then
            kicho_error "unsafe recorded dependency: '$relative'."
            return 1
        fi
        directory="$(dirname "$relative")"
        if ! physical_directory="$(cd -- "$directory" 2>/dev/null && pwd -P)"; then
            printf "Warning: recorded dependency was not found: '%s'; run 'kicho build' to refresh it.\n" "$relative" >&2
            continue
        fi
        if ! kicho_path_is_within_root "$root" "$physical_directory" || [[ -L "$relative" ]]; then
            kicho_error "recorded dependency is a symbolic link or resolves outside the project: '$relative'."
            return 1
        fi
        if [[ -f "$relative" ]]; then
            KICHO_RECORDED_FILES+=("$root/$relative")
        else
            printf "Warning: recorded dependency was not found: '%s'; run 'kicho build' to refresh it.\n" "$relative" >&2
        fi
    done < "$recorder"
    return 0
}

kicho_copy_recorded_dependencies() {
    local destination="$1" mode="$2" file relative root
    local KICHO_RECORDED_FILES=()
    root="$(pwd -P)"
    kicho_collect_recorded_dependencies || return 1
    for file in "${KICHO_RECORDED_FILES[@]}"; do
        relative="${file#"$root/"}"
        [[ "$mode" == arxiv && "$relative" == *.bib ]] && continue
        if ! kicho_prepare_dependency_destination "$destination" "$relative" ||
            ! cp "$file" "$destination/$relative"; then
            kicho_error "could not preserve recorded dependency: '$relative'."
            return 1
        fi
    done
    return 0
}
