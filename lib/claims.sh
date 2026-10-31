# Who claims which files: the Files: line of each status read as paths, the
# warning crew status gives when a path is already claimed, and the board's
# conflicts and unclaimed sections. A responsibility of its own, apart from
# the stream and the statuses it reads (lib/store.sh). Sourced by bin/crew.

# The paths on the Files: line of the status <file>, one a line, in order and
# once each. Commas and spaces separate them (backticks around one are
# dropped), a leading ./ is stripped, and the words that mean no file are
# not paths: none, nothing, n/a, and -.
claims_paths() {
    sed -n 's/^Files:[[:space:]]*//p' "$1" | head -n 1 | tr -s ', `\t' '\n' |
        sed 's|^\./||' | while read -r cl_p; do
        case $(printf '%s' "$cl_p" | tr 'A-Z' 'a-z') in
        "" | none | nothing | n/a | -) ;;
        *) printf '%s\n' "$cl_p" ;;
        esac
    done | awk '!seen[$0]++'
}

# Every claim of the crew, as "<member> <path>" lines, except those of the
# member <skip> (none when not given).
claims_all() {
    for cl_f in "$1"/status/*.md; do
        [ -e "$cl_f" ] || continue
        cl_who=$(basename "$cl_f" .md)
        [ "$cl_who" != "${2:-}" ] || continue
        claims_paths "$cl_f" | sed "s|^|$cl_who |"
    done
}

# Whether the claim <claim> covers <path>: it is the path, or a directory
# (a trailing /) the path is under.
claims_covers() {
    [ "$1" = "$2" ] && return 0
    case "$1" in
    */) case "$2" in "$1"*) return 0 ;; esac ;;
    esac
    return 1
}

# Whether two claims name a common file: one covers the other.
claims_overlap() {
    claims_covers "$1" "$2" || claims_covers "$2" "$1"
}

# Warns, on stderr, of each path on <name>'s Files: line that another
# member's status also lists, with who and how long ago. Only warns: the
# status is written, and the member decides.
claims_warn() {
    claims_all "$1" "$2" | while read -r cl_who cl_theirs; do
        claims_paths "$1/status/$2.md" | while read -r cl_mine; do
            claims_overlap "$cl_mine" "$cl_theirs" || continue
            echo "crew: $cl_mine is also claimed by $cl_who ($cl_theirs on its Files: line, written $(crew_age "$1/status/$cl_who.md") min ago): send it a Heads-up: and wait, or pick another file" >&2
        done
    done
}

# The board's conflicts: each path claimed by two or more members, with who
# lists it. A directory claim counts against every claimed path under it.
claims_conflicts() {
    cl_all=$(claims_all "$1")
    printf '%s\n' "$cl_all" | awk 'NF { print $2 }' | sort -u | while read -r cl_p; do
        cl_who=$(printf '%s\n' "$cl_all" | while read -r cl_w cl_q; do
            ! claims_covers "$cl_q" "$cl_p" || echo "$cl_w"
        done | sort -u | tr '\n' ' ' | sed 's/ $//; s/ /, /g')
        case "$cl_who" in
        *,*) echo "$cl_p: $cl_who" ;;
        esac
    done
}

# The files changed in the project's working tree (renames by their new
# path, untracked files one by one) that are on nobody's Files: line.
# Nothing outside git.
claims_unclaimed() {
    cl_all=$(claims_all "$1")
    git -C "$(crew_project "$1")" status --porcelain -z --untracked-files=all 2>/dev/null |
        tr '\0' '\n' | awk '
            skip { skip = 0; next }
            { print substr($0, 4) }
            /^[RC]/ { skip = 1 }' | while read -r cl_p; do
        cl_taken=
        while read -r _ cl_q; do
            ! claims_covers "$cl_q" "$cl_p" || cl_taken=1
        done <<EOF
$cl_all
EOF
        [ -n "$cl_taken" ] || echo "$cl_p"
    done
}

# Prints a board section: <title> and the lines on stdin, then a blank line,
# or nothing when there is no line.
claims_section() {
    cl_lines=$(cat)
    [ -n "$cl_lines" ] || return 0
    echo "== $1"
    echo "$cl_lines"
    echo
}

# The board's two sections, each only when it has a line.
claims_board_conflicts() {
    claims_conflicts "$1" | claims_section conflicts
}

claims_board_unclaimed() {
    claims_unclaimed "$1" | claims_section unclaimed
}
