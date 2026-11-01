# The session as one document: crew story writes the plan, the Crewfile,
# the members, the stream, the commits landed with their reviews, and the
# reports as Markdown on stdout, from the live crew or from an archive, so
# that the owner can read a session whole and hand it to someone. Sourced
# by bin/crew.

# Where the stream, the statuses, and the reports of <what> are, in the
# crew <dir>: the crew itself when <what> is empty, a path when it has a /,
# else archive/<what>, as crew archive names them.
story_source() {
    case "$2" in
    "") echo "$1" ;;
    */*) echo "$2" ;;
    *) echo "$1/archive/$2" ;;
    esac
}

# The plan and the Crewfile of the crew <dir>, whole, when it has them.
story_plan() {
    if [ -f "$1/README.md" ]; then
        echo
        echo "## The plan"
        echo
        cat "$1/README.md"
    fi
    if [ -f "$1/Crewfile" ]; then
        echo
        echo "## The Crewfile"
        echo
        echo '```'
        cat "$1/Crewfile"
        echo '```'
    fi
}

# The members of the crew <dir> whose session is in <src>: one with a
# status there, a pane, a thread, a session, or a kind; a line each with
# its kind, tab, clone, reviewer, and what it spent.
story_members() {
    s_names=$( (for f in "$2"/status/*.md; do [ -e "$f" ] && basename "$f" .md; done; cost_members "$1") | sort -u)
    [ -n "$s_names" ] || return 0
    echo
    echo "## The members"
    echo
    for s_who in $s_names; do
        s_kind=$(kind_member "$1" "$s_who")
        s_tab=$(tab_of "$1" "$s_who")
        s_clone=$(clone_of "$1" "$s_who")
        s_reviewer=$(crewfile_get "$1" "$s_who" reviewer)
        s_spent=$(cost_sum board "$1" "$s_who" | sed -n "1s/^ *$s_who *//p")
        echo "- $s_who (${s_kind:-no kind}${s_tab:+, tab $s_tab}${s_clone:+, clone $s_clone}${s_reviewer:+, reviewed by $s_reviewer})${s_spent:+: $s_spent}"
    done
}

# The stream of <src>, every message whole, in order.
story_stream() {
    [ -n "$(ls "$1/seq" 2>/dev/null)" ] || return 0
    echo
    echo "## The stream"
    for n in $(ls "$1/seq" | sort -n); do
        echo
        cat "$1/seq/$n"
    done
}

# The commits landed in <src>: each Pushed: with who landed it, and the
# Review: that answered it, or that it still waits for one. One awk pass
# reads every header (the number, From, To, and the subject), so a long
# session costs no more than its messages.
story_commits() {
    s_src=$1
    set --
    for n in $(ls "$s_src/seq" | sort -n); do
        set -- "$@" "$s_src/seq/$n"
    done
    [ $# -gt 0 ] || return 0
    s_lines=$(awk '
        FNR == 1 {
            i++
            match($0, /^# [0-9]+\./)
            number[i] = substr($0, 3, RLENGTH - 3)
            subject[i] = $0
            sub(/^# [0-9]+\. [^:]*: /, "", subject[i])
        }
        FNR == 3 { from[i] = $0; sub(/^From: /, "", from[i]) }
        FNR == 4 { to[i] = $0; sub(/^To: /, "", to[i]) }
        END {
            for (p = 1; p <= i; p++) {
                if (subject[p] !~ /^Pushed: /) continue
                rest = substr(subject[p], 9)
                hash = rest
                sub(/ .*/, "", hash)
                review = ""
                for (r = p + 1; r <= i; r++) {
                    if (subject[r] ~ /^Review: / && index(subject[r], hash) > 0) {
                        review = subject[r] " (" number[r] ", " from[r] ")"
                        break
                    }
                }
                if (review == "") review = "waiting for " to[p] "'"'"'s review"
                printf "- %s, landed by %s (%s), %s\n", rest, from[p], number[p], review
            }
        }' "$@")
    [ -n "$s_lines" ] || return 0
    echo
    echo "## The commits"
    echo
    printf '%s\n' "$s_lines"
}

# The reports in <src>, each under the member's name, and the patches left.
story_reports() {
    [ -n "$(ls "$1/reports" 2>/dev/null)" ] || return 0
    echo
    echo "## The reports"
    for f in "$1"/reports/*.md; do
        [ -e "$f" ] || continue
        echo
        echo "### $(basename "$f" .md)"
        echo
        cat "$f"
    done
    for f in "$1"/reports/*.patch; do
        [ -e "$f" ] || continue
        echo
        echo "A patch left by $(basename "$f" .patch): reports/$(basename "$f")"
    done
}

# The session as one document, on stdout: the live crew's, or the archive
# <what> (a time from crew archive, or a path).
crew_story() {
    if [ $# -gt 1 ]; then
        echo "usage: crew story [<archive>]" >&2
        return 2
    fi
    dir=$(crew_dir) || return 1
    src=$(story_source "$dir" "${1:-}")
    if [ ! -d "$src/seq" ]; then
        echo "crew: no session at $src" >&2
        return 1
    fi
    s_first=$(ls "$src/seq" | sort -n | head -n 1)
    s_last=$(ls "$src/seq" | sort -n | tail -n 1)
    echo "# The crew of $(basename "$(crew_project "$dir")")"
    echo
    if [ -n "$s_first" ]; then
        echo "From $(crew_field "$src/seq/$s_first" Time) to $(crew_field "$src/seq/$s_last" Time): $(ls "$src/seq" | wc -l | tr -d ' ') messages."
    else
        echo "No message yet."
    fi
    story_plan "$dir"
    story_members "$dir" "$src"
    story_stream "$src"
    story_commits "$src"
    story_reports "$src"
}
