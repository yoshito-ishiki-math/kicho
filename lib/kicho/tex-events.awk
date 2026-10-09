# Bounded literal-source lexer. TeX expansion remains the compiler's job.
# Input is comment/verbatim-masked text; events retain command opening lines.
function advance(n,    consumed) {
    consumed = substr(text, position, n)
    line += gsub(/\n/, "", consumed)
    position += n
}
function space() {
    while (substr(text, position, 1) ~ /[[:space:]]/) advance(1)
}
function argument(opening, closing,    start, depth, braces, ch) {
    start = position
    depth = braces = 0
    while (position <= length(text)) {
        ch = substr(text, position, 1)
        if (ch == "\\") { advance(2); continue }
        if (opening == "[" && ch == "{") braces++
        if (opening == "[" && ch == "}") braces--
        if (braces == 0 && ch == opening) depth++
        if (braces == 0 && ch == closing) depth--
        advance(1)
        if (depth == 0) {
            value = substr(text, start + 1, position - start - 2)
            return 1
        }
    }
    return 0
}
function emit(kind, value,    clean) {
    clean = value
    gsub(/\n/, " ", clean)
    sub(/^[[:space:]]+/, "", clean)
    sub(/[[:space:]]+$/, "", clean)
    printf "%d\t%s\t%s\n", start_line, kind, clean
}
{ text = text $0 "\n" }
END {
    position = line = 1
    while (position <= length(text)) {
        start_line = line
        ch = substr(text, position, 1)
        if (ch == "{" || ch == "}") {
            emit(ch == "{" ? "open" : "close", "-")
            advance(1)
            continue
        }
        if (ch != "\\") { advance(1); continue }
        advance(1)
        start = position
        while (substr(text, position, 1) ~ /[[:alpha:]@]/) advance(1)
        command = substr(text, start, position - start)
        if (command == "") { advance(1); continue }
        if (command ~ /^(begingroup|bgroup|endgroup|egroup)$/) {
            emit(command ~ /^(begingroup|bgroup)$/ ? "open" : "close", "-")
            continue
        }
        if (command == "printbibliography") { emit(command, "-"); continue }
        if (command !~ /^(graphicspath|includegraphics|input|include|addbibresource|bibliography|RequirePackageWithOptions|RequirePackage|usepackage|LoadClassWithOptions|LoadClass|documentclass|bibliographystyle|begin|end)$/) continue
        if (command == "includegraphics" && substr(text, position, 1) == "*") advance(1)
        space()
        if (substr(text, position, 1) == "[") {
            if (!argument("[", "]")) { emit("unsupported", command); break }
            space()
        }
        if (substr(text, position, 1) != "{") { emit("unsupported", command); continue }
        if (!argument("{", "}")) { emit("unsupported", command); break }
        if (command == "begin" || command == "end")
            emit(command == "begin" ? "open" : "close", "-")
        else emit(command, value)
    }
}
