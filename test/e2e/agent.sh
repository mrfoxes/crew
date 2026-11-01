# A fake agent for test/e2e_tmux.sh, sourced by a script named claude whose
# interpreter is a link to sh named claude too, so that ps shows an agent
# in the pane. It draws the captured idle screen, records every line it is
# sent in $E2E_LOG/$E2E_NAME.in, and does what a real agent does with a
# line crew types: runs the command after "Run: " when it is crew's.
#
#   the line "!ask <fixture>"   draws that captured prompt and records the
#                               next line (an empty one is the key Enter)
#                               as its answer
#   the line "!exit"            leaves

stty -echo 2>/dev/null
log=$E2E_LOG/$E2E_NAME

draw() {
    printf '\033[2J\033[H'
    cat "$1"
}

draw "$E2E_FIXTURES/claude-idle.txt"
while IFS= read -r line; do
    printf '%s\n' "$line" >>"$log.in"
    case "$line" in
    '!ask '*)
        draw "${line#!ask }"
        IFS= read -r answer
        printf 'answer: [%s]\n' "$answer" >>"$log.in"
        draw "$E2E_FIXTURES/claude-idle.txt"
        ;;
    '!exit') exit 0 ;;
    *'Run: crew '*)
        cmd=${line#*Run: }
        cmd=${cmd%%. Then*}
        case "$cmd" in
        'crew join '* | 'crew unread '*) sh -c "$cmd" >>"$log.out" 2>&1 ;;
        esac
        ;;
    esac
done
