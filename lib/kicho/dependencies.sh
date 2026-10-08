# shellcheck shell=bash
# Preserve project-local inputs recorded by the compiler, without parsing TeX.

kicho_collect_recorded_dependencies() {
    local root recorder recorded_root recorded_path line file relative directory physical_directory
    root="$(pwd -P)"
    recorder="$(kicho_project_output fls)"
    KICHO_RECORDED_FILES=()
    [[ -e "$recorder" || -L "$recorder" ]] || return 0
    if [[ -L "$recorder" || ! -f "$recorder" ]]; then
        kicho_error "compiler dependency record is not a regular file: '$recorder'."
        return 1
    fi
    recorded_path="$(awk '/^PWD / { sub(/^PWD /, ""); print; exit }' "$recorder")"
    recorded_root="$recorded_path"
    if [[ -z "$recorded_root" ]] ||
        ! recorded_root="$(cd -- "$recorded_root" 2>/dev/null && pwd -P)" ||
        [[ "$recorded_root" != "$root" ]]; then
        printf "Warning: '%s' belongs to another project root; run 'kicho build' to refresh it.\n" "$recorder" >&2
        return 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == 'INPUT '* ]] || continue
        file="${line#INPUT }"
        if [[ "$file" == /* ]]; then
            if [[ "$file" == "$recorded_path/"* ]]; then
                file="$root/${file#"$recorded_path/"}"
            fi
            kicho_path_is_within_root "$root" "$file" || continue
            relative="${file#"$root/"}"
        else
            relative="$file"
            while [[ "$relative" == ./* ]]; do relative="${relative#./}"; done
        fi
        [[ "$relative" == "$KICHO_MAIN" || "$relative" == "$KICHO_BUILD_DIR/texmf-var/"* ]] && continue
        case "$relative" in
            *.aux|*.bbl|*.blg|*.log|*.fls|*.fdb_latexmk|*.bcf|*.run.xml|*.toc|*.lof|*.lot|*.out|*.synctex|*.synctex.gz) continue ;;
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

# Isolate traversal state from a caller such as check --log. Result files are
# deduplicated once and shared by export copying and freshness diagnostics.
# shellcheck disable=SC2034
kicho_dependencies_collect() {
    local mode="$1" file existing
    local KICHO_SOURCE_QUIET=true KICHO_SOURCE_JSON=true
    [[ "$mode" != export ]] || KICHO_SOURCE_JSON=false
    local KICHO_SOURCE_ROOT KICHO_SOURCE_VISITED='' KICHO_SOURCE_STACK=''
    local KICHO_SOURCE_FILE='' KICHO_SOURCE_LINE=0 KICHO_SOURCE_RESOLVED=''
    local KICHO_SOURCE_DIAGNOSTICS=() KICHO_SOURCE_FILES=() KICHO_SOURCE_KINDS=()
    local KICHO_SOURCE_ERRORS=0 KICHO_SOURCE_WARNINGS=0 KICHO_SOURCE_USES_BIBLIOGRAPHY=false
    local KICHO_SOURCE_GRAPHICS_PATHS=() KICHO_SOURCE_GRAPHICS_DYNAMIC=false
    local KICHO_RECORDED_FILES=()
    kicho_source_init
    if [[ -f "$KICHO_MAIN" ]]; then
        kicho_source_scan_tex_file "$KICHO_SOURCE_ROOT/$KICHO_MAIN" >&2
    fi
    kicho_collect_recorded_dependencies || return 1
    KICHO_DEPENDENCY_ERRORS="$KICHO_SOURCE_ERRORS"
    KICHO_DEPENDENCY_USES_BIBLIOGRAPHY="$KICHO_SOURCE_USES_BIBLIOGRAPHY"
    KICHO_DEPENDENCY_FILES=()
    for file in "${KICHO_SOURCE_FILES[@]}" "${KICHO_RECORDED_FILES[@]}"; do
        for existing in "${KICHO_DEPENDENCY_FILES[@]}"; do
            [[ "$file" != "$existing" ]] || break
        done
        [[ "$file" != "${existing:-}" ]] || continue
        KICHO_DEPENDENCY_FILES+=("$file")
    done
}

kicho_copy_source_dependencies() {
    local destination="$1" mode="$2" file relative root
    root="$(pwd -P)"
    kicho_dependencies_collect export || return 1
    if ((KICHO_DEPENDENCY_ERRORS > 0)) && [[ "$mode" != archive ]]; then
        kicho_error 'submission has missing or unsafe source dependencies.'
        return 1
    fi
    if [[ "$mode" == arxiv && "$KICHO_DEPENDENCY_USES_BIBLIOGRAPHY" == true && ! -f "$(kicho_project_output bbl)" ]]; then
        kicho_error "$(kicho_project_output bbl) was not found for an included document that uses a bibliography."
        return 1
    fi
    for file in "${KICHO_DEPENDENCY_FILES[@]}"; do
        relative="${file#"$root/"}"
        [[ "$relative" != "$KICHO_MAIN" ]] || continue
        [[ "$mode" != arxiv || "$relative" != *.bib ]] || continue
        if ! kicho_prepare_dependency_destination "$destination" "$relative" ||
            ! cp "$file" "$destination/$relative"; then
            kicho_error "could not preserve dependency: '$relative'."
            return 1
        fi
    done
}

# 0: known newer input; 1: no newer input; 2: dependency inspection failed.
kicho_inputs_newer_than() {
    local output="$1" root file
    root="$(pwd -P)"
    kicho_dependencies_collect quiet || return 2
    KICHO_NEWER_INPUT=''
    for file in "$KICHO_MAIN" .latexmkrc kicho.conf "${KICHO_DEPENDENCY_FILES[@]}"; do
        if [[ -f "$file" && "$file" -nt "$output" ]]; then
            KICHO_NEWER_INPUT="${file#"$root/"}"
            return 0
        fi
    done
    return 1
}

kicho_submit_warn_stale_output() {
    local output="$1" status
    [[ -f "$output" ]] || return 0
    if kicho_inputs_newer_than "$output"; then
        printf "Warning: '%s' may be stale; '%s' is newer. Run 'kicho submit --build' to refresh outputs.\n" \
            "$output" "$KICHO_NEWER_INPUT" >&2
    else
        status=$?
        [[ "$status" == 1 ]] || return 1
    fi
    return 0
}

# Copy only visible conventional figures; explicit dependency copies below can
# restore any hidden file actually used by TeX, without exporting hidden junk.
kicho_copy_visible_figures() {
    local destination="$1" file relative
    [[ -d figures ]] || return 0
    mkdir -p "$destination/figures" || return 1
    while IFS= read -r -d '' file; do
        relative="${file#./}"
        kicho_prepare_dependency_destination "$destination" "$relative" || return 1
        cp -R "$file" "$destination/$relative" || return 1
    done < <(find figures -name '.*' -prune -o \( -type f -o -type l \) -print0)
}
