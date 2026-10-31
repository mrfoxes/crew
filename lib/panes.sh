# The crew's panes: who sits in which, and what the coordinator does with
# them. .crew/panes/<name> holds <name>'s pane. Sourced by bin/crew.

# The pane of <name>, or <name> itself when it is a pane already
# (iterm:<id>, tmux:<id>), so an unjoined pane can be reached too.
crew_pane() {
    case "$1" in
    iterm:* | tmux:*)
        echo "$1"
        return
        ;;
    esac
    crew_name "$1" || return 2
    dir=$(crew_dir) || return 1
    if [ ! -s "$dir/panes/$1" ]; then
        echo "crew: $1 has no pane: '$1' runs 'crew join $1' in it, or see 'crew panes'" >&2
        return 1
    fi
    cat "$dir/panes/$1"
}

# Registers the pane this runs in as <name>'s, or the one given with --pane,
# then prints the protocol, the crew's plan, and <name>'s unread messages.
crew_join() {
    if [ $# -lt 1 ]; then
        echo "usage: crew join <name> [--pane <pane>]" >&2
        return 2
    fi
    name=$1
    crew_name "$name" || return 2
    case "$name" in all | owner)
        echo "crew: '$name' is a recipient, not a member" >&2
        return 2
        ;;
    esac
    dir=$(crew_dir) || return 1
    if [ "${2:-}" = --pane ] && [ -n "${3:-}" ]; then
        pane=$3
    else
        pane=$(term_self) || pane=""
    fi
    if [ -n "$pane" ]; then
        echo "$pane" >"$dir/panes/$name"
        where="in the pane $pane: a message to you is typed into it"
    else
        rm -f "$dir/panes/$name"
        where="in no pane crew can find: run 'crew unread $name' often"
    fi
    echo "You are $name, in the crew at $dir, $where."
    echo
    cat "$CREW_HOME/share/protocol.md"
    if [ -f "$dir/README.md" ]; then
        echo
        echo "## The plan for this crew ($dir/README.md)"
        echo
        cat "$dir/README.md"
    fi
    echo
    echo "## Your unread messages"
    crew_unread "$name"
}

# Every pane crew can see, with the member joined to it.
crew_panes() {
    dir=$(crew_dir 2>/dev/null) || dir=""
    term_list | while IFS='	' read -r pane tty title; do
        who=-
        if [ -n "$dir" ]; then
            for f in "$dir"/panes/*; do
                [ -e "$f" ] || continue
                [ "$(cat "$f")" = "$pane" ] && who=$(basename "$f")
            done
        fi
        printf '%-8s %-48s %-14s %s\n' "$who" "$pane" "$tty" "$title"
    done
}

crew_peek() {
    if [ $# -lt 1 ]; then
        echo "usage: crew peek <name> [lines]" >&2
        return 2
    fi
    pane=$(crew_pane "$1") || return 1
    term_read "$pane" | grep -v '^[[:space:]]*$' | tail -n "${2:-30}"
}

crew_poke() {
    if [ $# -lt 2 ]; then
        echo "usage: crew poke <name> <line>" >&2
        return 2
    fi
    pane=$(crew_pane "$1") || return 1
    shift
    term_poke "$pane" "$*"
}

crew_key() {
    if [ $# -lt 2 ]; then
        echo "usage: crew key <name> <key>..." >&2
        return 2
    fi
    pane=$(crew_pane "$1") || return 1
    shift
    for k in "$@"; do
        term_key "$pane" "$k" || return
        sleep 0.2
    done
}

# Opens a pane beside this one running <command> in the project's root,
# joined as <name>. The agent still runs 'crew join <name>' to learn the
# protocol; its pane is known from the start.
crew_spawn() {
    if [ $# -lt 2 ]; then
        echo "usage: crew spawn <name> [--tab] <command>..." >&2
        return 2
    fi
    name=$1
    shift
    crew_name "$name" || return 2
    dir=$(crew_dir) || return 1
    where='split'
    if [ "$1" = --tab ]; then
        where=tab
        shift
    fi
    root=$(crew_project "$dir")
    pane=$(term_spawn "$where" "cd '$root' && $*") || return 1
    echo "$pane" >"$dir/panes/$name"
    echo "$name: $pane"
}

# Tells the recipients of message <n> that it is there: typed into each
# member's pane as one line, a desktop notification for the owner. The line
# holds the number, the sender, and the command, never the subject: an agent
# may read a character of free text (@, $) as a command of its own. A member
# with no pane, or none at all, is named: the message waits in the stream.
crew_wake() {
    dir=$1
    n=$2
    from=$3
    to=$4
    subject=$5
    case "$to" in
    owner)
        crew_notify "crew: $from" "$subject" ||
            echo "crew: no notifier for owner here; the message waits in the stream" >&2
        return
        ;;
    all) members=$(ls "$dir/panes") ;;
    *) members=$to ;;
    esac
    for who in $members; do
        [ "$who" != "$from" ] || continue
        if [ ! -s "$dir/panes/$who" ]; then
            echo "crew: $who has no pane; the message waits for 'crew unread $who'" >&2
            continue
        fi
        line=$(printf 'crew: message %04d from %s. Run: crew unread %s' "$n" "$from" "$who")
        term_poke "$(cat "$dir/panes/$who")" "$line" 2>/dev/null ||
            echo "crew: could not wake $who; the message waits in the stream" >&2
    done
}

# A desktop notification for the owner: macOS through osascript, Linux
# through notify-send. Fails where there is neither.
crew_notify() {
    if command -v osascript >/dev/null 2>&1; then
        osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$1" "$2" >/dev/null 2>&1
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send "$1" "$2" >/dev/null 2>&1
    else
        return 1
    fi
}

# The relay wakes the recipients of every new message from outside the
# senders' sandboxes: Codex's cannot reach iTerm2, so a message it sends
# wakes nobody by itself. The coordinator runs 'crew relay' in a pane of
# their own; while it runs, 'crew send' leaves the waking to it.
crew_relay() {
    dir=$(crew_dir) || return 1
    if crew_relay_alive "$dir"; then
        echo "crew: a relay runs already (pid $(cat "$dir/relay.pid"))" >&2
        return 1
    fi
    # Messages sent before now were woken by their senders.
    last=$dir/relay.last
    ls "$dir/seq" | sort -n | tail -n 1 >"$last"
    trap 'rm -f "$dir/relay.pid"' EXIT INT TERM
    echo "relay: waking for $dir"
    while :; do
        # Rewritten every second: its age tells crew send whether a relay runs.
        echo $$ >"$dir/relay.pid"
        crew_relay_step "$dir" "$last"
        sleep 1
    done
}

# One step of the relay: wakes the recipients of every message past the
# number in <last>, one line each, and writes the last number woken there.
crew_relay_step() {
    dir=$1
    lastfile=$2
    last=$(cat "$lastfile" 2>/dev/null)
    last=${last:-0}
    for n in $(ls "$dir/seq" | sort -n); do
        [ "$n" -gt "$last" ] || continue
        f=$dir/seq/$n
        from=$(crew_field "$f" From)
        to=$(crew_field "$f" To)
        crew_wake "$dir" "$n" "$from" "$to" "$(sed -n "1s/^# [0-9]*\. $from to $to: //p" "$f")"
        printf 'relay: %04d from %s to %s\n' "$n" "$from" "$to"
        echo "$n" >"$lastfile"
    done
}

# Whether a relay runs for <dir>: its pid file was rewritten in the last
# five seconds. Read, not signalled, so a sandbox can tell too.
crew_relay_alive() {
    f=$1/relay.pid
    [ -f "$f" ] || return 1
    age=$(($(date +%s) - $(crew_mtime "$f")))
    [ "$age" -le 5 ]
}
