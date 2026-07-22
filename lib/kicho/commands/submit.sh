# shellcheck shell=bash
# Implementation of `kicho submit`.

kicho_command_submit_summary() {
    printf 'Prepare a submission package.\n'
}

kicho_command_submit_usage() {
    cat <<'USAGE'
Usage:
    kicho submit

Create a local submission/ package without uploading it.
USAGE
}

kicho_command_submit_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho submit
EXAMPLES
}

kicho_command_submit_requires_project() {
    return 0
}

kicho_submit_copy_if_exists() {
    local source="$1"
    local destination="$2"

    if [[ -e "$source" ]]; then
        cp -R "$source" "$destination"
    else
        printf 'Warning: %s not found.\n' "$source" >&2
    fi
}

kicho_command_submit() {
    if [[ $# -ne 0 ]]; then
        kicho_error "submit does not accept arguments."
        printf "Run 'kicho help submit' for usage.\n" >&2
        return 1
    fi

    if [[ -e "submission" ]]; then
        kicho_error "submission destination already exists: 'submission'."
        return 1
    fi

    local created_at
    created_at="$(kicho_archive_created_at)"

    local project
    project="$(basename "$PWD")"

    local include_git="false"
    local git_branch=""
    local git_commit=""
    local git_dirty="false"

    if kicho_archive_has_git_metadata; then
        include_git="true"
        git_branch="$(kicho_archive_git_branch)"
        git_commit="$(kicho_archive_git_commit)"
        git_dirty="$(kicho_archive_git_dirty)"
    fi

    local temporary_directory
    temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/kicho-submit.XXXXXX")" || {
        kicho_error "could not create temporary submission directory."
        return 1
    }

    if ! kicho_flatten_write "$temporary_directory/main.tex"; then
        rm -rf "$temporary_directory"
        return 1
    fi

    if ! kicho_submit_copy_if_exists "bib" "$temporary_directory/bib" ||
        ! kicho_submit_copy_if_exists "figures" "$temporary_directory/figures" ||
        ! kicho_submit_copy_if_exists ".latexmkrc" "$temporary_directory/.latexmkrc"; then
        rm -rf "$temporary_directory"
        kicho_error "could not copy submission source files."
        return 1
    fi

    if [[ -f "build/main.pdf" ]]; then
        if ! cp "build/main.pdf" "$temporary_directory/main.pdf"; then
            rm -rf "$temporary_directory"
            kicho_error "could not copy build/main.pdf."
            return 1
        fi
    else
        printf 'Warning: build/main.pdf not found.\n' >&2
    fi

    if ! kicho_archive_write_metadata \
        "$temporary_directory/manifest.json" \
        "$created_at" \
        "$project" \
        "$include_git" \
        "$git_branch" \
        "$git_commit" \
        "$git_dirty"; then
        rm -rf "$temporary_directory"
        kicho_error "could not create submission manifest."
        return 1
    fi

    if ! mv "$temporary_directory" "submission"; then
        rm -rf "$temporary_directory"
        kicho_error "could not create submission directory."
        return 1
    fi

    printf 'Created submission package:\n'
    printf '    submission\n'
}
