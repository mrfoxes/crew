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
    where=split
    if [ "$1" = --tab ]; then
        where=tab
        shift
    fi
    root=$(dirname "$dir")
    pane=$(term_spawn "$where" "cd '$root' && $*") || return 1
    echo "$pane" >"$dir/panes/$name"
    echo "$name: $pane"
}

# Tells the recipients of message <n> that it is there: typed into each
# member's pane, as a desktop notification for the owner.
crew_wake() {
    dir=$1
    n=$2
    from=$3
    to=$4
    subject=$5
    case "$to" in
    owner)
        osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
            "crew: $from" "$subject" >/dev/null 2>&1 || true
        return
        ;;
    all) members=$(ls "$dir/panes") ;;
    *) members=$to ;;
    esac
    for who in $members; do
        [ "$who" != "$from" ] && [ -s "$dir/panes/$who" ] || continue
        line=$(printf 'crew: message %04d from %s to %s: %s. Run: crew unread %s' "$n" "$from" "$to" "$subject" "$who")
        term_poke "$(cat "$dir/panes/$who")" "$line" 2>/dev/null ||
            echo "crew: could not wake $who; the message waits in the stream" >&2
    done
}
