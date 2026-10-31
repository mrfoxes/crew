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
    crew_member "$name" || return 2
    dir=$(crew_dir) || return 1
    recorded=$(cat "$dir/panes/$name" 2>/dev/null) || recorded=""
    if [ "${2:-}" = --pane ] && [ -n "${3:-}" ]; then
        pane=$3
    elif [ -n "$recorded" ] && ! term_gone "$recorded"; then
        # The pane crew spawn recorded, or an earlier join: a sandbox that
        # hides the pane, or names another, does not lose it.
        pane=$recorded
    else
        pane=$(term_self) || pane=""
        [ -z "$pane" ] || ! term_gone "$pane" || pane=""
    fi
    # The agent this runs under tells its kind; else the one spawn read
    # from its command stays, else it is other.
    kind=$(kind_of_self)
    [ -n "$kind" ] || kind=$(kind_member "$dir" "$name")
    kind_record "$dir" "$name" "${kind:-other}"
    # Codex names its thread: a message is queued to it, pane or no pane.
    if [ -n "${CODEX_THREAD_ID:-}" ]; then
        mkdir -p "$dir/threads"
        echo "$CODEX_THREAD_ID" >"$dir/threads/$name"
    fi
    # Claude Code names its session: crew cost reads its usage from it.
    if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
        mkdir -p "$dir/sessions"
        echo "$CLAUDE_CODE_SESSION_ID" >"$dir/sessions/$name"
    fi
    if [ -n "$pane" ]; then
        echo "$pane" >"$dir/panes/$name"
        crew_label "$pane" "$name" "${kind:-other}" 2>/dev/null || :
        where="in the pane $pane: a message to you is typed into it"
    elif [ -s "$dir/threads/$name" ]; then
        rm -f "$dir/panes/$name"
        where="in no pane crew can find; a message to you is queued to your Codex thread"
    else
        rm -f "$dir/panes/$name"
        where="in no pane crew can find: run 'crew unread $name' often"
    fi
    echo "You are $name, of kind ${kind:-other}, in the crew at $dir, $where."
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

# Forgets <name>'s pane, thread, and kind, and takes its name and color off
# the pane when it is still there: messages to <name> wait in the stream
# from now on.
crew_leave() {
    if [ $# -ne 1 ]; then
        echo "usage: crew leave <name>" >&2
        return 2
    fi
    crew_name "$1" || return 2
    dir=$(crew_dir) || return 1
    pane=$(cat "$dir/panes/$1" 2>/dev/null) || pane=""
    [ -z "$pane" ] || term_gone "$pane" || crew_unlabel "$pane"
    rm -f "$dir/panes/$1" "$dir/threads/$1" "$dir/sessions/$1" "$dir/kind/$1"
    tab_drop "$dir" "$1"
    echo "$1 has no pane now; messages to $1 wait for 'crew unread $1'"
}

# Mutes <name>, marked by muted/<name>: a message to all no longer wakes it,
# one to its name still does, and crew unread shows it both.
crew_mute() {
    if [ $# -ne 1 ]; then
        echo "usage: crew mute <name>" >&2
        return 2
    fi
    crew_member "$1" || return 2
    dir=$(crew_dir) || return 1
    mkdir -p "$dir/muted"
    : >"$dir/muted/$1"
    echo "$1 is muted: a message to all no longer wakes it, one to $1 still does"
}

crew_unmute() {
    if [ $# -ne 1 ]; then
        echo "usage: crew unmute <name>" >&2
        return 2
    fi
    crew_member "$1" || return 2
    dir=$(crew_dir) || return 1
    rm -f "$dir/muted/$1"
    echo "$1 is woken by messages to all again"
}

# A member's name: a name, and neither of the recipients all and owner.
crew_member() {
    crew_name "$1" || return
    case "$1" in all | owner)
        echo "crew: '$1' is a recipient, not a member" >&2
        return 1
        ;;
    esac
}

# Shows <name> on <pane>, and the tab it sits in, out of its agent's reach,
# marked with <kind>'s color unless CREW_COLOR=0. A label that fails says so and leaves the
# pane as it is: naming is no reason to fail a spawn.
crew_label() {
    label=$2
    label_tab=$(tab_of "$(crew_dir)" "$2")
    [ -z "$label_tab" ] || label="$2 · $label_tab"
    term_name "$1" "$label" || echo "crew: could not name the pane $1 $2" >&2
    color=""
    [ "${CREW_COLOR:-1}" = 0 ] || color=$(kind_field "$3" color)
    term_color "$1" "$color" || echo "crew: could not color the pane $1" >&2
}

# Takes the name and the color off <pane>.
crew_unlabel() {
    term_name "$1" "" 2>/dev/null || :
    term_color "$1" "" 2>/dev/null || :
}

# Every pane crew can see, with the member joined to it, its kind, and its
# tab, the members of a tab together, in the order they were placed.
crew_panes() {
    dir=$(crew_dir 2>/dev/null) || dir=""
    term_list | while IFS='	' read -r pane tty title; do
        who=-
        kind=-
        tab=-
        if [ -n "$dir" ]; then
            for f in "$dir"/panes/*; do
                [ -e "$f" ] || continue
                [ "$(cat "$f")" = "$pane" ] && who=$(basename "$f")
            done
            if [ "$who" != - ]; then
                kind=$(kind_member "$dir" "$who")
                tab=$(tab_of "$dir" "$who")
                tab=${tab:--}
            fi
        fi
        order=0
        [ "$tab" = - ] || order=$(grep -nx -- "$who" "$dir/tabs/$tab" | cut -d: -f1) || order=0
        printf '%s\t%s\t%-8s %-7s %-8s %-48s %-14s %s\n' "${tab:--}" "$order" "$who" "${kind:--}" "${tab:--}" "$pane" "$tty" "$title"
    done | sort -s -t '	' -k1,1 -k2,2n | cut -f3-
}

crew_peek() {
    if [ $# -lt 1 ]; then
        echo "usage: crew peek <name> [lines]" >&2
        return 2
    fi
    pane=$(crew_pane "$1") || return 1
    crew_count "${2:-30}" "crew peek <name> [lines]" || return 2
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

# Opens a pane beside this one, in a new tab with --tab, or right of, under,
# or over <member>'s pane with --beside, --below, or --above, running
# <command> in the project's root, joined as <name>, of the kind --kind
# names or the command runs. The agent still runs 'crew join <name>' to
# learn the protocol; its pane is known from the start, and with --join it
# is told to as soon as it is up.
crew_spawn() {
    if [ $# -lt 2 ]; then
        echo "usage: crew spawn <name> [--tab <tab> | --beside|--below|--above <member>] [--join] [--kind <kind>] <command>..." >&2
        return 2
    fi
    name=$1
    shift
    crew_name "$name" || return 2
    dir=$(crew_dir) || return 1
    where='split'
    anchor=""
    join=""
    kind=""
    tab=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --tab)
            shift
            tab=${1:-}
            crew_name "$tab" || return 2
            where=tab
            ;;
        --kind)
            shift
            kind=${1:-}
            if ! kind_known "$kind"; then
                echo "crew: '$kind' is not a kind crew knows: $(kinds_names | tr '\n' ' ')other" >&2
                return 2
            fi
            ;;
        --beside | --below | --above)
            where=${1#--}
            shift
            [ $# -gt 0 ] || break
            anchor=$(crew_pane "$1") || return 1
            ;;
        --join) join=1 ;;
        *) break ;;
        esac
        shift
    done
    if [ $# -eq 0 ]; then
        echo "usage: crew spawn <name> [--tab <tab> | --beside|--below|--above <member>] [--join] [--kind <kind>] <command>..." >&2
        return 2
    fi
    root=$(crew_project "$dir")
    # One argument is a line for the owner's shell; several are a command
    # and its arguments, each kept whole.
    if [ $# -eq 1 ]; then
        line=$1
    else
        line=""
        for word in "$@"; do
            line="$line $(shell_word "$word")"
        done
        line=${line# }
    fi
    # A tab opens for its first member; the next ones are placed beside
    # the last member still there, the tab's row growing.
    if [ -n "$tab" ]; then
        anchor=$(tab_anchor "$dir" "$tab")
        [ -z "$anchor" ] || where=beside
    fi
    pane=$(term_spawn "$where" "cd $(shell_word "$root") && $line" "$anchor") || return 1
    echo "$pane" >"$dir/panes/$name"
    [ -n "$kind" ] || kind=$(kind_of_line "$line")
    kind_record "$dir" "$name" "${kind:-other}"
    if [ -n "$tab" ]; then
        tab_add "$dir" "$tab" "$name"
        [ -n "$anchor" ] || term_tab "$pane" "$tab" || echo "crew: could not name the tab $tab" >&2
        # A tab with a layout puts its new member in its row.
        layout_apply "$dir" "$tab" || echo "crew: $tab is not laid out as it should be; see above" >&2
    elif [ -n "$anchor" ]; then
        # Placed next to a member's pane: in that member's tab.
        anchor_tab=$(tab_of_pane "$dir" "$anchor")
        [ -z "$anchor_tab" ] || tab_add "$dir" "$anchor_tab" "$name"
    fi
    crew_label "$pane" "$name" "${kind:-other}"
    echo "$name: $pane"
    [ -z "$join" ] || crew_invite "$name"
}

# Moves <name>'s pane right of, under, or over <member>'s, its agent still
# running there. The pane keeps its id, so panes/<name> stays as it is.
crew_move() {
    if [ $# -ne 3 ]; then
        echo "usage: crew move <name> --beside|--below|--above <member>" >&2
        return 2
    fi
    case "$2" in
    --beside | --below | --above) where=${2#--} ;;
    *)
        echo "usage: crew move <name> --beside|--below|--above <member>" >&2
        return 2
        ;;
    esac
    pane=$(crew_pane "$1") || return 1
    anchor=$(crew_pane "$3") || return 1
    term_move "$pane" "$where" "$anchor" || return 1
    echo "$1: $pane, now $where $3"
}

# Waits until the agent in <name>'s pane is up and ready for a line, at
# most <seconds> (60), then tells it to join and to work in caveman mode:
# $caveman in a prompt is what calls Codex's skill of that name. Up is
# something other than a shell in the foreground of the pane's tty; ready
# is its kind's input line drawn on two reads in a row (share/kinds), or
# two reads alike: an idle agent may redraw a hint or a notice every few
# seconds. A prompt waiting there (a trust dialog) is printed instead:
# answer it with crew key, then invite again. A line typed before the agent
# is up would go to the shell. Giving up, it says which of the two never
# came.
crew_invite() {
    if [ $# -lt 1 ]; then
        echo "usage: crew invite <name> [seconds]" >&2
        return 2
    fi
    name=$1
    crew_count "${2:-60}" "crew invite <name> [seconds]" || return 2
    pane=$(crew_pane "$name") || return 1
    tty=$(term_tty "$pane") || return 1
    kind=$(kind_member "$(crew_dir)" "$name")
    before=""
    drawn=""
    up=""
    i=0
    while :; do
        screen=$(term_read "$pane" 2>/dev/null) || screen=""
        # A screen counts only with the agent up: one the shell drew is
        # never ready.
        if [ -n "$screen" ] && term_running "$tty"; then
            up=1
        else
            screen=""
        fi
        was=$drawn
        drawn=""
        if [ -n "$screen" ] && printf '%s\n' "$screen" | kind_drawn "$kind"; then
            drawn=1
        fi
        ready=""
        [ -z "$screen" ] || [ "$screen" != "$before" ] || ready=1
        [ -z "$drawn" ] || [ -z "$was" ] || ready=1
        if [ -n "$ready" ]; then
            prompt=$(printf '%s\n' "$screen" | gate_prompt | cut -f2)
            if [ -n "$prompt" ]; then
                echo "crew: $name waits on a prompt: $prompt" >&2
                echo "crew: answer it with 'crew key $name ...', then 'crew invite $name'" >&2
                return 1
            fi
            crew_poke "$name" "Run: crew join $name. Then follow the protocol it prints. Work in caveman mode (\$caveman) from now on."
            echo "$name invited"
            return
        fi
        before=$screen
        i=$((i + 1))
        if [ "$i" -gt "${2:-60}" ]; then
            if [ -z "$up" ]; then
                echo "crew: nothing but a shell in $name's pane after ${2:-60} seconds" >&2
            else
                echo "crew: $name's agent runs, but after ${2:-60} seconds its screen has not settled, nor shown its input line" >&2
                echo "crew: see it with 'crew peek $name', then 'crew invite $name' again or 'crew poke $name ...'" >&2
            fi
            return 1
        fi
        sleep 1
    done
}

# <word> as the owner's shell reads it back whole: bare when it holds nothing
# the shell would read, else in single quotes, its own single quotes escaped
# the way sh, bash, zsh, and fish all read them.
shell_word() {
    case "$1" in
    "" | *[!A-Za-z0-9_./:,@+-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
    esac
}

# Tells the recipients of message <n> that it is there: one line, queued to
# a Codex member's thread or typed into the member's pane, a desktop
# notification for the owner. The line holds the number, the sender, and
# the command, never the subject: an agent may read a character of free
# text (@, $) as a command of its own. A member with no pane, or none at
# all, is named: the message waits in the stream. So is a muted member, for
# a message to all.
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
    all) members=$( (ls "$dir/panes" && ls "$dir/threads" 2>/dev/null) | sort -u) ;;
    *) members=$to ;;
    esac
    for who in $members; do
        [ "$who" != "$from" ] || continue
        if [ "$to" = all ] && [ -e "$dir/muted/$who" ]; then
            echo "crew: $who is muted; the message waits for 'crew unread $who'" >&2
            continue
        fi
        line=$(printf 'crew: message %04d from %s. Run: crew unread %s' "$n" "$from" "$who")
        # Codex takes the line through its daemon, which needs no terminal;
        # its pane is the way when the thread is gone.
        if [ -s "$dir/threads/$who" ] &&
            codex queue --thread "$(cat "$dir/threads/$who")" --message "$line" >/dev/null 2>&1; then
            continue
        fi
        if [ ! -s "$dir/panes/$who" ]; then
            echo "crew: $who has no pane; the message waits for 'crew unread $who'" >&2
            continue
        fi
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
    crew_relay_start "$dir" || return 1
    # A signal ends the loop, not just the sleep it interrupts.
    trap 'rm -f "$dir/relay.pid"' EXIT
    trap exit INT TERM
    echo "$(crew_stamp) relay: waking for $dir"
    while :; do
        crew_relay_beat "$dir"
        sleep 1
    done
}

# Gets a relay for <dir> ready: refuses while one runs, and notes the last
# number sent, since the messages before now were woken by their senders.
crew_relay_start() {
    if crew_relay_alive "$1"; then
        echo "crew: a relay runs already (pid $(cat "$1/relay.pid"))" >&2
        return 1
    fi
    ls "$1/seq" | sort -n | tail -n 1 >"$1/relay.last"
}

# One beat of the relay for <dir>: the heartbeat, whose age tells crew send
# whether a relay runs, then a step.
crew_relay_beat() {
    echo $$ >"$1/relay.pid"
    crew_relay_step "$1" "$1/relay.last"
}

# One step of the relay: wakes the recipients of every message past the
# number in <last> that its sender did not wake (tmp/wake.<n> is the claim,
# made by whoever wakes first), one line each, and writes the last number
# seen there.
crew_relay_step() {
    dir=$1
    lastfile=$2
    last=$(cat "$lastfile" 2>/dev/null)
    last=${last:-0}
    for n in $(ls "$dir/seq" | sort -n); do
        [ "$n" -gt "$last" ] || continue
        echo "$n" >"$lastfile"
        mkdir "$dir/tmp/wake.$n" 2>/dev/null || continue
        f=$dir/seq/$n
        from=$(crew_field "$f" From)
        to=$(crew_field "$f" To)
        crew_wake "$dir" "$n" "$from" "$to" "$(sed -n "1s/^# [0-9]*\. $from to $to: //p" "$f")"
        printf '%s relay: %04d from %s to %s\n' "$(crew_stamp)" "$n" "$from" "$to"
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
