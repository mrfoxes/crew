# The gate: answers an agent's approval prompts for the owner, and holds the
# commands the rules forbid for the coordinator to decide. Sourced by bin/crew.

# Reads a screen on stdin and prints the approval prompt waiting at its
# bottom as "<kind><tab><command><tab><command unwrapped>", or nothing:
#
#   codex   "Would you like to run the following command?", "$ <command>",
#           "1. Yes, proceed", answered with y
#   claude  "Bash command", the command between two rules (╌╌╌), "Do you
#           want to proceed?", the cursor on "1. Yes", answered with Return
#   other   any other menu near the bottom: a cursor (❯, ›, >) on a choice
#           and a choice below it, with the question above: never answered,
#           always held. A question with no choices under it is not a prompt.
#
# A Claude Code prompt is read only when it is the last question on the
# screen and "Bash command" is its own header: a prompt of another tool that
# asks the same question, with a Bash prompt still drawn above it, is "other".
# A command wrapped across lines comes twice, joined with spaces and without,
# so a wrap inside a word cannot hide it from the rules.
gate_prompt() {
    awk '
        {
            gsub(/│|┃|╭|╮|╰|╯|─/, "")
            sub(/^[ \t]+/, "")
            sub(/[ \t]+$/, "")
            if ($0 != "") line[++n] = $0
        }
        function out(kind, from, to,    i, l, wide, tight) {
            for (i = from; i <= to; i++) {
                l = line[i]
                if (i == from) sub(/^\$ /, "", l)
                wide = wide (wide == "" ? "" : " ") l
                tight = tight l
            }
            printf "%s\t%s\t%s\n", kind, wide, tight
        }
        END {
            # Codex: the last line of the screen asks for Return or Esc.
            if (n > 0 && line[n] ~ /^Press enter to confirm or esc to cancel/) {
                for (i = n; i > 0 && line[i] !~ /^Would you like to run the following command\?/; i--) ;
                if (i > 0) {
                    for (c = i; c <= n && line[c] !~ /^\$ /; c++) ;
                    for (e = c; e <= n && line[e] !~ /^(› *)?1\. Yes, proceed/; e++) ;
                    if (c < e && e <= n) { out("codex", c, e - 1); exit }
                }
            }
            # Claude Code: "Do you want to proceed?" with the cursor on "1. Yes".
            for (q = n; q > 0 && q > n - 16 && line[q] !~ /^Do you want to proceed\?$/; q--) ;
            if (q > 0 && q > n - 16 && line[q + 1] ~ /^❯ *1\. Yes$/) {
                # A question below it belongs to a newer prompt.
                for (t = q + 2; t <= n && line[t] !~ /\?$/; t++) ;
                # The header is its own only when no other prompt, with its
                # question or its options, stands between the two. The
                # command between the rules is skipped whole, and above the
                # rules a line ending in ? is the description, not a question.
                crossed = 0
                for (h = q - 1; h > 0 && line[h] !~ /^Bash command/ && line[h] !~ /^(❯ *)?[0-9]+\. /; h--) {
                    if (line[h] ~ /^╌/) {
                        for (h--; h > 0 && line[h] !~ /^╌/; h--) ;
                        crossed = 1
                    } else if (!crossed && line[h] ~ /\?$/) break
                }
                if (t > n && h > 0 && line[h] ~ /^Bash command/ && h + 1 < q) {
                    # The command stands between two rules, below the description.
                    for (c = h + 1; c < q && line[c] !~ /^╌/; c++) ;
                    for (e = c + 1; e < q && line[e] !~ /^╌/; e++) ;
                    if (c < q && e < q && c + 1 < e) out("claude", c + 1, e - 1)
                    else out("claude", h + 1, q - 1)
                    exit
                }
            }
            # Any other menu waiting at the bottom, under at most a few lines
            # of hints: a cursor on a choice with another choice below it. A
            # question the agent asks, with no choices under it, is not a
            # prompt. The text starts at the nearest question above the cursor.
            for (c = n; c > 0 && c > n - 8; c--)
                if (line[c] ~ /^(❯|›|>) +[^ ]/ && c < n && line[c + 1] ~ /^([0-9]+\. |Yes|No|Allow|Deny)/) {
                    for (q = c - 1; q > 0 && q > c - 6 && line[q] !~ /\?( |$)/; q--) ;
                    if (q <= 0 || q <= c - 6) q = c
                    e = c + 2 > n ? n : c + 2
                    out("other", q, e)
                    exit
                }
        }'
}

# Reads a screen on stdin and, when the menu at its bottom asks to trust the
# folder the agent runs in, prints how many lines the choice that trusts it
# stands below the cursor (above it when negative); prints nothing for any
# other screen. The choices, as the agents draw them:
#
#   claude  "Yes, I trust this folder", under the cursor on "No, exit"
#   codex   "1. Trust and continue", the cursor on it
#   agy     "Yes, I trust this folder", the cursor on it
gate_trust() {
    awk '
        {
            gsub(/│|┃|╭|╮|╰|╯|─/, "")
            sub(/^[ \t]+/, "")
            sub(/[ \t]+$/, "")
            if ($0 != "") line[++n] = $0
        }
        END {
            for (c = n; c > 0 && c > n - 8 && line[c] !~ /^(❯|›|>) +[^ ]/; c--) ;
            if (c <= 0 || c <= n - 8) exit
            # The menu: the choices around the cursor, up to a hint (a line
            # with a ·) or a question.
            for (i = c - 3; i <= c + 3; i++) {
                if (i < 1 || i > n) continue
                if (i > c && line[i] ~ /·|\?$/) break
                l = line[i]
                sub(/^(❯|›|>) +/, "", l)
                sub(/^[0-9]+\. +/, "", l)
                if (l ~ /^(Yes, I trust this folder|Trust and continue)$/) { print i - c; exit }
            }
        }'
}

# Prints the first rule of the file <rules> that <command> breaks, and fails
# when it breaks none. Lines starting with ! are exceptions, cut out of the
# command before the rules are tried.
gate_forbidden() {
    GATE_COMMAND=$2 awk '
        /^#/ || /^[ \t]*$/ { next }
        /^!/ { allow[++a] = substr($0, 2); next }
        { rule[++r] = $0 }
        END {
            command = ENVIRON["GATE_COMMAND"]
            # A wrapper (env VAR=value, command, nice, time) and git'"'"'s
            # global options do not hide the subcommand.
            word = "('"'"'[^'"'"']*'"'"'|\"[^\"]*\"|[^ ]+)"
            wrap = "(^|[ ;&|(])(env|command|nice|time)( +(-n +[0-9]+|[A-Za-z_][A-Za-z_0-9]*=[^ ]*))* +git( |$)"
            while (match(command, wrap)) {
                pre = substr(command, 1, RSTART - 1)
                lead = substr(command, RSTART, 1)
                command = pre (lead ~ /[ ;&|(]/ ? lead : "") "git " substr(command, RSTART + RLENGTH)
            }
            while (gsub("git +-[Cc] +" word, "git", command) \
                || gsub("git +--(git-dir|work-tree|namespace|exec-path|super-prefix|config-env) +" word, "git", command) \
                || gsub("git +--(git-dir|work-tree|namespace|exec-path|super-prefix|config-env)=" word, "git", command) \
                || gsub("git +(--no-pager|--paginate|-p|-P|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--no-advice)( |$)", "git ", command)) ;
            for (i = 1; i <= a; i++) gsub(allow[i], "", command)
            for (i = 1; i <= r; i++)
                if (command ~ rule[i]) { print rule[i]; exit 0 }
            exit 1
        }' "$1"
}

# One look at <name>'s pane <pane>: answers the prompt waiting there, holds
# it, or does nothing. What a look remembers for the next one lives in
# $gate_state: held/<name> is the last prompt reported, answered/<name> the
# screen a prompt was answered on, so a screen not redrawn yet is not
# answered twice. The screen stays in $screen, and $screen_read says it was
# read, for gate_tend to use without reading again.
gate_look() {
    name=$1
    pane=$2
    held=$gate_state/held/$name
    answered=$gate_state/answered/$name
    screen_read=""
    screen=$(term_read "$pane" 2>/dev/null) || {
        gate_say "$held" "gate: cannot read $name's pane $pane"
        return
    }
    screen_read=1
    prompt=$(printf '%s\n' "$screen" | gate_prompt)
    if [ -z "$prompt" ]; then
        rm -f "$held" "$answered"
        gate_end held "$name"
        return
    fi
    [ "$screen" != "$(cat "$answered" 2>/dev/null)" ] || return 0
    kind=$(printf '%s' "$prompt" | cut -f1)
    command=$(printf '%s' "$prompt" | cut -f2)
    tight=$(printf '%s' "$prompt" | cut -f3)
    case "$kind" in
    other) why="not a command" ;;
    *)
        # The crew's own forbid is looked for at each prompt, so one
        # written while the gate runs counts at once; rules that cannot
        # be read hold the prompt.
        rules=$gate_rules
        [ ! -f "${dir:-}/forbid" ] || rules=$dir/forbid
        if [ ! -r "$rules" ]; then
            why="no rules in $rules"
        else
            why=$(gate_forbidden "$rules" "$command") || why=$(gate_forbidden "$rules" "$tight") || why=""
        fi
        ;;
    esac
    # The key that answers yes is the kind's (share/kinds): a kind with
    # none has its prompts held.
    if [ -z "$why" ]; then
        key=$(kind_field "$kind" approve)
        [ -n "$key" ] || why="no key approves a $kind prompt"
    fi
    if [ -n "$why" ]; then
        gate_say "$held" "HOLD $name ($why): $command"
        if gate_new held "$name" "$command"; then
            gate_notify "$name" "HOLD: $(gate_short "$command"). Look: crew focus $name. Answer: crew key $name <key>..."
        fi
        return
    fi
    if [ "$gate_dry" = --dry ]; then
        gate_say "$held" "would approve $name: $command"
        return
    fi
    # The prompt read a moment ago may be gone: answered by the owner,
    # withdrawn, scrolled away. A key then lands in the agent's composer, so
    # read again and press only for the same prompt.
    [ "$(term_read "$pane" 2>/dev/null | gate_prompt)" = "$prompt" ] || return 0
    # A press that fails (the terminal busy, the pane just closed) is said
    # once and tried again at the next look: the gate itself goes on.
    term_key "$pane" "$key" 2>/dev/null || {
        gate_say "$held" "gate: cannot press $key in $name's pane $pane"
        return 0
    }
    echo "$(crew_stamp) approved $name: $command"
    printf '%s' "$screen" >"$answered"
    rm -f "$held"
    gate_end held "$name"
}

# Prints <line>, with the time, unless it is the one already in <file>, and
# keeps it there.
gate_say() {
    [ "$2" != "$(cat "$1" 2>/dev/null)" ] || return 0
    echo "$(crew_stamp) $2"
    printf '%s' "$2" >"$1"
}

# Watches the panes of <name>... every two seconds and prints one line a
# prompt, and one a member that needs the owner:
#
#   21:45:03 approved codex: cargo test --test editors
#   21:47:10 HOLD codex (git +reset): git reset --hard
#   21:52:31 exited claude: its agent is gone, its pane is back to a shell
#
# With --dry it answers nothing and says what it would do. A held prompt and
# each of those events is also a desktop notification, once (see gate_tend).
crew_gate() {
    gate_setup "$@" || return
    # A signal ends the loop, not just the sleep it interrupts.
    trap 'rm -rf "$gate_state"' EXIT
    trap exit INT TERM
    while :; do
        gate_round
        sleep 2
    done
}

# The gate and the relay in one pane: 'crew watch <name>... [--dry]'
# answers their prompts and wakes the recipients of every message.
crew_watch() {
    gate_setup "$@" || return
    crew_relay_start "$dir" || return 1
    trap 'rm -rf "$gate_state" "$dir/relay.pid"' EXIT
    trap exit INT TERM
    echo "$(crew_stamp) relay: waking for $dir"
    while :; do
        crew_relay_beat "$dir"
        gate_round
        sleep 2
    done
}

# Reads the gate's arguments into $names, $gate_all, $gate_dry, and
# $gate_to, finds the rules and the panes, and makes the state directory
# $gate_state under the crew's tmp. --all watches every member with a pane,
# read again at each round, so that a member spawned later is watched too;
# --to <name> names who hears of a member with nothing to do (gate_idle).
gate_setup() {
    gate_dry=""
    gate_all=""
    gate_to=""
    names=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --dry) gate_dry=--dry ;;
        --all) gate_all=1 ;;
        --to)
            if [ $# -lt 2 ]; then
                names=""
                gate_all=""
                break
            fi
            gate_to=$2
            shift
            ;;
        *) names="$names $1" ;;
        esac
        shift
    done
    if [ -z "$names" ] && [ -z "$gate_all" ]; then
        echo "usage: crew gate <name>... | --all [--dry] [--to <name>], or crew watch the same" >&2
        return 2
    fi
    dir=$(crew_dir) || return 1
    # The default rules; a crew's own forbid replaces them, at each prompt.
    gate_rules=$CREW_HOME/share/forbid
    gate_state=$(mktemp -d "$dir/tmp/gate.XXXXXX") || return 1
    gate_dirs "$gate_state"
    for name in $names; do
        crew_pane "$name" >"$gate_state/pane/$name" || return 1
    done
}

# With --all, the members with a pane now, and their panes.
gate_members() {
    [ -n "${gate_all:-}" ] || return 0
    names=""
    for m_file in "$dir"/panes/*; do
        [ -s "$m_file" ] || continue
        m_name=$(basename "$m_file")
        names="$names $m_name"
        cat "$m_file" >"$gate_state/pane/$m_name"
    done
}

# Makes the directories of the state directory <dir>: held/ and answered/
# (see gate_look), pane/ (the pane of each member), told/<event>/ (what the
# owner was told, see gate_new), up/ (members whose agent ran at a look),
# and seen/ (the screen of each member and since when it is unchanged).
gate_dirs() {
    mkdir -p "$1/held" "$1/answered" "$1/pane" "$1/up" "$1/seen" \
        "$1/told/held" "$1/told/exited" "$1/told/gone" "$1/told/idle" \
        "$1/told/budget"
}

# One look at every pane the gate watches, and a check that its member is
# still there, from one listing of their terminals a round.
gate_round() {
    gate_clock=""
    if [ -n "$(gate_idle_minutes)" ]; then
        gate_clock=$(gate_now)
    fi
    gate_members
    term_hold_dir "$gate_state/pane" 2>/dev/null
    for name in $names; do
        pane=$(cat "$gate_state/pane/$name")
        gate_look "$name" "$pane"
        gate_tend "$name" "$pane"
    done
    term_free
    gate_budgets
}

# Once a minute, the members whose Crewfile line gives a budget= against
# what they spent (crew cost): at 80% and at 100% the owner is told, once
# each, with the command that keeps the member from being woken by all;
# crew never mutes or stops an agent by itself. A member crew cannot price
# is said once. told/budget/<name> keeps the last threshold told.
gate_budgets() {
    b_now=$(gate_now)
    [ $((b_now - ${gate_budget_at:-0})) -ge 60 ] || return 0
    gate_budget_at=$b_now
    for b_name in $names; do
        b_budget=$(crewfile_get "$dir" "$b_name" budget)
        [ -n "$b_budget" ] || continue
        b_spent=$(cost_spent "$dir" "$b_name")
        if [ -z "$b_spent" ]; then
            if gate_new budget "$b_name" unpriced; then
                echo "$(crew_stamp) budget $b_name: \$$b_budget, but no rate prices its model: crew cost $b_name"
            fi
            continue
        fi
        b_level=$(awk -v s="$b_spent" -v b="$b_budget" 'BEGIN { p = (b > 0 ? s * 100 / b : 100); print (p >= 100 ? 100 : (p >= 80 ? 80 : 0)) }')
        [ "$b_level" != 0 ] || continue
        gate_new budget "$b_name" "$b_level" || continue
        echo "$(crew_stamp) budget $b_name: \$$b_spent of \$$b_budget ($b_level%)"
        gate_notify "$b_name" "Spent \$$b_spent of its \$$b_budget budget ($b_level%). Keep it from messages to all: crew mute $b_name"
    done
}

# The time, in seconds since the epoch; a function so that a test can set it.
gate_now() {
    date +%s
}

# The minutes a member may sit idle with nothing to do before the watch
# tells: 5, or CREW_IDLE_MINUTES when it is a positive number; nothing for
# 0, which turns the check off. Five is more than a CI run and far more
# than the coordinator takes to answer an Idle:, in its same turn.
gate_idle_minutes() {
    case "${CREW_IDLE_MINUTES:-}" in
    '' | *[!0-9]*) echo 5 ;;
    *) printf '%s\n' "$CREW_IDLE_MINUTES" | sed 's/^0*//; /^$/d' ;;
    esac
}

# Whether the event <event> of <name> is new, and if so remembers <key> as
# told: told/<event>/<name> holds the key of the last one, so that an event
# is told once while it lasts, and a different key (another held prompt in
# its place) is a new one. gate_end forgets it once the event is over.
gate_new() {
    if [ "$3" = "$(cat "$gate_state/told/$1/$2" 2>/dev/null)" ]; then
        return 1
    fi
    printf '%s' "$3" >"$gate_state/told/$1/$2"
}

# Forgets that the owner was told of the event <event> of <name>, so that
# it is told again if it comes back.
gate_end() {
    rm -f "$gate_state/told/$1/$2"
}

# A desktop notification for the owner about <name>, unless CREW_NOTIFY=0.
# Without a notifier it says so once in the pane: the lines stay the way to
# know, and the next events try again without repeating the complaint.
gate_notify() {
    if [ "${CREW_NOTIFY:-1}" = 0 ]; then
        return 0
    fi
    crew_notify "crew: $1" "$2" && return 0
    if [ ! -e "$gate_state/no-notifier" ]; then
        : >"$gate_state/no-notifier"
        echo "$(crew_stamp) gate: cannot notify: no notifier here; the lines in this pane stay"
    fi
}

# <text> cut to what fits a notification: 80 characters at most.
gate_short() {
    if [ "${#1}" -gt 80 ]; then
        printf '%s...' "$(printf '%s' "$1" | cut -c1-77)"
    else
        printf '%s' "$1"
    fi
}

# What a look cannot see in <name>'s pane <pane>, told to the owner once
# while it lasts:
#
#   exited  the pane's tty is back to a shell where an agent ran at an
#           earlier look
#   gone    the terminal no longer lists the pane
#   idle    a member idle at its prompt with nothing to do (lib/idle.sh)
#           for gate_idle_minutes, told once a stretch (see gate_idle)
#
# The screen is the one gate_look read; the tty is asked for once, and the
# terminal's list a second time only when the tty is not found.
gate_tend() {
    t_name=$1
    t_pane=$2
    if t_tty=$(term_tty "$t_pane" 2>/dev/null); then
        gate_end gone "$t_name"
        if term_running "$t_tty"; then
            : >"$gate_state/up/$t_name"
            gate_end exited "$t_name"
        elif [ -e "$gate_state/up/$t_name" ] && gate_new exited "$t_name" 1; then
            echo "$(crew_stamp) exited $t_name: its agent is gone, its pane is back to a shell"
            gate_notify "$t_name" "Its agent exited, the pane is back to a shell. Look: crew focus $t_name. Bring it back: crew spawn $t_name ... or crew up"
        fi
    elif term_gone "$t_pane"; then
        rm -f "$gate_state/up/$t_name"
        if gate_new gone "$t_name" 1; then
            echo "$(crew_stamp) gone $t_name: its pane $t_pane is gone"
            gate_notify "$t_name" "Its pane is gone. Forget it: crew leave $t_name. Bring it back: crew spawn $t_name ... or crew up"
        fi
    fi
    gate_idle "$t_name" "$t_pane"
}

# The idle check of gate_tend: <name>, idle at its prompt in <pane> with
# nothing to do (idle_free: not muted, nothing unread, its last message an
# Idle: or none) for gate_idle_minutes, is told once a stretch: a line in
# the watch's pane, and a Heads-up: in the stream to the member --to names,
# else a notification to the owner. The stream is read first, which costs
# no look at the pane; then the screen, read with its styles for
# screen_of. Its checksum and the time it first came are kept in
# seen/<name>, so a screen that changed, or a member with something to do,
# starts the stretch over.
gate_idle() {
    i_min=$(gate_idle_minutes)
    if [ -z "$i_min" ] || [ -z "$screen_read" ]; then
        return 0
    fi
    i_file=$gate_state/seen/$1
    if ! idle_free "$dir" "$1" idle; then
        rm -f "$i_file"
        gate_end idle "$1"
        return 0
    fi
    i_screen=$(term_read_styled "$2" 2>/dev/null) || return 0
    i_sum=$(printf '%s' "$i_screen" | cksum | cut -d ' ' -f1)
    if [ "$i_sum" != "$(cut -d ' ' -f1 "$i_file" 2>/dev/null)" ]; then
        echo "$i_sum $gate_clock" >"$i_file"
        gate_end idle "$1"
        return 0
    fi
    i_since=$(cut -d ' ' -f2 "$i_file")
    [ $((gate_clock - i_since)) -ge $((i_min * 60)) ] || return 0
    [ "$(printf '%s\n' "$i_screen" | screen_of "$(kind_member "$dir" "$1")")" = idle ] || return 0
    gate_new idle "$1" "$i_since" || return 0
    i_last=$(idle_stream "$dir" "$1" | cut -d ' ' -f2)
    if [ "$i_last" = 0 ]; then
        i_why="it has sent no message"
    else
        i_why="its last message, $(printf '%04d' "$i_last"), is an Idle:"
    fi
    echo "$(crew_stamp) idle $1: nothing to do for $i_min minutes: idle at its prompt, nothing unread, and $i_why"
    if [ -z "${gate_to:-}" ]; then
        gate_notify "$1" "Nothing to do for $i_min minutes: idle at its prompt, nothing unread, and $i_why. Give it a task, or say why it waits."
    elif [ -n "$gate_dry" ]; then
        echo "$(crew_stamp) dry: would send $gate_to a Heads-up: about $1"
    # In a subshell of its own, with this crew named: crew_send sets
    # variables of the gate's own names (dir, to).
    elif ! (echo "$1 sits idle at its prompt with nothing unread, and $i_why. Give it a task, or tell it why to wait." |
        CREW_DIR=$dir crew_send watch "$gate_to" "Heads-up: $1 has had nothing to do for $i_min minutes" >/dev/null 2>&1); then
        echo "$(crew_stamp) idle $1: could not send $gate_to the Heads-up:"
    fi
}
