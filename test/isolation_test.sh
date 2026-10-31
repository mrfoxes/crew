#!/bin/sh
# Child CLI processes must reach the harness's refusing terminal commands,
# never the owner's terminals. Shell-function fakes remain available to tests.
#
#   sh test/run.sh isolation

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

check "osascript is isolated" "$tmp/bin/osascript" "$(command -v osascript)"
check "tmux is isolated" "$tmp/bin/tmux" "$(command -v tmux)"

# These functions work in this test, but are not inherited by bin/crew.
osascript() { echo fake-osascript; }
tmux() { echo fake-tmux; }
check "a test can fake osascript" "fake-osascript" "$(osascript)"
check "a test can fake tmux" "fake-tmux" "$(tmux)"

check "a child CLI cannot type into iTerm2" "1" "$(sh "$CREW_HOME/bin/crew" poke iterm:fixture hello >/dev/null 2>&1; echo $?)"
check "the child records its iTerm2 attempt" "1" "$(grep -c '^osascript ' "$CREW_TEST_TERMINAL_LOG")"
check "a child CLI cannot type into tmux" "1" "$(sh "$CREW_HOME/bin/crew" poke tmux:%999 hello >/dev/null 2>&1; echo $?)"
check "the child records its tmux attempt" "tmux send-keys -t %999 -l -- hello" "$(grep '^tmux ' "$CREW_TEST_TERMINAL_LOG")"

finish
