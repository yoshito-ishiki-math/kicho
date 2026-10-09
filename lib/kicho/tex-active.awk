# Mask literal ranges and, optionally, comments without changing line positions.
# Run in the C locale so unchanged UTF-8 source bytes pass through intact.
function masked(end,    value) {
    value = substr(text, position, end - position + 1)
    gsub(/[^\n]/, " ", value)
    output = output value
    position = end + 1
}
function copied(count) {
    output = output substr(text, position, count)
    position += count
}
function argument_position(start,    ch, newline) {
    while (start <= length(text)) {
        ch = substr(text, start, 1)
        if (ch ~ /[[:space:]]/) start++
        else if (ch == "%") {
            newline = index(substr(text, start), "\n")
            start += newline
        } else break
    }
    return start
}
function character(value,    first, count) {
    first = substr(value, 1, 1)
    count = 1
    if (first ~ /[\300-\337]/) count = 2
    else if (first ~ /[\340-\357]/) count = 3
    else if (first ~ /[\360-\367]/) count = 4
    return substr(value, 1, count)
}
{ text = text $0 "\n" }
END {
    position = 1
    while (position <= length(text)) {
        rest = substr(text, position)
        if (environment != "") {
            escaped = environment
            if (substr(escaped, length(escaped), 1) == "*")
                escaped = substr(escaped, 1, length(escaped) - 1) "\\*"
            if (match(rest, "\\\\end[[:space:]]*\\{" escaped "\\}")) {
                masked(position + RSTART + RLENGTH - 2)
                environment = ""
            } else masked(length(text))
            continue
        }
        ch = substr(rest, 1, 1)
        if (ch == "%") {
            count = index(rest, "\n") - 1
            if (keep_comments) copied(count)
            else masked(position + count - 1)
            continue
        }
        if (ch != "\\") { copied(1); continue }
        if (!match(rest, /^\\[A-Za-z@]+/)) { copied(2); continue }
        count = RLENGTH
        command = substr(rest, 2, count - 1)
        if (command == "begin") {
            start = argument_position(position + count)
            if (match(substr(text, start), /^\{[^{}]+\}/)) {
                name = substr(text, start + 1, RLENGTH - 2)
                if (name ~ /^(verbatim\*?|Verbatim\*?|BVerbatim|LVerbatim|lstlisting|minted)$/) {
                    environment = name
                    masked(start + RLENGTH - 1)
                    continue
                }
            }
        }
        if (command == "verb") {
            if (substr(rest, count + 1, 1) == "*") count++
            delimiter = character(substr(rest, count + 1))
            body = substr(rest, count + length(delimiter) + 1)
            end = index(body, delimiter)
            newline = index(body, "\n")
            if (delimiter != "\n" && end && end < newline)
                masked(position + count + 2 * length(delimiter) + end - 2)
            else masked(position + index(rest, "\n") - 2)
            continue
        }
        copied(count)
    }
    printf "%s", output
    if (require_closed && environment != "") {
        printf "Error: unclosed literal environment '%s' in '%s'.\n", environment, FILENAME > "/dev/stderr"
        exit 1
    }
}
