# What an agent's screen says, per kind: whether a prompt or dialog is open,
# a turn runs, text waits on the input line, a background shell runs, or
# the agent is idle at an empty prompt. The marks are those of the screens
# in test/fixtures/ (their versions in test/fixtures/VERSIONS), one case a
# kind: Claude Code, Codex, and Antigravity. crew clear and crew compact
# (lib/context.sh) and the board read them. Its variables start with sc_.
# Sourced by bin/crew.

# The wait between the two looks of screen_state, in seconds; a function so
# that a test can fake it and never sleep. Every kind's spinner or timer
# moves within it.
screen_pause() {
    sleep 2
}

# The text on <kind>'s input line in the screen on stdin, its mark and the
# kind's placeholder taken off: nothing for an empty line. Fails when no
# input line is drawn near the bottom (a dialog in its place). The input
# line is the lowest line, of the last 8, that is the mark alone or the mark
# and a space; Claude Code draws a no-break space after it, which counts as
# a space, and the screen is read as bytes, the same in every locale. On a
# screen read with its styles (term_read_styled), dim text is no text: it
# is a placeholder or a suggestion (Claude Code's "yes, proceed"), never
# what someone typed; plain text is matched against the kinds' placeholders.
screen_input() {
    sc_mark=$(kind_field "$1" idle)
    [ -n "$sc_mark" ] || return 1
    LC_ALL=C awk -v m="$sc_mark" -v k="$1" '
        function norm(s) {
            gsub(/\302\240/, " ", s)
            gsub(/│|┃|╭|╮|╰|╯/, "", s)
            sub(/^[ \t]+/, "", s)
            sub(/[ \t]+$/, "", s)
            return s
        }
        {
            p = $0
            gsub(/\033\[[0-9;:?]*[A-Za-z]/, "", p)
            t = $0
            gsub(/\033\[([0-9;]*;)?2(;[0-9;]*)?m[^\033]*/, "", t)
            gsub(/\033\[[0-9;:?]*[A-Za-z]/, "", t)
            p = norm(p)
            if (p != "") { line[++n] = p; text[n] = norm(t) }
        }
        END {
            for (i = n; i > 0 && i > n - 8; i--) {
                if (line[i] == m) exit 0
                if (index(line[i], m " ") == 1) {
                    t = (index(text[i], m " ") == 1) ? substr(text[i], length(m) + 2) : ""
                    sub(/^[ \t]+/, "", t)
                    if (k == "claude" && index(t, "Try \"") == 1) t = ""
                    if (k == "codex" && t == "Ask Codex to do anything") t = ""
                    print t
                    exit 0
                }
            }
            exit 1
        }'
}

# Whether the screen on stdin shows <kind> in a turn: Claude Code's spinner
# line ("✳ Sparkling… (4s · ↓ 216 tokens)", "Compacting conversation… (1s"),
# which no longer says esc interrupts it, or esc to interrupt (Claude Code
# before 2.1.318, Codex), or esc to cancel (Antigravity's footer).
screen_working() {
    LC_ALL=C awk -v k="$1" '
        k == "claude" && (index($0, "\342\200\246 (") || index($0, "esc to interrupt")) { found = 1 }
        k == "codex" && index($0, "esc to interrupt") { found = 1 }
        k == "agy" && index($0, "esc to cancel") { found = 1 }
        END { exit !found }'
}

# Whether the screen on stdin shows a background shell of <kind>'s: Claude
# Code's footer, under its input line, ends "· 1 shell" (it lasts through a
# clear and a compact); Codex says "1 background terminal running".
# Antigravity shows none.
screen_shell() {
    sc_mark=$(kind_field "$1" idle)
    LC_ALL=C awk -v m="$sc_mark" -v k="$1" '
        {
            l = $0
            gsub(/\302\240/, " ", l)
            gsub(/│|┃|╭|╮|╰|╯/, "", l)
            sub(/^[ \t]+/, "", l)
            sub(/[ \t]+$/, "", l)
            if (l == m || index(l, m " ") == 1) below = 1
            else if (k == "claude" && below && l ~ /(^|· )[0-9]+ shells?( ·|$)/) found = 1
            if (k == "codex" && l ~ /[0-9]+ background terminals? running/) found = 1
        }
        END { exit !found }'
}

# How many of <kind>'s marks of a finished compact the screen on stdin
# shows: Claude Code's "⎿  Compacted", Codex's "• Context compacted",
# Antigravity's "── Conversation compacted ──".
screen_compacted() {
    LC_ALL=C awk -v k="$1" '
        k == "claude" && index($0, "\342\216\277  Compacted") { n++ }
        k == "codex" && index($0, "\342\200\242 Context compacted") { n++ }
        k == "agy" && index($0, " Conversation compacted ") { n++ }
        END { print n + 0 }'
}

# The screen on stdin without its escape sequences.
screen_plain() {
    LC_ALL=C awk '{ gsub(/\033\[[0-9;:?]*[A-Za-z]/, ""); print }'
}

# What the screen on stdin of a <kind> agent says, in one word, from one
# look: dialog (a prompt the gate sees, or no input line drawn), working,
# typed (text waits on the input line), shell (idle, with a background
# shell), idle, or unknown for a kind with no input mark. The screen may
# carry its styles (term_read_styled): only the input line reads them.
screen_of() {
    if [ -z "$(kind_field "$1" idle)" ]; then
        echo unknown
        return
    fi
    sc_styled=$(cat)
    sc_screen=$(printf '%s\n' "$sc_styled" | screen_plain)
    if [ -n "$(printf '%s\n' "$sc_screen" | gate_prompt)" ] ||
        ! sc_text=$(printf '%s\n' "$sc_styled" | screen_input "$1"); then
        echo dialog
    elif printf '%s\n' "$sc_screen" | screen_working "$1"; then
        echo working
    elif [ -n "$sc_text" ]; then
        echo typed
    elif printf '%s\n' "$sc_screen" | screen_shell "$1"; then
        echo shell
    else
        echo idle
    fi
}

# What <name>'s pane in the crew <dir> shows, in one word: none (no pane),
# gone, exited (no agent of its kind in the foreground), unknown (a kind
# with no input mark), or what screen_of says; an idle or shell screen is
# looked at twice, screen_pause apart, and one that moved is working.
screen_state() {
    sc_pane=$(cat "$1/panes/$2" 2>/dev/null) || sc_pane=""
    if [ -z "$sc_pane" ]; then
        echo none
        return
    fi
    sc_kind=$(kind_member "$1" "$2")
    if [ -z "$(kind_field "$sc_kind" idle)" ]; then
        echo unknown
        return
    fi
    if ! term_tty "$sc_pane" >/dev/null 2>&1; then
        echo gone
        return
    fi
    if ! pane_agent "$1" "$2" "$sc_pane"; then
        echo exited
        return
    fi
    if ! sc_one=$(term_read_styled "$sc_pane" 2>/dev/null); then
        echo gone
        return
    fi
    sc_state=$(printf '%s\n' "$sc_one" | screen_of "$sc_kind")
    case "$sc_state" in
    idle | shell) ;;
    *)
        echo "$sc_state"
        return
        ;;
    esac
    screen_pause
    if ! sc_two=$(term_read_styled "$sc_pane" 2>/dev/null); then
        echo gone
    elif [ "$sc_one" != "$sc_two" ]; then
        echo working
    else
        echo "$sc_state"
    fi
}
