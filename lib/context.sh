# The members' context: crew clear and crew compact, the care of an agent's
# conversation the coordinator gave by hand, made safe. Both act only on an
# agent idle at an empty prompt (lib/screen.sh), never on the pane they run
# in. A clear also refuses a background shell, and a claimed file changed
# after the member's status was written: its Next: could not say where that
# work is. While either runs, wakes to the member are held (tmp/hold/<name>,
# which wake_one honors while the process that wrote it lives), and the
# newest held one is sent once it is over. Its variables start with cx_.
# Sourced by bin/crew.

# The most looks at the pane, each about 2 seconds or more, that a clear,
# the rejoin after it, and a compact are waited for: a minute, half a
# minute, and 10 minutes, since a big context takes minutes to compact.
context_clear_looks=30
context_join_looks=15
context_compact_looks=300

# The command <kind> takes to clear or to compact its conversation, as its
# slash menu lists it, or to quit, as each was ended when its screens were
# captured (restart, for crew up --restart).
context_command() {
    case "$1:$2" in
    claude:clear | agy:clear) echo /clear ;;
    codex:clear) echo /new ;;
    claude:compact | codex:compact | agy:compact) echo /compact ;;
    claude:restart) echo /exit ;;
    codex:restart | agy:restart) echo /quit ;;
    *) return 1 ;;
    esac
}

# The line typed after a clear: the member rejoins, reads its status, and
# resumes from its Next:, in caveman mode ($caveman calls Codex's skill).
context_line() {
    printf 'crew: your context was cleared. Run: crew join %s, then crew status %s, and resume from its Next: line. Work in caveman mode ($caveman) from now on.' "$1" "$1"
}

# crew clear <name>: clears the conversation of <name>'s agent at its idle
# prompt, then has it rejoin and resume from its status's Next:.
crew_clear() {
    if [ $# -ne 1 ]; then
        echo "usage: crew clear <name>" >&2
        return 2
    fi
    context_start clear "$1" || return $?
    context_landed || return 1
    context_hold
    cx_before=$(term_read "$cx_pane" 2>/dev/null) || cx_before=""
    # Codex's /new starts a thread of its own: wakes must not go to the old
    # one, which may still take them; the rejoin writes the new one.
    [ "$cx_kind" != codex ] || rm -f "$cx_dir/threads/$cx_who"
    cx_cmd=$(context_command "$cx_kind" clear)
    if ! term_poke "$cx_pane" "$cx_cmd" 2>/dev/null; then
        context_end "could not type $cx_cmd into $cx_who's pane"
        return 1
    fi
    if ! context_wait "$context_clear_looks" context_cleared; then
        context_end "$cx_who's $cx_cmd did not end within about a minute: its pane shows $cx_state; look with crew peek $cx_who"
        return 1
    fi
    if ! term_poke "$cx_pane" "$(context_line "$cx_who")" 2>/dev/null; then
        context_end "$cx_who was cleared, but the line to rejoin could not be typed: send it with crew poke $cx_who"
        return 1
    fi
    if ! context_wait "$context_join_looks" context_taken; then
        context_end "$cx_who was cleared, but its pane does not show the line to rejoin as taken: look with crew peek $cx_who"
        return 1
    fi
    context_end
    echo "cleared $cx_who: it took the line to rejoin (crew join $cx_who) and to resume from its Next:"
}

# crew compact <name> [instructions]: compacts the conversation of <name>'s
# agent at its idle prompt; instructions go to Claude Code's /compact. Nothing
# is typed after it: a message sent to the member then starts it.
crew_compact() {
    if [ $# -eq 0 ]; then
        echo "usage: crew compact <name> [instructions]" >&2
        return 2
    fi
    cx_who=$1
    shift
    context_start compact "$cx_who" || return $?
    cx_cmd=$(context_command "$cx_kind" compact)
    if [ $# -gt 0 ]; then
        if [ "$cx_kind" != claude ]; then
            echo "crew: only Claude Code's /compact takes instructions; $cx_who is $cx_kind, so nothing was typed" >&2
            return 1
        fi
        cx_cmd="$cx_cmd $*"
    fi
    context_hold
    cx_before=$(term_read "$cx_pane" 2>/dev/null) || cx_before=""
    cx_marks=$(printf '%s\n' "$cx_before" | screen_compacted "$cx_kind")
    cx_seen=""
    if ! term_poke "$cx_pane" "$cx_cmd" 2>/dev/null; then
        context_end "could not type /compact into $cx_who's pane"
        return 1
    fi
    if ! context_wait "$context_compact_looks" context_compacted; then
        context_end "$cx_who's /compact did not end within about 10 minutes: its pane shows $cx_state; look with crew peek $cx_who"
        return 1
    fi
    context_end
    echo "compacted $cx_who"
}

# What must hold before anything is typed, for crew <what> (clear,
# compact, or restart) <name>: a member with a pane of its own, of a kind
# crew knows the command of, not the pane this runs in, idle at an empty
# prompt, and for a clear or a restart with no background shell. Sets cx_who, cx_dir, cx_pane, cx_kind,
# and cx_state.
context_start() {
    cx_what=$1
    cx_who=$2
    crew_name "$cx_who" || return 2
    cx_dir=$(crew_dir) || return 1
    if [ -e "$cx_dir/nopane/$cx_who" ]; then
        echo "crew: $cx_who reads the stream on its own (--no-pane): crew types nothing into its pane, so it cannot $cx_what it" >&2
        return 1
    fi
    cx_pane=$(cat "$cx_dir/panes/$cx_who" 2>/dev/null) || cx_pane=""
    if [ -z "$cx_pane" ]; then
        echo "crew: $cx_who has no pane" >&2
        return 1
    fi
    cx_kind=$(kind_member "$cx_dir" "$cx_who")
    if ! context_command "$cx_kind" "$cx_what" >/dev/null; then
        echo "crew: crew $cx_what knows Claude Code, Codex, and Antigravity; $cx_who is ${cx_kind:-of no kind crew knows}" >&2
        return 1
    fi
    if [ "$(term_self 2>/dev/null)" = "$cx_pane" ]; then
        echo "crew: $cx_who's pane is the one this runs in: crew cannot $cx_what its own pane" >&2
        return 1
    fi
    cx_state=$(screen_state "$cx_dir" "$cx_who")
    case "$cx_state:$cx_what" in
    idle:* | shell:compact) ;;
    shell:clear)
        echo "crew: a background shell runs in $cx_who's pane (its footer says so): a clear would lose who started it; wait until it ends" >&2
        return 1
        ;;
    shell:restart)
        echo "crew: a background shell runs in $cx_who's pane (its footer says so): it would die with the agent; wait until it ends" >&2
        return 1
        ;;
    *)
        echo "crew: $cx_who is not idle at an empty prompt: $(context_said "$cx_state"), so nothing was typed" >&2
        return 1
        ;;
    esac
}

# What <state> of screen_state means, in words.
context_said() {
    case "$1" in
    none) echo "it has no pane" ;;
    gone) echo "its pane is gone" ;;
    exited) echo "its pane runs no agent" ;;
    unknown) echo "its kind draws no input line crew knows" ;;
    dialog) echo "a prompt or a dialog is open in its pane" ;;
    working) echo "it is working" ;;
    typed) echo "text waits on its input line, and crew types nothing over it" ;;
    *) echo "its pane shows $1" ;;
    esac
}

# Whether every changed file the member claims, in its clone or the
# project's tree, is older than its status: then its Next: was written
# after the last change and can say where the work is. Says the first that
# is not, with both ages. A deleted file has no age and is not counted.
context_landed() {
    cx_status=$cx_dir/status/$cx_who.md
    cx_tree=$(clone_of "$cx_dir" "$cx_who")
    [ -n "$cx_tree" ] || cx_tree=$(crew_project "$cx_dir")
    git -C "$cx_tree" rev-parse --git-dir >/dev/null 2>&1 || return 0
    cx_files=$(claims_paths "$cx_status" 2>/dev/null | context_changed "$cx_tree")
    [ -n "$cx_files" ] || return 0
    while IFS= read -r cx_f; do
        [ -n "$cx_f" ] && [ -e "$cx_tree/$cx_f" ] || continue
        if [ ! -f "$cx_status" ]; then
            echo "crew: $cx_who has changes not landed in $cx_f and no status: a clear would lose where it stands; ask it to land, or to write its status with a Next:" >&2
            return 1
        fi
        if [ -n "$(find "$cx_tree/$cx_f" -prune -newer "$cx_status")" ]; then
            echo "crew: $cx_who's $cx_f changed after its status was written (the file $(crew_age "$cx_tree/$cx_f") min ago, the status $(crew_age "$cx_status") min ago) and is not landed: a clear would lose where it stands; ask it to land, or to write its Next:" >&2
            return 1
        fi
    done <<EOF
$cx_files
EOF
}

# The changed and untracked files in the tree <tree> under the paths on
# stdin, one a line, renames by their new path.
context_changed() {
    while IFS= read -r cx_p; do
        [ -z "$cx_p" ] || set -- "$@" "$(land_norm "$cx_p")"
    done
    [ $# -gt 0 ] || return 0
    git --literal-pathspecs -C "$cx_tree" status --porcelain -z --untracked-files=all -- "$@" 2>/dev/null |
        tr '\0' '\n' | awk '
            skip { skip = 0; next }
            { print substr($0, 4) }
            /^[RC]/ { skip = 1 }'
}

# Holds the wakes to the member while this runs, and releases them whatever
# happens: on a signal too, and wake_one ignores a hold whose process is
# gone.
context_hold() {
    mkdir -p "$cx_dir/tmp/hold"
    echo "$$" >"$cx_dir/tmp/hold/$cx_who"
    trap 'rm -f "$cx_dir/tmp/hold/$cx_who"' EXIT
    trap 'rm -f "$cx_dir/tmp/hold/$cx_who"; exit 130' INT TERM HUP
}

# Releases the hold, says <reason> on stderr when there is one, and sends
# the member the newest wake held meanwhile, if it has not read that message
# yet: no relay may be there to send it.
context_end() {
    rm -f "$cx_dir/tmp/hold/$cx_who"
    trap - EXIT INT TERM HUP
    [ -z "${1:-}" ] || echo "crew: $1" >&2
    cx_n=""
    for cx_w in "$cx_dir"/tmp/wake.*."$cx_who"; do
        cx_k=${cx_w#"$cx_dir/tmp/wake."}
        cx_k=${cx_k%".$cx_who"}
        case "$cx_k" in
        "" | *[!0-9]*) continue ;;
        esac
        if [ -z "$cx_n" ] || [ "$cx_k" -gt "$cx_n" ]; then
            cx_n=$cx_k
        fi
    done
    [ -n "$cx_n" ] || return 0
    cx_from=$(cat "$cx_dir/tmp/wake.$cx_n.$cx_who" 2>/dev/null) || cx_from=""
    for cx_w in "$cx_dir"/tmp/wake.*."$cx_who"; do
        [ "$cx_w" = "$cx_dir/tmp/wake.$cx_n.$cx_who" ] || rm -f "$cx_w"
    done
    cx_last=$(cat "$cx_dir/cursors/$cx_who" 2>/dev/null) || cx_last=0
    if [ -n "$cx_from" ] && [ "$cx_n" -gt "${cx_last:-0}" ]; then
        wake_one "$cx_dir" "$cx_n" "$cx_from" "$cx_who" retry || :
    else
        rm -f "$cx_dir/tmp/wake.$cx_n.$cx_who"
    fi
}

# Looks at the pane until <condition> holds, at most <looks> times, a pause
# between two looks.
context_wait() {
    cx_left=$1
    while [ "$cx_left" -gt 0 ]; do
        "$2" && return 0
        cx_left=$((cx_left - 1))
        screen_pause
    done
    return 1
}

# Whether the clear is over: the screen is no longer the one before it, and
# the agent is idle at an empty prompt again.
context_cleared() {
    cx_state=$(screen_state "$cx_dir" "$cx_who")
    case "$cx_state" in
    idle | shell) ;;
    *) return 1 ;;
    esac
    [ "$(term_read "$cx_pane" 2>/dev/null)" != "$cx_before" ]
}

# Whether the line to rejoin was taken: it shows on the screen, and not on
# the input line, where it would wait unsent.
context_taken() {
    cx_now=$(term_read_styled "$cx_pane" 2>/dev/null) || return 1
    cx_state=$(printf '%s\n' "$cx_now" | screen_of "$cx_kind")
    printf '%s\n' "$cx_now" | screen_plain | grep -q 'crew: your context was cleared' || return 1
    cx_text=$(printf '%s\n' "$cx_now" | screen_input "$cx_kind") || cx_text=""
    case "$cx_text" in
    "crew: your context"*) return 1 ;;
    esac
}

# Whether the compact is over: the agent is idle again, and a mark of a
# finished compact came, one more than before, or one after a turn was seen
# (the old mark may have scrolled away).
context_compacted() {
    cx_state=$(screen_state "$cx_dir" "$cx_who")
    case "$cx_state" in
    working) cx_seen=1 ;;
    esac
    case "$cx_state" in
    idle | shell) ;;
    *) return 1 ;;
    esac
    cx_now=$(term_read "$cx_pane" 2>/dev/null | screen_compacted "$cx_kind")
    [ "$cx_now" -gt "$cx_marks" ] || { [ -n "$cx_seen" ] && [ "$cx_now" -gt 0 ]; }
}
