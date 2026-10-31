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
            # git -C <dir> and -c <key=value> do not hide the subcommand.
            while (gsub(/git +-[Cc] +('"'"'[^'"'"']*'"'"'|"[^"]*"|[^ ]+)/, "git", command)) ;
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
# answered twice.
gate_look() {
    name=$1
    pane=$2
    held=$gate_state/held/$name
    answered=$gate_state/answered/$name
    screen=$(term_read "$pane" 2>/dev/null) || {
        gate_say "$held" "gate: cannot read $name's pane $pane"
        return
    }
    prompt=$(printf '%s\n' "$screen" | gate_prompt)
    if [ -z "$prompt" ]; then
        rm -f "$held" "$answered"
        return
    fi
    [ "$screen" != "$(cat "$answered" 2>/dev/null)" ] || return 0
    kind=$(printf '%s' "$prompt" | cut -f1)
    command=$(printf '%s' "$prompt" | cut -f2)
    tight=$(printf '%s' "$prompt" | cut -f3)
    case "$kind" in
    other) why="not a command" ;;
    *) why=$(gate_forbidden "$gate_rules" "$command") || why=$(gate_forbidden "$gate_rules" "$tight") || why="" ;;
    esac
    if [ -n "$why" ]; then
        gate_say "$held" "HOLD $name ($why): $command"
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
    case "$kind" in
    codex) key=y ;;
    claude) key=enter ;;
    esac
    # A press that fails (the terminal busy, the pane just closed) is said
    # once and tried again at the next look: the gate itself goes on.
    term_key "$pane" "$key" 2>/dev/null || {
        gate_say "$held" "gate: cannot press $key in $name's pane $pane"
        return 0
    }
    echo "$(crew_stamp) approved $name: $command"
    printf '%s' "$screen" >"$answered"
    rm -f "$held"
}

# Prints <line>, with the time, unless it is the one already in <file>, and
# keeps it there.
gate_say() {
    [ "$2" != "$(cat "$1" 2>/dev/null)" ] || return 0
    echo "$(crew_stamp) $2"
    printf '%s' "$2" >"$1"
}

# Watches the panes of <name>... every two seconds and prints one line a
# prompt:
#
#   21:45:03 approved codex: cargo test --test editors
#   21:47:10 HOLD codex (git +reset): git reset --hard
#
# With --dry it answers nothing and says what it would do.
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

# Reads the gate's arguments into $names and $gate_dry, finds the rules and
# the panes, and makes the state directory $gate_state under the crew's tmp.
gate_setup() {
    gate_dry=""
    names=""
    for arg in "$@"; do
        case "$arg" in
        --dry) gate_dry=--dry ;;
        *) names="$names $arg" ;;
        esac
    done
    if [ -z "$names" ]; then
        echo "usage: crew gate <name>... [--dry], or crew watch the same" >&2
        return 2
    fi
    dir=$(crew_dir) || return 1
    gate_rules=$dir/forbid
    [ -f "$gate_rules" ] || gate_rules=$CREW_HOME/share/forbid
    gate_state=$(mktemp -d "$dir/tmp/gate.XXXXXX") || return 1
    mkdir -p "$gate_state/held" "$gate_state/answered" "$gate_state/pane"
    for name in $names; do
        crew_pane "$name" >"$gate_state/pane/$name" || return 1
    done
}

# One look at every pane the gate watches.
gate_round() {
    for name in $names; do
        gate_look "$name" "$(cat "$gate_state/pane/$name")"
    done
}
