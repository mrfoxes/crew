#!/bin/sh
# The gate's notifications: what it tells the owner, once while it lasts and
# again when it comes back. crew_notify and the terminal are faked: the
# notifications are written to a file, and the terminal is two files, one for
# a pane listed and one for an agent running in it.
#
#   sh test/run.sh notify

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

notes=$tmp/notes
crew_notify() {
    [ ! -e "$tmp/no-notifier" ] || return 1
    printf '%s | %s\n' "$1" "$2" >>"$notes"
}
term_read() { fixture_read; }
term_key() { echo "pressed $2"; }
term_tty() { [ -e "$tmp/listed" ] && echo /dev/ttys001; }
term_running() { [ -e "$tmp/running" ]; }
term_gone() { [ ! -e "$tmp/listed" ]; }
gate_now() { cat "$tmp/now"; }

# Whether the agent runs, whether the pane is listed, and the time.
agent() { if [ "$1" = up ]; then : >"$tmp/running"; else rm -f "$tmp/running"; fi; }
pane() { if [ "$1" = listed ]; then : >"$tmp/listed"; else rm -f "$tmp/listed"; fi; }
clock() { echo "$1" >"$tmp/now"; }

# A gate over codex that has told the owner of nothing, its agent up in a
# pane that is listed.
dir=$tmp/crew
gate_rules=$CREW_HOME/share/forbid
gate_dry=""
names=codex
fresh() {
    rm -rf "$tmp/state" "$dir" "$tmp/no-notifier"
    mkdir -p "$dir/seq" "$dir/kind"
    echo codex >"$dir/kind/codex"
    gate_state=$tmp/state
    gate_dirs "$gate_state"
    echo tmux:%1 >"$gate_state/pane/codex"
    : >"$notes"
    pane listed
    agent up
    clock 1000
}
# One round of the gate: its lines, then the notifications it sent.
round() {
    gate_round
    cat "$notes"
    : >"$notes"
}
CREW_NOTIFY=1
fresh

# A held prompt is told once, not again while it is drawn, and again after it
# went and came back. The command is cut to 80 characters.
show codex-wrapped
want="12:00:00 HOLD codex (git +(stash|restore|clean|rebase|pull|merge|checkout|switch|cherry-pick|am)( |\$)): cd /Users/mrfoxes/Documents/repos/github.com/mrfoxes/tess && git sta sh push -m wip
crew: codex | HOLD: cd /Users/mrfoxes/Documents/repos/github.com/mrfoxes/tess && git sta sh push .... Look: crew focus codex. Answer: crew key codex <key>..."
check "a held prompt is told" "$want" "$(round)"
check "a held prompt is told once" "" "$(round)"
show codex-idle
check "no prompt, nothing to tell" "" "$(round)"
show codex-wrapped
check "a held prompt is told again after it went" "$want" "$(round)"
show claude-fetch
check "another held prompt in its place is told" "1" "$(round | grep -c '^crew: codex | HOLD: Do you want to allow Claude to fetch')"

# CREW_NOTIFY=0 prints the line and notifies nothing.
fresh
show claude-fetch
check "a held prompt is printed with CREW_NOTIFY=0" "1" "$(CREW_NOTIFY=0 round | grep -c '^12:00:00 HOLD codex')"
check "a held prompt is not notified with CREW_NOTIFY=0" "" "$(cat "$notes")"
fresh
show codex-idle
round >/dev/null
agent down
check "an exit is printed with CREW_NOTIFY=0" "1" "$(CREW_NOTIFY=0 round | grep -c '^12:00:00 exited codex')"
check "an exit is not notified with CREW_NOTIFY=0" "" "$(cat "$notes")"

# An agent that exited: its pane is back to a shell where it ran before.
fresh
show codex-idle
check "an agent running is nothing to tell" "" "$(round)"
agent down
want="12:00:00 exited codex: its agent is gone, its pane is back to a shell
crew: codex | Its agent exited, the pane is back to a shell. Look: crew focus codex. Bring it back: crew spawn codex ... or crew up"
check "an exit is told" "$want" "$(round)"
check "an exit is told once" "" "$(round)"
agent up
check "the agent back is nothing to tell" "" "$(round)"
agent down
check "an exit is told again after the agent came back" "$want" "$(round)"
fresh
agent down
check "a shell where no agent ran is nothing to tell" "" "$(round)"

# A pane that is gone.
fresh
show codex-idle
round >/dev/null
pane gone
want="12:00:00 cannot read codex's pane tmux:%1
12:00:00 gone codex: its pane tmux:%1 is gone
crew: codex | Its pane is gone. Forget it: crew leave codex. Bring it back: crew spawn codex ... or crew up"
check "a pane gone is told" "$(printf '%s\n' "$want" | sed 1d)" "$(round | grep -v ' cannot read ')"
check "a pane gone is told once" "" "$(round | grep -v ' cannot read ')"
pane listed
check "the pane back is nothing to tell" "" "$(round)"
pane gone
check "a pane gone is told again after it came back" "2" "$(round | grep -c -e ' gone codex' -e 'Its pane is gone')"
fresh
agent down
pane gone
check "a gone pane is not an agent that exited" "0" "$(round | grep -c exited)"

# A notifier that fails is said once, and the lines stay.
fresh
: >"$tmp/no-notifier"
show codex-wrapped
want="gate: cannot notify: no notifier here; the lines in this pane stay"
out=$(round)
check "a failed notification is said" "1" "$(printf '%s\n' "$out" | grep -c "^12:00:00 $want")"
check "a failed notification keeps the held line" "1" "$(printf '%s\n' "$out" | grep -c '^12:00:00 HOLD codex')"
agent down
check "a failed notification is said once" "0" "$(round | grep -c 'cannot notify')"
check "the next event is still printed" "" "$(round)"

# A member idle for CREW_IDLE_MINUTES: off unless asked for.
fresh
show codex-idle
clock 1000
round >/dev/null
clock 100000
check "idle is off by default" "" "$(round)"
CREW_IDLE_MINUTES=0
check "idle is off for 0" "" "$(round)"
CREW_IDLE_MINUTES=soon
check "idle is off for a word" "" "$(round)"

fresh
CREW_IDLE_MINUTES=10
show codex-idle
clock 1000
check "idle starts counting at the first look" "" "$(round)"
clock 1599
check "not idle for long enough" "" "$(round)"
clock 1600
want="12:00:00 idle codex: waiting for input for 10 minutes, and no Done: sent
crew: codex | Idle for 10 minutes, waiting for input, no Done: sent. Look: crew focus codex"
check "idle is told" "$want" "$(round)"
clock 2000
check "idle is told once" "" "$(round)"
sed 's/^/ /' "$here/fixtures/codex-idle.txt" >"$tmp/changed.txt"
show "$tmp/changed.txt"
clock 2100
check "a screen that changed is not idle" "" "$(round)"
clock 2800
check "idle is told again after the screen changed" "$want" "$(round)"

# Not idle when the input line is not drawn, or the member sent Done:.
fresh
echo claude >"$dir/kind/codex"
show codex-idle
clock 1000
round >/dev/null
clock 5000
check "a screen without the kind's input line is not idle" "" "$(round)"
fresh
printf '# 0001. codex to claude: Done: the editors\n\nFrom: codex\nTo: claude\n' >"$dir/seq/1"
show codex-idle
clock 1000
round >/dev/null
clock 5000
check "a member that sent Done: is not idle" "" "$(round)"
fresh
printf '# 0001. claude to codex: Done: the editors\n\nFrom: claude\nTo: codex\n' >"$dir/seq/1"
show codex-idle
clock 1000
round >/dev/null
clock 5000
check "a Done: from someone else does not count" "1" "$(round | grep -c '^12:00:00 idle codex')"

# --all watches every member with a pane, read again at each round.
gate_all=1
mkdir -p "$dir/panes" "$gate_state/pane"
rm -f "$dir"/panes/*
echo tmux:%31 >"$dir/panes/m1"
gate_members
check "all: the members with a pane" " m1" "$names"
check "all: their panes" "tmux:%31" "$(cat "$gate_state/pane/m1")"
echo tmux:%32 >"$dir/panes/m2"
gate_members
check "all: a member spawned later" " m1 m2" "$names"
gate_all=""

finish
