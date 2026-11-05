# A fake agent for test/e2e_tmux.sh, sourced by a script named claude whose
# interpreter is a link to sh named claude too, so that ps shows an agent
# in the pane. It draws the captured idle screen, records every line it is
# sent in $E2E_LOG/$E2E_NAME.in, and does what a real agent does with a
# line crew types: runs the command after "Run: " when it is crew's, and
# shows that line taken above its input line.
#
#   the line "!ask <fixture>"   draws that captured prompt and records the
#                               next line (an empty one is the key Enter)
#                               as its answer
#   the line "!draw <fixture>"  draws that captured screen
#   the line "/clear"           draws the captured cleared screen; while
#                               $E2E_LOG/$E2E_NAME.slow is there (at most
#                               30 seconds), it keeps the screen it had
#   the line "/compact ..."     draws the captured compacting screen, then
#                               after 3 seconds the compacted one
#   the line "/exit", "/quit",
#   or "!exit"                  leaves; while $E2E_LOG/$E2E_NAME.slow is
#                               there (at most 30 seconds), it stays
#
# Its arguments go to $E2E_LOG/$E2E_NAME.args, a line a start. Like Claude
# Code, it has a session, which crew join records: the one after --resume,
# or one of its own.

stty -echo 2>/dev/null
log=$E2E_LOG/$E2E_NAME
printf 'args: [%s]\n' "$*" >>"$log.args"
if [ $# -ge 2 ] && [ "$1" = --resume ]; then
    CLAUDE_CODE_SESSION_ID=$2
else
    CLAUDE_CODE_SESSION_ID=e2e-$E2E_NAME-$$
fi
export CLAUDE_CODE_SESSION_ID

# Waits while $log.slow is there, at most 30 seconds.
slow() {
    slow_left=30
    while [ -e "$log.slow" ] && [ "$slow_left" -gt 0 ]; do
        slow_left=$((slow_left - 1))
        sleep 1
    done
}

draw() {
    printf '\033[2J\033[H'
    cat "$1"
}

# Draws <fixture> with the line <text> taken: in the transcript, as the
# agent's mark and the text, just above the rule over its input line.
draw_taken() {
    printf '\033[2J\033[H'
    awk -v t="$2" '
        { l[NR] = $0 }
        index($0, "❯") == 1 { input = NR }
        END {
            for (i = 1; i <= NR; i++) {
                if (i == input - 1) print "❯ " t
                print l[i]
            }
        }' "$1"
}

screen=$E2E_FIXTURES/claude-idle.txt
draw "$screen"
while IFS= read -r line; do
    printf '%s\n' "$line" >>"$log.in"
    case "$line" in
    '!ask '*)
        draw "${line#!ask }"
        IFS= read -r answer
        printf 'answer: [%s]\n' "$answer" >>"$log.in"
        draw "$screen"
        ;;
    '!draw '*)
        screen=${line#!draw }
        draw "$screen"
        ;;
    /clear)
        slow
        screen=$E2E_FIXTURES/claude-cleared.txt
        draw "$screen"
        ;;
    /compact*)
        draw "$E2E_FIXTURES/claude-compacting.txt"
        sleep 3
        screen=$E2E_FIXTURES/claude-compacted.txt
        draw "$screen"
        ;;
    /exit | /quit | '!exit')
        slow
        exit 0
        ;;
    *'Run: crew '*)
        draw_taken "$screen" "$line"
        cmd=${line#*Run: }
        cmd=${cmd%%. Then*}
        cmd=${cmd%%,*}
        case "$cmd" in
        'crew join '* | 'crew unread '*) sh -c "$cmd" >>"$log.out" 2>&1 ;;
        esac
        ;;
    esac
done
