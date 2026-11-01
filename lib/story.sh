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

# The subject of the message <file>: its first line, after the number and
# the names.
story_subject() {
    sed -n '1s/^# [0-9]*\. [^:]*: //p' "$1"
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
# Review: that answered it, or that it still waits for one.
story_commits() {
    s_lines=""
    for n in $(ls "$1/seq" 2>/dev/null | sort -n); do
        s_subject=$(story_subject "$1/seq/$n")
        case "$s_subject" in
        "Pushed: "*) ;;
        *) continue ;;
        esac
        s_hash=$(printf '%s\n' "$s_subject" | awk '{ print $2 }')
        s_from=$(crew_field "$1/seq/$n" From)
        s_to=$(crew_field "$1/seq/$n" To)
        s_review=""
        for m in $(ls "$1/seq" | sort -n); do
            [ "$m" -gt "$n" ] || continue
            s_answer=$(story_subject "$1/seq/$m")
            case "$s_answer" in
            "Review: "*"$s_hash"*)
                s_review=$(printf '%s (%04d, %s)' "$s_answer" "$m" "$(crew_field "$1/seq/$m" From)")
                break
                ;;
            esac
        done
        [ -n "$s_review" ] || s_review="waiting for $s_to's review"
        s_lines="$s_lines- ${s_subject#Pushed: }, landed by $s_from ($(printf '%04d' "$n")), $s_review
"
    done
    [ -n "$s_lines" ] || return 0
    echo
    echo "## The commits"
    echo
    printf '%s' "$s_lines"
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
