# Ending a crew: the End: message sent, the Done: messages waited for, what
# is left said, the panes crew up opened stopped, and, when asked, the
# stream archived and the panes of agents that exited closed. It is a file
# of its own, not a part of lib/up.sh, because bringing a crew up and
# ending it share no step, only the two pane files they keep. Its variables
# start with dn_. Sourced by bin/crew.

# The time in seconds, and a pause of <seconds>: the two the wait is made
# of, so that a test replaces them and no test waits.
down_now() {
    date +%s
}

down_sleep() {
    sleep "$1"
}

# The members of the crew <dir> crew down looks at, one a line: the ones
# with a pane, and the ones the Crewfile lists.
down_members() {
    {
        for dn_f in "$1"/panes/*; do
            if [ -s "$dn_f" ]; then
                basename "$dn_f"
            fi
        done
        if [ -f "$(crewfile_path "$1")" ]; then
            crewfile_read "$(crewfile_path "$1")" 2>/dev/null | awk -F '\t' '$1 == "member" { print $3 }'
        fi
    } | sort -u
}

# What <member>'s pane is in the crew <dir>, with <self> the coordinator's
# own pane: none (it has no pane), self (the coordinator's), gone (closed),
# exited (its agent left, a shell is back), or running. A terminal that
# cannot be asked says running: it holds the wait rather than let go.
down_state() {
    dn_pane=$(cat "$1/panes/$2" 2>/dev/null) || dn_pane=""
    if [ -z "$dn_pane" ]; then
        echo none
    elif [ "$dn_pane" = "$3" ]; then
        echo self
    elif term_gone "$dn_pane"; then
        echo gone
    elif ! dn_tty=$(term_tty "$dn_pane" 2>/dev/null); then
        echo running
    elif term_running "$dn_tty"; then
        echo running
    else
        echo exited
    fi
}

# Whether <member> sent a Done: in the crew <dir> after the message <after>.
down_done() {
    for dn_n in $(ls "$1/seq" | sort -n); do
        [ "$dn_n" -gt "$3" ] || continue
        if sed -n 1p "$1/seq/$dn_n" | grep -q "^# [0-9]*\. $2 to [a-z0-9-]*: Done:"; then
            return 0
        fi
    done
    return 1
}

# Posts an End: from the owner, whose word it is, to <to>: the same body for
# every one, which points to the protocol, since the coordinator does not
# know what each member has left to land.
down_say_end() {
    crew_send owner "$1" "$2" <<'EOT'
The owner is ending the crew. Do what "The end" in the protocol says (crew
help): land your work, or save a patch in reports/ and put your files back;
write your report with crew report; then send all Done:, even if you sent one
before. If you are blocked, say what blocks you in the Done:.
EOT
}

# Sends the End: to all, and to each muted one of <members> by name, which a
# message to all does not wake. $dn_after is set to the number of the first.
down_send_end() {
    dn_out=$(down_say_end all "End: land or save a patch, write your report, send Done:") || return 1
    dn_file=$(printf '%s\n' "$dn_out" | head -n 1)
    dn_after=$(basename "$dn_file" | cut -c1-4 | sed 's/^0*//')
    for dn_m in $2; do
        [ -e "$1/muted/$dn_m" ] || continue
        down_say_end "$dn_m" "End: see message $dn_after to all" >/dev/null
    done
}

# Waits until every one of <members> of the crew <dir> has sent a Done: after
# the message <after>, or <minutes> have passed, polling every five seconds.
# A member with no pane, whose pane is gone, or whose agent exited holds
# nothing; the coordinator's own pane, <self>, is not a member to wait for.
# Says each Done: as it comes and who is left when that changes. $dn_done
# holds the members that sent one.
down_wait() {
    dn_end=$(($(down_now) + $2 * 60))
    dn_done=" "
    dn_free=" "
    dn_last=""
    while :; do
        dn_left=""
        term_hold_dir "$1/panes" 2>/dev/null
        for dn_m in $3; do
            case "$dn_done$dn_free" in *" $dn_m "*) continue ;; esac
            if down_done "$1" "$dn_m" "$5"; then
                echo "$dn_m: Done: sent"
                dn_done="$dn_done$dn_m "
                continue
            fi
            dn_state=$(down_state "$1" "$dn_m" "$4")
            case "$dn_state" in
            running)
                dn_left="$dn_left $dn_m"
                continue
                ;;
            esac
            # A member that sends its Done: and leaves in one instant is
            # seen to have left before its Done: is read: read it again.
            if down_done "$1" "$dn_m" "$5"; then
                echo "$dn_m: Done: sent"
                dn_done="$dn_done$dn_m "
                continue
            fi
            case "$dn_state" in
            none) dn_why="has no pane" ;;
            self) dn_why="is this pane, the coordinator's" ;;
            gone) dn_why="has no pane any more" ;;
            exited) dn_why="has exited" ;;
            esac
            echo "$dn_m: $dn_why: the wait does not hold for it"
            dn_free="$dn_free$dn_m "
        done
        term_free
        [ -n "$dn_left" ] || return 0
        [ "$dn_left" = "$dn_last" ] || echo "waiting for:$dn_left"
        dn_last=$dn_left
        [ "$(down_now)" -lt "$dn_end" ] || return 0
        down_sleep 5
    done
}

# The commits of <path> not on its upstream, or on no remote when it has
# none, as "<hash> <subject>", one a line.
down_ahead() {
    if git -C "$1" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
        git -C "$1" log --format='%h %s' '@{u}..HEAD' 2>/dev/null || :
    else
        git -C "$1" log --format='%h %s' HEAD --not --remotes 2>/dev/null || :
    fi
}

# What the checkout at <path>, called <label>, holds that no one has
# pushed: commits, changed files, and stashes, a line each.
down_tree() {
    down_ahead "$2" | while IFS= read -r dn_line; do
        echo "$1: unpushed commit $dn_line"
    done
    git -C "$2" status --porcelain 2>/dev/null | while IFS= read -r dn_line; do
        echo "$1: changed file $dn_line"
    done
    git -C "$2" stash list 2>/dev/null | while IFS= read -r dn_line; do
        echo "$1: stash $dn_line"
    done
}

# What is left in the crew <dir> of the project at <root>, a line each:
# the members of <members> without a Done:, the unpushed work of the shared
# tree and of each clone, the patches in reports/, the commits waiting for a
# review, and the lock.
down_left() {
    dn_held=""
    for dn_m in $3; do
        case "$dn_done" in *" $dn_m "*) continue ;; esac
        [ -n "$dn_held" ] || {
            term_hold_dir "$1/panes" 2>/dev/null
            dn_held=1
        }
        dn_st=$(down_state "$1" "$dn_m" "$4")
        # The coordinator never sends a Done: to itself.
        [ "$dn_st" != self ] || continue
        echo "no Done: from $dn_m ($(printf '%s' "$dn_st" | sed 's/^none$/no pane/'))"
    done
    term_free
    down_tree "the shared tree" "$2"
    for dn_f in "$1"/clones/*; do
        [ -f "$dn_f" ] || continue
        dn_path=$(clone_of "$1" "$(basename "$dn_f")")
        [ ! -d "$dn_path" ] || down_tree "$(basename "$dn_f")'s clone $dn_path" "$dn_path"
    done
    for dn_f in "$1"/reports/*.patch; do
        [ ! -e "$dn_f" ] || echo "patch to apply: $dn_f"
    done
    crew_reviews "$1" | while IFS='	' read -r _ dn_from dn_to dn_hash dn_sub; do
        echo "review waiting: $dn_hash${dn_sub:+ $dn_sub} ($dn_from to $dn_to)"
    done
    if [ -d "$1/lock" ]; then
        echo "the lock is held: $(cat "$1/lock/owner" 2>/dev/null || echo someone)"
    fi
}

# Stops the watch and the board pane crew up opened in the crew <dir> with
# ctrl-c, and forgets them; nothing else is touched. The panes it stopped
# go in $dn_stopped. The coordinator's own pane, <self>, is never one.
down_stop() {
    dn_stopped=""
    for dn_what in watch board; do
        [ -f "$1/up/$dn_what" ] || continue
        dn_pane=$(up_helper "$1" "$dn_what")
        rm -f "$1/up/$dn_what"
        if [ -z "$dn_pane" ] || [ "$dn_pane" = "$2" ]; then
            continue
        fi
        if term_key "$dn_pane" ctrl-c; then
            echo "stopped the $dn_what in $dn_pane"
            dn_stopped="$dn_stopped $dn_pane"
        else
            echo "crew: could not stop the $dn_what in $dn_pane" >&2
        fi
    done
}

# Waits for the relay of the crew <dir> to let go, for up to ten seconds:
# the archive refuses while one runs.
down_relay_off() {
    dn_try=0
    while crew_relay_alive "$1" && [ "$dn_try" -lt 10 ]; do
        down_sleep 1
        dn_try=$((dn_try + 1))
    done
}

# Closes <pane> when nothing runs in it: a pane whose agent still runs is
# never closed, whatever asked.
down_close() {
    if term_gone "$1"; then
        return 0
    fi
    # A pane whose tty crew cannot read may still run its agent: it stays.
    if ! dn_tty=$(term_tty "$1" 2>/dev/null); then
        echo "$1: crew cannot tell what runs there: left open"
        return 0
    fi
    if term_running "$dn_tty"; then
        echo "$1 still runs something: left open"
        return 0
    fi
    term_close "$1" && echo "closed $1"
}

# Closes the panes of <members> whose agent exited, and the ones crew down
# stopped, once they are back at a shell; never the coordinator's, <self>.
down_close_all() {
    for dn_m in $2; do
        [ "$(down_state "$1" "$dn_m" "$3")" = exited ] || continue
        down_close "$(cat "$1/panes/$dn_m")" || echo "crew: could not close $dn_m's pane" >&2
    done
    for dn_pane in $dn_stopped; do
        # ctrl-c takes a moment to bring the shell back.
        dn_try=0
        while dn_tty=$(term_tty "$dn_pane" 2>/dev/null) && term_running "$dn_tty" && [ "$dn_try" -lt 5 ]; do
            down_sleep 1
            dn_try=$((dn_try + 1))
        done
        down_close "$dn_pane" || echo "crew: could not close $dn_pane" >&2
    done
}

# crew down [minutes] [--archive] [--close]: tells the crew it ends (End:,
# from the owner, to all), waits up to <minutes> (15) for a Done: from each
# member, says what is left, stops the watch and the board crew up opened,
# and exits 1 when anything is left. --archive archives the stream when
# nothing is; --close closes the panes whose agent exited.
crew_down() {
    dn_minutes=15
    dn_archive=""
    dn_closing=""
    for dn_arg in "$@"; do
        case "$dn_arg" in
        --archive) dn_archive=1 ;;
        --close) dn_closing=1 ;;
        *)
            crew_count "$dn_arg" "crew down [minutes] [--archive] [--close]" || return 2
            # shellcheck disable=SC2154 # count_n is set by crew_count, in lib/store.sh
            dn_minutes=$count_n
            ;;
        esac
    done
    dir=$(crew_dir) || return 1
    dn_root=$(crew_project "$dir")
    dn_names=$(down_members "$dir")
    # The terminal is asked only when there is a pane to look at.
    dn_self=""
    if [ -n "$dn_names" ] || [ -n "$(ls "$dir/up" 2>/dev/null)" ]; then
        dn_self=$(term_self 2>/dev/null) || dn_self=""
    fi
    dn_done=" "
    if [ -z "$dn_names" ]; then
        echo "nobody to wait for: no member has a pane or a line in the Crewfile"
    else
        down_send_end "$dir" "$dn_names" || return 1
        echo "sent End: to all; waiting up to $dn_minutes minutes for Done:"
        down_wait "$dir" "$dn_minutes" "$dn_names" "$dn_self" "$dn_after"
    fi
    dn_report=$(down_left "$dir" "$dn_root" "$dn_names" "$dn_self")
    if [ -n "$dn_report" ]; then
        echo "left:"
        printf '%s\n' "$dn_report" | sed 's/^/  /'
    else
        echo "nothing is left"
    fi
    down_stop "$dir" "$dn_self"
    dn_status=0
    [ -z "$dn_report" ] || dn_status=1
    if [ -n "$dn_archive" ]; then
        if [ -n "$dn_report" ]; then
            echo "not archived: something is left"
        else
            down_relay_off "$dir"
            if dn_to=$(crew_archive); then
                echo "$dn_to"
                case "$dn_to" in
                */*) crew_story "$dn_to" >"$dn_to/story.md" ;;
                esac
            else
                dn_status=1
            fi
        fi
    fi
    if [ -n "$dn_closing" ]; then
        down_close_all "$dir" "$dn_names" "$dn_self"
    fi
    return "$dn_status"
}
