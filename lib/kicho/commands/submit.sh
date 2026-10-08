# shellcheck shell=bash
# Implementation of `kicho submit`.

kicho_command_submit_summary() {
    printf 'Prepare a submission package.\n'
}

kicho_command_submit_usage() {
    cat <<'USAGE'
Usage:
    kicho submit [--build] [--output DIRECTORY]
    kicho submit --arxiv [--build] [--output DIRECTORY]

Create a local submission package without uploading it.
Paragraph IDs, editorial notes, and showkeys are disabled in the release copy.
A marked standard submission rebuilds its PDF using latexmk. Requires Python 3.9+.

Options:
    --build             Refresh the project PDF, BBL, and recorded dependencies.
    --arxiv             Create an arXiv source ZIP and metadata worksheet.
    -o, --output DIR    Write the package to DIR instead of submission/.
USAGE
}

kicho_command_submit_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho submit
    kicho submit --arxiv
    kicho submit --arxiv --output submissions/revision-2
EXAMPLES
}

kicho_command_submit_requires_project() {
    return 0
}

kicho_command_submit_accepts_arguments() {
    return 0
}

kicho_submit_normalize_destination() {
    local destination="$1"

    if [[ -z "$destination" ]]; then
        kicho_error "submit output directory must not be empty."
        return 1
    fi

    case "$destination" in
        /*)
            kicho_error "submit output must be a relative path: '$destination'."
            return 1
            ;;
    esac

    while [[ "$destination" == ./* ]]; do
        destination="${destination#./}"
    done
    while [[ "$destination" == */ ]]; do
        destination="${destination%/}"
    done

    if [[ -z "$destination" || "$destination" == "." ]]; then
        kicho_error "submit output must name a directory inside the project."
        return 1
    fi

    if kicho_path_has_parent_component "$destination"; then
        kicho_error "submit output does not allow '..' path components: '$destination'."
        return 1
    fi

    printf '%s\n' "$destination"
}

kicho_submit_check_destination() {
    local destination="$1"

    if [[ -e "$destination" || -L "$destination" ]]; then
        kicho_error "submission destination already exists: '$destination'."
        return 1
    fi
}

kicho_submit_prepare_destination_parent() {
    local destination="$1"
    local parent="${destination%/*}"
    if [[ "$parent" == "$destination" ]]; then
        parent="."
    fi

    local existing_parent="$parent"
    while [[ ! -d "$existing_parent" && ! -L "$existing_parent" ]]; do
        if [[ "$existing_parent" != */* ]]; then
            existing_parent="."
            break
        fi
        existing_parent="${existing_parent%/*}"
        [[ -n "$existing_parent" ]] || existing_parent="."
    done

    local project_root
    project_root="$(pwd -P)"
    local physical_parent
    if ! physical_parent="$(cd -- "$existing_parent" 2>/dev/null && pwd -P)"; then
        kicho_error "could not inspect submit output parent: '$parent'."
        return 1
    fi

    if ! kicho_path_is_within_root "$project_root" "$physical_parent"; then
        kicho_error "submit output resolves outside the project: '$destination'."
        return 1
    fi

    if ! mkdir -p "$parent"; then
        kicho_error "could not create submit output parent: '$parent'."
        return 1
    fi

    if ! physical_parent="$(cd -- "$parent" 2>/dev/null && pwd -P)"; then
        kicho_error "could not inspect submit output parent: '$parent'."
        return 1
    fi

    if ! kicho_path_is_within_root "$project_root" "$physical_parent"; then
        kicho_error "submit output resolves outside the project: '$destination'."
        return 1
    fi
}

kicho_submit_write_manifest() {
    local destination="$1"
    local created_at="$2"
    local project="$3"
    local include_git="false"
    local git_branch=""
    local git_commit=""
    local git_dirty="false"

    if kicho_metadata_has_git; then
        include_git="true"
        git_branch="$(kicho_metadata_git_branch)"
        git_commit="$(kicho_metadata_git_commit)"
        git_dirty="$(kicho_metadata_git_dirty)"
    fi

    kicho_metadata_write_manifest \
        "$destination" \
        "$created_at" \
        "$project" \
        "$include_git" \
        "$git_branch" \
        "$git_commit" \
        "$git_dirty" || return 1
    shift 3
    kicho_metadata_add_provenance "$destination" "$(dirname "$destination")" "$@"
}

kicho_submit_rebuild_pdf() (
    local source="$1" build_directory
    if ! command -v latexmk >/dev/null 2>&1; then
        kicho_error "'latexmk' is required to rebuild a submission with editorial marks."
        return 1
    fi
    build_directory="$(mktemp -d "${TMPDIR:-/tmp}/kicho-release-build.XXXXXX")" || return 1
    # Compile another copy so build outputs cannot enter the submission package
    # or overwrite copied source dependencies that happen to live under build/.
    trap '[[ -z "$build_directory" ]] || rm -rf -- "$build_directory"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if ! cp -R "$source/." "$build_directory/"; then
        return 1
    fi
    rm -f -- "$build_directory/build/main.pdf"
    if ! (cd -- "$build_directory" && KICHO_MAIN=main.tex KICHO_BUILD_DIR=build KICHO_JOBNAME=main kicho_command_build) >"$build_directory/release-build.log" 2>&1; then
        cat "$build_directory/release-build.log" >&2
        kicho_error 'could not build the cleaned submission PDF; no package was created.'
        return 1
    fi
    if [[ ! -f "$build_directory/build/main.pdf" ]] ||
        ! cp "$build_directory/build/main.pdf" "$source/main.pdf"; then
        kicho_error 'release build did not produce a fresh build/main.pdf.'
        return 1
    fi
    return 0
)

kicho_submit_standard() (
    local destination="$1" pdf
    pdf="$(kicho_project_output pdf)"

    if ! kicho_submit_check_destination "$destination"; then
        return 1
    fi

    local created_at
    created_at="$(kicho_metadata_created_at)"

    local project
    project="$(basename "$PWD")"

    local temporary_directory
    temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/kicho-submit.XXXXXX")" || {
        kicho_error "could not create temporary submission directory."
        return 1
    }

    trap '[[ -z "$temporary_directory" ]] || rm -rf -- "$temporary_directory"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if ! kicho_flatten_write "$temporary_directory/main.tex"; then
        return 1
    fi

    if ! kicho_copy_if_exists "bib" "$temporary_directory/bib" ||
        ! kicho_copy_if_exists "figures" "$temporary_directory/figures" ||
        ! kicho_copy_if_exists ".latexmkrc" "$temporary_directory/.latexmkrc"; then
        kicho_error "could not copy submission source files."
        return 1
    fi

    if ! kicho_project_write_config "$temporary_directory" main.tex build ||
        ! kicho_copy_source_dependencies "$temporary_directory" standard; then
        return 1
    fi

    if ! kicho_copy_local_styles "$temporary_directory"; then
        return 1
    fi

    local editorial_state
    if ! editorial_state="$(kicho_paraids_run prepare-release --root "$temporary_directory")"; then
        return 1
    fi

    if [[ "$editorial_state" == review ]]; then
        if ! kicho_submit_rebuild_pdf "$temporary_directory"; then
            return 1
        fi
    elif [[ -f "$pdf" ]]; then
        if ! kicho_submit_warn_stale_output "$pdf"; then
            return 1
        fi
        if ! cp "$pdf" "$temporary_directory/main.pdf"; then
            kicho_error "could not copy $pdf."
            return 1
        fi
    else
        printf 'Warning: %s not found.\n' "$pdf" >&2
    fi

    if ! kicho_submit_write_manifest \
        "$temporary_directory/manifest.json" "$created_at" "$project"; then
        kicho_error "could not create submission manifest."
        return 1
    fi

    if ! kicho_submit_prepare_destination_parent "$destination" ||
        ! kicho_submit_check_destination "$destination"; then
        return 1
    fi

    if ! mv "$temporary_directory" "$destination"; then
        kicho_error "could not create submission directory: '$destination'."
        return 1
    fi

    printf 'Created submission package:\n'
    printf '    %s\n' "$destination"
)

kicho_command_submit() {
    local arxiv="false"
    local destination="submission"
    local output_seen="false"
    local build="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build)
                kicho_require_python || return 1
    if [[ "$arxiv" == true ]] && ! command -v zip >/dev/null 2>&1; then
        kicho_error "'zip' is not installed or not available in PATH."
        return 1
    fi
    if [[ "$build" == true ]]; then
                    kicho_error "submit option '--build' was specified more than once."
                    return 1
                fi
                build=true
                shift
                ;;
            --arxiv)
                if [[ "$arxiv" == "true" ]]; then
                    kicho_error "submit option '--arxiv' was specified more than once."
                    return 1
                fi
                arxiv="true"
                shift
                ;;
            -o|--output)
                if [[ "$output_seen" == "true" ]]; then
                    kicho_error "submit output was specified more than once."
                    return 1
                fi
                if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
                    kicho_error "option '$1' requires an output directory."
                    return 1
                fi
                destination="$2"
                output_seen="true"
                shift 2
                ;;
            --output=*)
                if [[ "$output_seen" == "true" ]]; then
                    kicho_error "submit output was specified more than once."
                    return 1
                fi
                destination="${1#*=}"
                if [[ -z "$destination" ]]; then
                    kicho_error "option '--output' requires an output directory."
                    return 1
                fi
                output_seen="true"
                shift
                ;;
            *)
                kicho_error "submit does not accept arguments such as '$1'."
                printf "Run 'kicho help submit' for usage.\n" >&2
                return 1
                ;;
        esac
    done

    if ! destination="$(kicho_submit_normalize_destination "$destination")"; then
        return 1
    fi

    if [[ "$build" == true ]]; then
        kicho_submit_check_destination "$destination" || return 1
        kicho_require_latexmk
        kicho_command_build || return 1
    fi

    if [[ "$arxiv" == "true" ]]; then
        kicho_submit_arxiv "$destination"
    else
        kicho_submit_standard "$destination"
    fi
}
