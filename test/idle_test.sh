#!/bin/sh
# Idle members: what a pane shows from looks that never wait, one pause for
# a whole board, what the stream says of a member, who has nothing to do,
# and how the board says it. The terminal is faked: each pane's screen is a
# file, and the pause copies each pane's next screen in.
#
#   sh test/run.sh idle

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

fixtures=$here/fixtures
git init -q "$tmp/repo"
git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "Start the project"
cd "$tmp/repo" || exit 1
dir=$(crew_init)

term_tty() { [ "$1" != tmux:%gone ] && echo "/dev/tty${1#tmux:%}"; }
term_running() { [ ! -e "$tmp/exited" ]; }
term_read_styled() { cat "$tmp/screen.${1#tmux:%}"; }
pauses=$tmp/pauses
: >"$pauses"
screen_pause() {
    echo pause >>"$pauses"
    for p_next in "$tmp"/next.*; do
        [ -f "$p_next" ] || continue
        mv "$p_next" "$tmp/screen.${p_next##*.}"
    done
}
# pane <name> <pane number> <kind> <fixture> [<the fixture after a pause>]
pane() {
    echo "tmux:%$2" >"$dir/panes/$1"
    kind_record "$dir" "$1" "$3"
    cp "$fixtures/$4.txt" "$tmp/screen.$2"
    rm -f "$tmp/next.$2"
    [ -z "${5:-}" ] || cp "$fixtures/$5.txt" "$tmp/next.$2"
}
# say <from> <to> <subject>: a message in the stream.
say() { echo body | crew_send "$1" "$2" "$3" >/dev/null 2>&1; }

# One look, its checksum kept in a file of the caller's.
check "no pane" "none" "$(idle_look "$dir" ann "$tmp/sum.ann")"
pane ann 1 claude claude-idle
check "an idle screen, at a first look" "idle" "$(idle_look "$dir" ann "$tmp/sum.ann")"
check "the same screen again" "idle" "$(idle_look "$dir" ann "$tmp/sum.ann")"
cp "$fixtures/claude-after-turn.txt" "$tmp/screen.1"
check "an idle screen that changed since the last look" "working" "$(idle_look "$dir" ann "$tmp/sum.ann")"
cp "$fixtures/claude-working.txt" "$tmp/screen.1"
check "a turn" "working" "$(idle_look "$dir" ann "$tmp/sum.ann")"
cp "$fixtures/claude-typed.txt" "$tmp/screen.1"
check "text typed" "typed" "$(idle_look "$dir" ann "$tmp/sum.ann")"
cp "$fixtures/claude-shell.txt" "$tmp/screen.1"
rm -f "$tmp/sum.ann"
check "a background shell" "shell" "$(idle_look "$dir" ann "$tmp/sum.ann")"
cp "$fixtures/claude-run.txt" "$tmp/screen.1"
check "a dialog" "dialog" "$(idle_look "$dir" ann "$tmp/sum.ann")"
: >"$tmp/exited"
check "no agent in the foreground" "exited" "$(idle_look "$dir" ann "$tmp/sum.ann")"
rm "$tmp/exited"
echo tmux:%gone >"$dir/panes/ann"
check "a pane gone" "gone" "$(idle_look "$dir" ann "$tmp/sum.ann")"
pane ann 1 other claude-idle
check "a kind with no input mark" "unknown" "$(idle_look "$dir" ann "$tmp/sum.ann")"

# A board's looks: one pause for all the members it found idle, none when
# it found none, and a screen that moved across the pause is working.
pane ann 1 claude claude-idle
pane bob 2 codex codex-idle codex-working
pane cat 3 claude claude-idle claude-after-turn
check "the states of a board" "ann idle
bob working
cat working
dan none" "$(idle_states "$dir" ann bob cat dan)"
check "one pause for all of them" "1" "$(wc -l <"$pauses" | tr -d ' ')"
: >"$pauses"
pane ann 1 claude claude-working
pane bob 2 codex codex-typed
check "no member idle, no pause" "ann working
bob typed" "$(idle_states "$dir" ann bob)"
check "and no wait" "0" "$(wc -l <"$pauses" | tr -d ' ')"
check "nothing left in tmp" "" "$(find "$dir/tmp" -name "idle.*")"

# What the stream says: unread, the last message sent, its subject's word.
check "nothing in the stream" "0 0 -" "$(idle_stream "$dir" ann)"
say bob ann "Question: the parser"
say bob all "Heads-up: main moved"
say ann bob "Answer: yes"
say ann owner "Idle: the lane is done"
check "two unread, an Idle: last" "2 4 Idle:" "$(idle_stream "$dir" ann)"
check "a message to all is not unread for its sender" "1 0 -" "$(idle_stream "$dir" cat)"
crew_unread ann >/dev/null
check "read" "0 4 Idle:" "$(idle_stream "$dir" ann)"
say bob ann "Review: two findings"
check "a new one" "1 4 Idle:" "$(idle_stream "$dir" ann)"

# Nothing to do: idle at an empty prompt, not muted, nothing unread, and the
# last message an Idle:, or none at all.
check "unread: not free" "1" "$(idle_free "$dir" ann idle; echo $?)"
crew_unread ann >/dev/null
check "idle, nothing unread, an Idle: last: free" "0" "$(idle_free "$dir" ann idle; echo $?)"
check "typed is not free" "1" "$(idle_free "$dir" ann typed; echo $?)"
check "a background shell is not free" "1" "$(idle_free "$dir" ann shell; echo $?)"
check "working is not free" "1" "$(idle_free "$dir" ann working; echo $?)"
crew_unread dan >/dev/null
check "a member that sent nothing: free" "0" "$(idle_free "$dir" dan idle; echo $?)"
say ann bob "Review: clean"
check "a message after the Idle: is work done since" "1" "$(idle_free "$dir" ann idle; echo $?)"
say ann owner "Done: the lane"
check "a member that sent Done: has ended, not free" "1" "$(idle_free "$dir" ann idle; echo $?)"
crew_mute dan >/dev/null
check "a muted member is idle by design, not free" "1" "$(idle_free "$dir" dan idle; echo $?)"

# How the board says it.
check "muted and idle" "idle (muted)" "$(idle_said "$dir" dan idle)"
check "muted and working" "working" "$(idle_said "$dir" dan working)"
say eve coord "Idle: nothing left"
crew_unread eve >/dev/null
check "free since its Idle:" "idle, nothing to do for 0 min" "$(idle_said "$dir" eve idle)"
printf 'Agent: fay\n' >"$dir/status/fay.md"
crew_unread fay >/dev/null
crew_unread gil >/dev/null
check "free since its status, with no message sent" "idle, nothing to do for 0 min" "$(idle_said "$dir" fay idle)"
check "free with neither" "idle, nothing to do" "$(idle_said "$dir" gil idle)"
check "a member with something to do" "idle" "$(idle_said "$dir" ann idle)"

# The board: each member's state after its pane.
rm -f "$dir"/muted/*
for m in ann eve; do
    printf 'Agent: %s\nFiles: none\n' "$m" >"$dir/status/$m.md"
done
pane ann 1 claude claude-working
pane eve 5 claude claude-idle
term_gone() { return 1; }
gh() { return 1; }
board=$(crew_board 1)
check "the board says a member works" "1" "$(printf '%s\n' "$board" | grep -c '^== ann (claude, tmux:%1, working, ')"
check "and that one has nothing to do" "1" "$(printf '%s\n' "$board" | grep -c '^== eve (claude, tmux:%5, idle, nothing to do for 0 min, ')"
check "a member with no pane says no state" "1" "$(printf '%s\n' "$board" | grep -c '^== fay (no pane, ')"
crew_mute eve >/dev/null
check "a muted member at its prompt" "1" "$(crew_board 1 | grep -c '^== eve (claude, tmux:%5, idle (muted), [0-9]')"

finish
