# shellcheck shell=bash
# Summarize warnings already emitted by TeX; do not resolve labels or citations.

# File/line locals are read by source.sh through Bash dynamic scoping.
# shellcheck disable=SC2034
kicho_log_diagnostics() {
    local log number message status
    log="$(kicho_project_output log)"
    local KICHO_SOURCE_FILE="$KICHO_SOURCE_ROOT/$log" KICHO_SOURCE_LINE=0
    if [[ -L "$log" || ! -f "$log" ]]; then
        kicho_source_warn "TeX log is unavailable: '$log'. Run 'kicho build' first."
        return 0
    fi
    if kicho_inputs_newer_than "$log"; then
        kicho_source_warn "TeX log may be stale; '$KICHO_NEWER_INPUT' is newer. Run 'kicho build' to refresh it."
    else
        status=$?
        if [[ "$status" != 1 ]]; then
            kicho_source_warn 'Could not inspect dependencies to establish log freshness.'
        fi
    fi
    while IFS=$'\t' read -r number message; do
        [[ -n "$number" ]] || continue
        KICHO_SOURCE_LINE="$number"
        kicho_source_warn "$message"
    done < <(awk '
        function flush() {
            if (warning ~ /undefined/ && warning ~ /(Citation|Reference)/)
                printf "%d\t%s\n", start, warning
            warning = ""
        }
        /^(LaTeX|Package [[:alnum:]_-]+) Warning:/ {
            flush()
            start = NR
            warning = $0
            next
        }
        warning != "" {
            if ($0 ~ /^[[:space:]]*$/) { flush(); next }
            warning = warning " " $0
        }
        END { flush() }
    ' "$log")
    return 0
}
