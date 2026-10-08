# shellcheck shell=bash
# arXiv source packages and their editable metadata worksheets.

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

kicho_submit_arxiv() (
    local destination="$1" bbl
    bbl="$(kicho_project_output bbl)"

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

    local metadata_owned=false published=false
    trap 'rm -rf -- "$temporary_directory"; if [[ "$metadata_owned" == true && "$published" == false ]]; then rm -f -- arxiv-metadata.txt; fi' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    local source_directory="$temporary_directory/source"
    local package_directory="$temporary_directory/package"
    if ! kicho_submit_warn_stale_output "$bbl"; then
        return 1
    fi
    mkdir -p "$source_directory" "$package_directory" || return 1

    if ! kicho_flatten_write "$source_directory/main.tex"; then
        return 1
    fi

    if ! kicho_copy_visible_figures "$source_directory"; then
        kicho_error "could not copy arXiv figure files."
        return 1
    fi

    if ! kicho_copy_local_styles "$source_directory"; then
        kicho_error "could not copy arXiv style files."
        return 1
    fi

    if kicho_submit_tex_uses_bibliography "$source_directory/main.tex"; then
        if [[ ! -f "$bbl" ]]; then
            kicho_error "$bbl was not found for a document that uses a bibliography."
            printf "Run 'kicho build' before creating the arXiv package.\n" >&2
            return 1
        fi
        if ! cp "$bbl" "$source_directory/main.bbl"; then
            kicho_error "could not copy $bbl."
            return 1
        fi
    elif [[ -f "$bbl" ]]; then
        if ! cp "$bbl" "$source_directory/main.bbl"; then
            kicho_error "could not copy $bbl."
            return 1
        fi
    fi

    if ! kicho_copy_source_dependencies "$source_directory" arxiv; then
        return 1
    fi

    if ! kicho_paraids_run prepare-release --root "$source_directory" >/dev/null; then
        return 1
    fi

    local metadata_source="arxiv-metadata.txt"
    local generated_metadata="false"
    if [[ -f "$metadata_source" ]]; then
        if ! cp "$metadata_source" "$package_directory/arxiv-metadata.txt"; then
            kicho_error "could not copy arxiv-metadata.txt."
            return 1
        fi
    else
        generated_metadata="true"
        if ! kicho_submit_extract_metadata \
            "$source_directory/main.tex" \
            "$package_directory/arxiv-metadata.txt"; then
            kicho_error "could not generate arxiv-metadata.txt."
            return 1
        fi
    fi

    kicho_submit_validate_metadata "$package_directory/arxiv-metadata.txt"

    if ! (
        cd -- "$source_directory" &&
        zip -q -r "$package_directory/arxiv-source.zip" .
    ); then
        kicho_error "could not create arxiv-source.zip."
        return 1
    fi

    local created_at
    created_at="$(kicho_metadata_created_at)"
    local project
    project="$(basename "$PWD")"
    if ! kicho_submit_write_manifest \
        "$package_directory/manifest.json" "$created_at" "$project" --sources "$source_directory"; then
        kicho_error "could not create submission manifest."
        return 1
    fi

    if [[ "$generated_metadata" == "true" ]]; then
        if [[ -e "$metadata_source" || -L "$metadata_source" ]] ||
            ! cp "$package_directory/arxiv-metadata.txt" "$metadata_source"; then
            kicho_error "arxiv-metadata.txt could not be saved in the project root."
            return 1
        fi
        metadata_owned=true
    fi

    if ! kicho_submit_prepare_destination_parent "$destination" ||
        ! kicho_submit_check_destination "$destination"; then
        return 1
    fi

    if ! mv "$package_directory" "$destination"; then
        kicho_error "could not create submission directory: '$destination'."
        return 1
    fi

    published=true
    if [[ "$generated_metadata" == "true" ]]; then
        printf 'Generated metadata draft for review:\n'
        printf '    arxiv-metadata.txt\n'
    fi

    printf 'Created arXiv submission package:\n'
    printf '    %s/arxiv-source.zip\n' "$destination"
    printf '    %s/arxiv-metadata.txt\n' "$destination"
)
