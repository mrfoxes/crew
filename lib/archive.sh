# The crew's directory from one crew to the next: crew archive puts a
# session aside, crew reset the whole crew, and crew restore brings either
# back. Each one goes under archive/<date and time>/. Sourced by bin/crew.

# What a session holds: the stream, the cursors, the statuses, the reports,
# and the members' saved work.
ARCHIVE_SESSION="messages seq cursors status reports work"
# What else belongs to a crew, and not to the project or the machine: its
# plan, its Crewfile, its members' tabs, layouts, mutes, kinds, panes,
# threads, and sessions, and the panes crew up opened for the watch and the
# board. The project's rates, forbid, and kinds, the project file, tmp/,
# exports/, archive/, and a clone still on disk stay.
ARCHIVE_CREW="README.md Crewfile tabs layouts muted kind panes nopane threads sessions up"

# Whether the crew <dir> holds something of its own in <entry>: a file, a
# directory with anything in it, or a plan that is not share/plan.md, the
# one crew init writes.
archive_full() {
    case "$2" in
    README.md) [ -f "$1/README.md" ] && ! cmp -s "$1/README.md" "$CREW_HOME/share/plan.md" ;;
    *) [ -f "$1/$2" ] || [ -n "$(ls -A "$1/$2" 2>/dev/null)" ] ;;
    esac
}

# Refuses to <verb> the crew <dir> while a relay runs: its count would go on
# from the stream it read.
archive_relay() {
    if crew_relay_alive "$1"; then
        echo "crew: a relay runs; stop it before the $2" >&2
        return 1
    fi
}

# Makes a free archive/<date and time> in the crew <dir> and prints it. A
# second archive in the same second would move into the first, nested: a
# free name, -2 onward, keeps them apart.
archive_new() {
    an_to=$1/archive/$(date '+%Y-%m-%d-%H%M%S')
    an_base=$an_to
    an_n=1
    while [ -e "$an_to" ]; do
        an_n=$((an_n + 1))
        an_to=$an_base-$an_n
    done
    mkdir -p "$an_to" && echo "$an_to"
}

# The members of the crew <dir> whose clone is no longer on disk, one a
# line: their clones/<name> goes with the crew it belonged to.
archive_gone_clones() {
    for ag_f in "$1"/clones/*; do
        [ -f "$ag_f" ] || continue
        [ -d "$(cat "$ag_f")" ] || basename "$ag_f"
    done
}

# Says, a line each, which member's pane in the crew <dir> still runs its
# agent: once the crew is put aside, it is no member. The pane the command
# runs in is never named.
archive_running() {
    ar_self=""
    for ar_f in "$1"/panes/*; do
        [ -s "$ar_f" ] || continue
        [ -n "$ar_self" ] || ar_self=$(term_self 2>/dev/null) || ar_self=-
        ar_m=$(basename "$ar_f")
        if [ "$(down_state "$1" "$ar_m" "$ar_self")" = running ]; then
            echo "crew: $ar_m's pane $(cat "$ar_f") still runs its agent; it is no member now"
        fi
    done
}

# Puts the session (the stream, the cursors, the statuses, the reports, the
# members' work, and the wake claims) under archive/<date and time>/ and
# starts the stream over, keeping the plan, the rules, the project, the lock,
# the panes, the threads, and the mutes. Not under a relay.
crew_archive() {
    crew_none "crew archive" "$@" || return 2
    dir=$(crew_dir) || return 1
    archive_relay "$dir" archive || return 1
    ac_any=""
    for ac_e in messages status reports work; do
        ! archive_full "$dir" "$ac_e" || ac_any=1
    done
    if [ -z "$ac_any" ]; then
        echo "crew: nothing to archive"
        return
    fi
    to=$(archive_new "$dir") || return 1
    for ac_e in $ARCHIVE_SESSION; do
        [ ! -e "$dir/$ac_e" ] || mv "$dir/$ac_e" "$to/" || return 1
    done
    rm -rf "$dir"/tmp/wake.* "$dir/relay.last"
    crew_skeleton "$dir"
    echo "$to"
}

# Puts the whole crew aside under archive/<date and time>/: its session, as
# crew archive does, and its plan, Crewfile, tabs, layouts, mutes, members,
# and the clones/<name> of a clone gone from disk. Leaves the directory as
# crew init makes it, with the project's and the machine's files kept. Not
# under a relay, and not while the lock is held: a landing is half done.
crew_reset() {
    crew_none "crew reset" "$@" || return 2
    dir=$(crew_dir) || return 1
    archive_relay "$dir" reset || return 1
    if [ -d "$dir/lock" ]; then
        echo "crew: the lock is held by $(cat "$dir/lock/owner" 2>/dev/null || echo someone); let the landing end first" >&2
        return 1
    fi
    re_any=""
    for re_e in $ARCHIVE_SESSION $ARCHIVE_CREW; do
        ! archive_full "$dir" "$re_e" || re_any=1
    done
    re_gone=$(archive_gone_clones "$dir")
    if [ -z "$re_any$re_gone" ]; then
        echo "crew: nothing to reset"
        return
    fi
    archive_running "$dir" >&2
    to=$(archive_new "$dir") || return 1
    for re_e in $ARCHIVE_SESSION $ARCHIVE_CREW; do
        [ ! -e "$dir/$re_e" ] || mv "$dir/$re_e" "$to/" || return 1
    done
    for re_m in $re_gone; do
        mkdir -p "$to/clones"
        mv "$dir/clones/$re_m" "$to/clones/" || return 1
    done
    rm -rf "$dir"/tmp/wake.* "$dir/relay.last"
    crew_skeleton "$dir"
    echo "$to"
}

# The archive <what> of the crew <dir> names: a time from crew archive or
# crew reset, a path when it has a /, the latest by name when empty.
archive_source() {
    if [ -n "$2" ]; then
        story_source "$1" "$2"
        return
    fi
    as_last=$(ls "$1/archive" 2>/dev/null | sort | tail -n 1)
    [ -z "$as_last" ] || echo "$1/archive/$as_last"
}

# Brings back the archive <what>, the latest by default: a session from
# crew archive into the crew as it is, or a whole crew from crew reset. Never
# its panes, nor the panes in its tabs or the ones crew up opened: a pane's
# number may name someone else's pane now. Refuses when the crew has a
# stream of its own, or anything else the archive would put back.
crew_restore() {
    if [ $# -gt 1 ]; then
        echo "usage: crew restore [<archive>]" >&2
        return 2
    fi
    dir=$(crew_dir) || return 1
    archive_relay "$dir" restore || return 1
    from=$(archive_source "$dir" "${1:-}")
    if [ -z "$from" ]; then
        echo "crew: no archive to restore" >&2
        return 1
    fi
    if [ ! -d "$from" ]; then
        echo "crew: no archive at $from" >&2
        return 1
    fi
    rs_back=""
    rs_crew=""
    for rs_e in $ARCHIVE_SESSION $ARCHIVE_CREW; do
        case "$rs_e" in panes | up) continue ;; esac
        [ -e "$from/$rs_e" ] || continue
        rs_back="$rs_back $rs_e"
        case " $ARCHIVE_CREW " in *" $rs_e "*) rs_crew=1 ;; esac
    done
    if [ -z "$rs_back" ] && [ -z "$(ls "$from/clones" 2>/dev/null)" ]; then
        echo "crew: nothing to restore in $from" >&2
        return 1
    fi
    # A session is put back whole or not at all: its cursors alone, read
    # from a stream that is gone, count for nothing.
    for rs_e in messages seq status reports work; do
        if archive_full "$dir" "$rs_e"; then
            echo "crew: the crew has a session of its own ($rs_e/); 'crew archive' or 'crew reset' puts it aside first" >&2
            return 1
        fi
    done
    for rs_e in $rs_back; do
        case " $ARCHIVE_SESSION " in *" $rs_e "*) continue ;; esac
        if archive_full "$dir" "$rs_e"; then
            echo "crew: the crew has its own $rs_e; 'crew reset' puts it aside first" >&2
            return 1
        fi
    done
    for rs_f in "$from"/clones/*; do
        [ -f "$rs_f" ] || continue
        if [ -e "$dir/clones/$(basename "$rs_f")" ]; then
            echo "crew: the crew has a clone for $(basename "$rs_f") already" >&2
            return 1
        fi
    done
    for rs_e in $rs_back; do
        # Only an empty directory, the plan crew init writes, or cursors
        # with no stream are in the way now.
        rm -rf "${dir:?}/$rs_e"
        mv "$from/$rs_e" "$dir/" || return 1
    done
    for rs_f in "$from"/clones/*; do
        [ -f "$rs_f" ] || continue
        mkdir -p "$dir/clones"
        mv "$rs_f" "$dir/clones/" || return 1
    done
    # The panes stay aside when there are any; empty, they say nothing.
    for rs_e in clones panes up; do
        rmdir "$from/$rs_e" 2>/dev/null || :
    done
    for rs_f in "$dir"/tabs/*; do
        [ -f "$rs_f" ] || continue
        grep -Ev '^(iterm|tmux):' "$rs_f" >"$rs_f.new" || :
        if [ -s "$rs_f.new" ]; then
            mv "$rs_f.new" "$rs_f"
        else
            rm -f "$rs_f" "$rs_f.new"
        fi
    done
    crew_skeleton "$dir"
    echo "restored $from"
    if ! rmdir "$from" 2>/dev/null; then
        echo "kept in $from: $(ls "$from" | tr '\n' ' ' | sed 's/ $//')"
    fi
    [ -z "$rs_crew" ] || echo "run 'crew up' to bring the members back"
}
