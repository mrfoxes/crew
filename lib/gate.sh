# The gate: answers an agent's approval prompts for the owner, and holds the
# commands the rules forbid for the coordinator to decide. Sourced by bin/crew.

# Reads a screen on stdin and prints the approval prompt waiting at its
# bottom as "<kind><tab><command><tab><command unwrapped>", or nothing:
#
#   codex   "Would you like to run the following command?", "$ <command>",
#           "1. Yes, proceed", answered with y
#   claude  "Bash command", <command>, "Do you want to proceed?", the cursor
#           on "1. Yes", answered with Return
#   other   any other question near the bottom (Allow ...?, Run this
#           command?, Do you want ...?): never answered, always held
#
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
            # Claude Code: "Do you want to proceed?" with its options below.
            for (q = n; q > 0 && q > n - 10 && line[q] !~ /^Do you want to proceed\?$/; q--) ;
            if (q > 0 && q > n - 10 && line[q + 1] ~ /^❯ *1\. Yes$/) {
                for (h = q; h > 0 && line[h] !~ /^Bash command/; h--) ;
                if (h > 0 && h + 1 < q) { out("claude", h + 1, q - 1); exit }
            }
            # Any other question waiting near the bottom.
            for (q = n; q > 0 && q > n - 12; q--)
                if (line[q] ~ /\?$/ && line[q] ~ /(Allow|Approve|Do you want|Would you like|Run this command|Proceed)/) {
                    e = q + 3 > n ? n : q + 3
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

# Watches <name>'s pane every two seconds and prints one line a prompt:
#
#   approved codex: cargo test --test editors
#   HOLD codex (git +reset): git reset --hard
#
# With --dry it answers nothing and says what it would do.
crew_gate() {
    if [ $# -lt 1 ]; then
        echo "usage: crew gate <name> [--dry]" >&2
        return 2
    fi
    name=$1
    dry=${2:-}
    pane=$(crew_pane "$name") || return 1
    dir=$(crew_dir) || return 1
    rules=$dir/forbid
    [ -f "$rules" ] || rules=$CREW_HOME/share/forbid
    seen=""
    while :; do
        screen=$(term_read "$pane" 2>/dev/null) || {
            echo "gate: cannot read $name's pane $pane"
            sleep 30
            continue
        }
        prompt=$(printf '%s\n' "$screen" | gate_prompt)
        if [ -z "$prompt" ]; then
            seen=""
            sleep 2
            continue
        fi
        kind=$(printf '%s' "$prompt" | cut -f1)
        command=$(printf '%s' "$prompt" | cut -f2)
        tight=$(printf '%s' "$prompt" | cut -f3)
        case "$kind" in
        other) why="not a command" ;;
        *) why=$(gate_forbidden "$rules" "$command") || why=$(gate_forbidden "$rules" "$tight") || why="" ;;
        esac
        if [ -n "$why" ] || [ "$dry" = --dry ]; then
            if [ "$prompt" != "$seen" ]; then
                if [ -n "$why" ]; then
                    echo "HOLD $name ($why): $command"
                else
                    echo "would approve $name: $command"
                fi
                seen=$prompt
            fi
            sleep 2
            continue
        fi
        case "$kind" in
        codex) term_key "$pane" y ;;
        claude) term_key "$pane" enter ;;
        esac
        echo "approved $name: $command"
        seen=""
        sleep 3
    done
}
