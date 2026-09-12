# shellcheck shell=bash
# Implementation of `kicho submit`.

kicho_command_submit_summary() {
    printf 'Prepare a submission package.\n'
}

kicho_command_submit_usage() {
    cat <<'USAGE'
Usage:
    kicho submit [--output DIRECTORY]
    kicho submit --arxiv [--output DIRECTORY]

Create a local submission package without uploading it.

Options:
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

kicho_submit_copy_if_exists() {
    local source="$1"
    local destination="$2"

    if [[ -e "$source" ]]; then
        cp -R "$source" "$destination"
    else
        printf 'Warning: %s not found.\n' "$source" >&2
    fi
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
        "$git_dirty"
}

kicho_submit_tex_uses_bibliography() {
    local source="$1"

    grep -E '\\(addbibresource|bibliography|printbibliography)(\{|\[|[[:space:]]|$)' \
        <(kicho_tex_active_file "$source") >/dev/null 2>&1
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
    local destination="$1"

    if ! command -v zip >/dev/null 2>&1; then
        kicho_error "'zip' is not installed or not available in PATH."
        return 1
    fi

    if ! kicho_submit_check_destination "$destination"; then
        return 1
    fi

    if [[ -L "arxiv-metadata.txt" ]]; then
        kicho_error "arxiv-metadata.txt must not be a symbolic link."
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

    if ! kicho_copy_source_dependencies "$source_directory" arxiv; then
        rm -rf "$temporary_directory"
        return 1
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
    created_at="$(kicho_metadata_created_at)"
    local project
    project="$(basename "$PWD")"
    if ! kicho_submit_write_manifest \
        "$package_directory/manifest.json" "$created_at" "$project"; then
        rm -rf "$temporary_directory"
        kicho_error "could not create submission manifest."
        return 1
    fi

    if [[ "$generated_metadata" == "true" ]]; then
        if [[ -e "$metadata_source" || -L "$metadata_source" ]] ||
            ! cp "$package_directory/arxiv-metadata.txt" "$metadata_source"; then
            rm -rf "$temporary_directory"
            kicho_error "arxiv-metadata.txt could not be saved in the project root."
            return 1
        fi
    fi

    if ! kicho_submit_prepare_destination_parent "$destination" ||
        ! kicho_submit_check_destination "$destination"; then
        if [[ "$generated_metadata" == "true" ]]; then
            rm -f -- "$metadata_source"
        fi
        rm -rf "$temporary_directory"
        return 1
    fi

    if ! mv "$package_directory" "$destination"; then
        if [[ "$generated_metadata" == "true" ]]; then
            rm -f -- "$metadata_source"
        fi
        rm -rf "$temporary_directory"
        kicho_error "could not create submission directory: '$destination'."
        return 1
    fi

    if [[ "$generated_metadata" == "true" ]]; then
        printf 'Generated metadata draft for review:\n'
        printf '    arxiv-metadata.txt\n'
    fi

    rm -rf "$temporary_directory"
    printf 'Created arXiv submission package:\n'
    printf '    %s/arxiv-source.zip\n' "$destination"
    printf '    %s/arxiv-metadata.txt\n' "$destination"
}

kicho_submit_standard() {
    local destination="$1"

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

    if ! kicho_copy_source_dependencies "$temporary_directory" standard; then
        rm -rf "$temporary_directory"
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

    if ! kicho_submit_prepare_destination_parent "$destination" ||
        ! kicho_submit_check_destination "$destination"; then
        rm -rf "$temporary_directory"
        return 1
    fi

    if ! mv "$temporary_directory" "$destination"; then
        rm -rf "$temporary_directory"
        kicho_error "could not create submission directory: '$destination'."
        return 1
    fi

    printf 'Created submission package:\n'
    printf '    %s\n' "$destination"
}

kicho_command_submit() {
    local arxiv="false"
    local destination="submission"
    local output_seen="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    if [[ "$arxiv" == "true" ]]; then
        kicho_submit_arxiv "$destination"
    else
        kicho_submit_standard "$destination"
    fi
}
