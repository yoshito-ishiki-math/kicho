# shellcheck shell=bash
# Implementation of `kicho submit`.

kicho_command_submit_summary() {
    printf 'Prepare a submission package.\n'
}

kicho_command_submit_usage() {
    cat <<'USAGE'
Usage:
    kicho submit
    kicho submit --arxiv

Create a local submission/ package without uploading it.

Options:
    --arxiv    Create arxiv-source.zip and arxiv-metadata.txt for arXiv.
USAGE
}

kicho_command_submit_examples() {
    cat <<'EXAMPLES'
Examples:
    kicho submit
    kicho submit --arxiv
EXAMPLES
}

kicho_command_submit_requires_project() {
    return 0
}

kicho_command_submit_accepts_arguments() {
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

kicho_submit_write_manifest() {
    local destination="$1"
    local created_at="$2"
    local project="$3"
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

    kicho_archive_write_metadata \
        "$destination" \
        "$created_at" \
        "$project" \
        "$include_git" \
        "$git_branch" \
        "$git_commit" \
        "$git_dirty"
}

kicho_submit_tex_uses_bibliography() {
    local source="$1"

    grep -E '\\(addbibresource|bibliography|printbibliography)(\{|\[|[[:space:]]|$)' \
        "$source" >/dev/null 2>&1
}

kicho_submit_extract_metadata() {
    local source="$1"
    local destination="$2"

    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }

        function append_value(field, value) {
            value = trim(value)
            if (field == "author") {
                if (authors != "") authors = authors ", "
                authors = authors value
            } else if (field == "title") {
                title = value
            } else if (field == "keywords") {
                keywords = value
            } else if (field == "subjclass") {
                subjclass = value
            }
        }

        function consume_command(text, command, field,    start, rest, i, ch, previous) {
            start = index(text, "\\" command)
            if (start == 0) return 0

            rest = substr(text, start + length(command) + 1)
            sub(/^[[:space:]]*/, "", rest)
            if (field == "subjclass" && substr(rest, 1, 1) == "[") {
                sub(/^\[[^]]*\][[:space:]]*/, "", rest)
            }
            if (substr(rest, 1, 1) != "{") return 0

            active = field
            depth = 1
            buffer = ""
            rest = substr(rest, 2)
            previous = ""
            for (i = 1; i <= length(rest); i++) {
                ch = substr(rest, i, 1)
                if (ch == "{" && previous != "\\") depth++
                if (ch == "}" && previous != "\\") depth--
                if (depth == 0) {
                    append_value(active, buffer)
                    active = ""
                    return 1
                }
                buffer = buffer ch
                previous = ch
            }
            return 1
        }

        function continue_command(text,    i, ch, previous) {
            previous = ""
            if (buffer != "") buffer = buffer "\n"
            for (i = 1; i <= length(text); i++) {
                ch = substr(text, i, 1)
                if (ch == "{" && previous != "\\") depth++
                if (ch == "}" && previous != "\\") depth--
                if (depth == 0) {
                    append_value(active, buffer)
                    active = ""
                    return
                }
                buffer = buffer ch
                previous = ch
            }
        }

        {
            if (in_abstract) {
                if ($0 ~ /^[[:space:]]*\\end\{abstract\}/) {
                    in_abstract = 0
                } else {
                    if (abstract != "") abstract = abstract "\n"
                    abstract = abstract $0
                }
                next
            }

            if ($0 ~ /^[[:space:]]*\\begin\{abstract\}/) {
                in_abstract = 1
                next
            }

            if (active != "") {
                continue_command($0)
                next
            }

            consume_command($0, "title", "title")
            consume_command($0, "author", "author")
            consume_command($0, "keywords", "keywords")
            consume_command($0, "subjclass", "subjclass")
        }

        END {
            if (title == "") title = "[Please fill in]"
            if (authors == "") authors = "[Please fill in]"
            if (abstract == "") abstract = "[Please fill in]"
            if (subjclass == "") subjclass = "[Please fill in]"
            if (keywords == "") keywords = "[Please fill in]"

            print "Title:"
            print title
            print ""
            print "Authors:"
            print authors
            print ""
            print "Abstract:"
            print trim(abstract)
            print ""
            print "Comments:"
            print "[Please fill in]"
            print ""
            print "MSC-class:"
            print subjclass
            print ""
            print "Keywords:"
            print keywords
        }
    ' "$source" > "$destination"
}

kicho_submit_validate_metadata() {
    local metadata="$1"
    local abstract_length

    if LC_ALL=C grep '[^ -~]' "$metadata" >/dev/null 2>&1; then
        printf 'Warning: arxiv-metadata.txt contains non-ASCII characters; review them before submission.\n' >&2
    fi

    abstract_length="$(awk '
        /^Abstract:$/ { in_abstract = 1; next }
        in_abstract && /^[A-Za-z-]+:$/ { exit }
        in_abstract {
            if (length($0) == 0 && count == 0) next
            count += length($0)
        }
        END { print count + 0 }
    ' "$metadata")"

    if [[ "$abstract_length" -gt 1920 ]]; then
        printf 'Warning: arXiv abstract is %s characters; the limit is 1920.\n' \
            "$abstract_length" >&2
    fi

    if grep -F '[Please fill in]' "$metadata" >/dev/null 2>&1; then
        printf 'Warning: arxiv-metadata.txt has fields that require review.\n' >&2
    fi
}

kicho_submit_copy_arxiv_styles() {
    local destination="$1"
    local source

    shopt -s nullglob
    for source in ./*.sty ./*.cls ./*.bst; do
        cp "$source" "$destination/" || return 1
    done
    shopt -u nullglob
}

kicho_submit_arxiv() {
    if ! command -v zip >/dev/null 2>&1; then
        kicho_error "'zip' is not installed or not available in PATH."
        return 1
    fi

    if [[ -e "submission" ]]; then
        kicho_error "submission destination already exists: 'submission'."
        return 1
    fi

    if [[ -e "arxiv-metadata.txt" && ! -f "arxiv-metadata.txt" ]]; then
        kicho_error "arxiv-metadata.txt exists but is not a regular file."
        return 1
    fi

    local temporary_directory
    temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/kicho-submit-arxiv.XXXXXX")" || {
        kicho_error "could not create temporary arXiv submission directory."
        return 1
    }

    local source_directory="$temporary_directory/source"
    local package_directory="$temporary_directory/package"
    mkdir -p "$source_directory" "$package_directory"

    if ! kicho_flatten_write "$source_directory/main.tex"; then
        rm -rf "$temporary_directory"
        return 1
    fi

    if [[ -d "figures" ]] && ! cp -R "figures" "$source_directory/figures"; then
        rm -rf "$temporary_directory"
        kicho_error "could not copy arXiv figure files."
        return 1
    fi

    if ! kicho_submit_copy_arxiv_styles "$source_directory"; then
        rm -rf "$temporary_directory"
        kicho_error "could not copy arXiv style files."
        return 1
    fi

    if kicho_submit_tex_uses_bibliography "$source_directory/main.tex"; then
        if [[ ! -f "build/main.bbl" ]]; then
            rm -rf "$temporary_directory"
            kicho_error "build/main.bbl was not found for a document that uses a bibliography."
            printf "Run 'kicho build' before creating the arXiv package.\n" >&2
            return 1
        fi
        if ! cp "build/main.bbl" "$source_directory/main.bbl"; then
            rm -rf "$temporary_directory"
            kicho_error "could not copy build/main.bbl."
            return 1
        fi
    elif [[ -f "build/main.bbl" ]]; then
        if ! cp "build/main.bbl" "$source_directory/main.bbl"; then
            rm -rf "$temporary_directory"
            kicho_error "could not copy build/main.bbl."
            return 1
        fi
    fi

    local metadata_source="arxiv-metadata.txt"
    local generated_metadata="false"
    if [[ -f "$metadata_source" ]]; then
        if ! cp "$metadata_source" "$package_directory/arxiv-metadata.txt"; then
            rm -rf "$temporary_directory"
            kicho_error "could not copy arxiv-metadata.txt."
            return 1
        fi
    else
        generated_metadata="true"
        if ! kicho_submit_extract_metadata \
            "$source_directory/main.tex" \
            "$package_directory/arxiv-metadata.txt"; then
            rm -rf "$temporary_directory"
            kicho_error "could not generate arxiv-metadata.txt."
            return 1
        fi
    fi

    kicho_submit_validate_metadata "$package_directory/arxiv-metadata.txt"

    if ! (
        cd -- "$source_directory" &&
        zip -q -r "$package_directory/arxiv-source.zip" . \
            -x '.*' '*/.*'
    ); then
        rm -rf "$temporary_directory"
        kicho_error "could not create arxiv-source.zip."
        return 1
    fi

    local created_at
    created_at="$(kicho_archive_created_at)"
    local project
    project="$(basename "$PWD")"
    if ! kicho_submit_write_manifest \
        "$package_directory/manifest.json" "$created_at" "$project"; then
        rm -rf "$temporary_directory"
        kicho_error "could not create submission manifest."
        return 1
    fi

    if ! mv "$package_directory" "submission"; then
        rm -rf "$temporary_directory"
        kicho_error "could not create submission directory."
        return 1
    fi

    if [[ "$generated_metadata" == "true" ]]; then
        if ! cp "submission/arxiv-metadata.txt" "$metadata_source"; then
            rm -rf "$temporary_directory"
            kicho_error "submission was created, but arxiv-metadata.txt could not be saved in the project root."
            return 1
        fi
        printf 'Generated metadata draft for review:\n'
        printf '    arxiv-metadata.txt\n'
    fi

    rm -rf "$temporary_directory"
    printf 'Created arXiv submission package:\n'
    printf '    submission/arxiv-source.zip\n'
    printf '    submission/arxiv-metadata.txt\n'
}

kicho_submit_standard() {
    if [[ -e "submission" ]]; then
        kicho_error "submission destination already exists: 'submission'."
        return 1
    fi

    local created_at
    created_at="$(kicho_archive_created_at)"

    local project
    project="$(basename "$PWD")"

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

    if ! kicho_submit_write_manifest \
        "$temporary_directory/manifest.json" "$created_at" "$project"; then
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

kicho_command_submit() {
    case "${1:-}" in
        "")
            if [[ $# -ne 0 ]]; then
                kicho_error "submit does not accept these arguments."
                printf "Run 'kicho help submit' for usage.\n" >&2
                return 1
            fi
            kicho_submit_standard
            ;;
        --arxiv)
            if [[ $# -ne 1 ]]; then
                kicho_error "submit --arxiv does not accept additional arguments."
                printf "Run 'kicho help submit' for usage.\n" >&2
                return 1
            fi
            kicho_submit_arxiv
            ;;
        *)
            kicho_error "submit does not accept arguments other than '--arxiv'."
            printf "Run 'kicho help submit' for usage.\n" >&2
            return 1
            ;;
    esac
}
