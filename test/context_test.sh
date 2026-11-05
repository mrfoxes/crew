#!/bin/sh
# The context tests: crew clear and crew compact over a faked terminal whose
# screens are the captured ones of test/fixtures/, shown one after another
# as the agent would draw them: the refusals (no pane, its own pane, not
# idle, a background shell, a claimed file changed after the status), what
# is typed for each kind, the waits and their ends, the wakes held while
# they run and the one sent after. No pane is read or typed into.
#
#   sh test/run.sh context

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

fixtures=$CREW_HOME/test/fixtures
git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
echo one >a.txt
git add a.txt
git -c user.name=t -c user.email=t@t commit -q -m "Start the project"
dir=$(crew_init)

# The terminal: the screen is a file; each pause shows the next screen of
# the queue; the n-th line typed queues the screens of after<n>.
self_pane=tmux:%0
term_self() { echo "$self_pane"; }
term_tty() { echo /dev/ttys001; }
term_running() { :; }
term_read() { cat "$tmp/screen"; }
term_read_styled() { cat "$tmp/screen"; }
term_poke() {
    printf '%s\n' "$2" >>"$tmp/typed"
    pokes=$(wc -l <"$tmp/typed" | tr -d ' ')
    [ ! -f "$tmp/after$pokes" ] || cp "$tmp/after$pokes" "$tmp/queue"
}
screen_pause() {
    [ -s "$tmp/queue" ] || return 0
    show "$(head -n 1 "$tmp/queue")"
    tail -n +2 "$tmp/queue" >"$tmp/queue.next"
    mv "$tmp/queue.next" "$tmp/queue"
}
# show <screen>: a fixture by name, or a file of this test by path.
show() {
    case "$1" in
    /*) cp "$1" "$tmp/screen" ;;
    *) cp "$fixtures/$1.txt" "$tmp/screen" ;;
    esac
}
# start <screen> [after1] [after2]: the screen now, and the screens the
# first and second lines typed bring, a word each.
start() {
    show "$1"
    rm -f "$tmp/typed" "$tmp/queue" "$tmp/after1" "$tmp/after2"
    [ -z "${2:-}" ] || printf '%s\n' $2 >"$tmp/after1"
    [ -z "${3:-}" ] || printf '%s\n' $3 >"$tmp/after2"
}
typed() { cat "$tmp/typed" 2>/dev/null; }
run() {
    "$@" >"$tmp/out" 2>"$tmp/err"
    echo $?
}
err() { cat "$tmp/err"; }
member() {
    echo "$2" >"$dir/panes/$1"
    kind_record "$dir" "$1" "$3"
}
status() { printf 'Agent: %s\nFiles: %s\nNext: more\n' "$1" "$2" | crew_write status "$1" >/dev/null 2>&1; }
held() { if [ -e "$dir/tmp/hold/ann" ]; then echo held; else echo free; fi; }
# The wakes kept for later.
wakes() {
    for w in "$dir"/tmp/wake.*; do
        [ ! -e "$w" ] || basename "$w"
    done
}

# The screen of a Claude Code member that took the line to rejoin: the
# cleared screen with the line above its input line, its turn begun.
line=$(context_line ann)
awk -v l="$line" '/^❯/ && !done { print "❯ " l; print "✳ Thinking… (1s · ↓ 12 tokens)"; done = 1 } { print }' \
    "$fixtures/claude-cleared.txt" | sed 's/ · 1 shell$//' >"$tmp/joined"
# And one whose line still waits on the input line, unsent.
sed "s/^❯ \$/❯ $line/; s/ · 1 shell\$//" "$fixtures/claude-cleared.txt" >"$tmp/unsent"
# The cleared screen with no background shell.
sed 's/ · 1 shell$//' "$fixtures/claude-cleared.txt" >"$tmp/cleared"

check "the line to rejoin" "crew: your context was cleared. Run: crew join ann, then crew status ann, and resume from its Next: line. Work in caveman mode (\$caveman) from now on." "$line"

# Arguments and members.
check "clear with no name" "2" "$(run crew_clear)"
check "clear with two names" "2" "$(run crew_clear ann bob)"
check "compact with no name" "2" "$(run crew_compact)"
check "a bad name" "2" "$(run crew_clear ANN)"
check "no pane" "1" "$(run crew_clear ann)"
check "it says so" "crew: ann has no pane" "$(err)"
mkdir -p "$dir/nopane"
: >"$dir/nopane/coord"
check "a member with --no-pane" "1" "$(run crew_clear coord)"
check "it says crew types nothing there" "1" "$(grep -c 'reads the stream on its own (--no-pane)' "$tmp/err")"
member ann tmux:%1 other
start claude-idle
check "a kind crew knows no command of" "1" "$(run crew_clear ann)"
check "it names the kinds" "1" "$(grep -c 'knows Claude Code, Codex, and Antigravity; ann is other' "$tmp/err")"
member ann tmux:%1 claude
self_pane=tmux:%1
check "its own pane" "1" "$(run crew_compact ann)"
check "it says crew cannot act on its own pane" "1" "$(grep -c "the one this runs in" "$tmp/err")"
self_pane=tmux:%0

# Not idle at an empty prompt: nothing is typed.
for screen in claude-working claude-typed claude-run claude-shell; do
    start "$screen"
    run crew_clear ann >/dev/null
    check "$screen: nothing is typed" "" "$(typed)"
done
start claude-working
check "a working member is refused" "1" "$(run crew_clear ann)"
check "it says why" "crew: ann is not idle at an empty prompt: it is working, so nothing was typed" "$(err)"
start claude-typed
run crew_clear ann >/dev/null
check "text on the input line is left alone" "crew: ann is not idle at an empty prompt: text waits on its input line, and crew types nothing over it, so nothing was typed" "$(err)"
start claude-run
run crew_compact ann >/dev/null
check "a prompt open" "crew: ann is not idle at an empty prompt: a prompt or a dialog is open in its pane, so nothing was typed" "$(err)"
start claude-shell
check "a clear with a background shell is refused" "1" "$(run crew_clear ann)"
check "it says a clear would lose who started it" "1" "$(grep -c 'a background shell runs in ann.s pane' "$tmp/err")"

# A claimed file changed after the status: the clear is refused, with both
# ages; once the status is newer, it goes on.
status ann "a.txt"
echo two >a.txt
touch -t 202001010000 "$dir/status/ann.md"
start claude-idle
check "a claimed file newer than the status stops the clear" "1" "$(run crew_clear ann)"
check "it names the file" "1" "$(grep -c "^crew: ann's a.txt changed after its status was written (the file 0 min ago, the status [0-9]* min ago)" "$tmp/err")"
check "nothing is typed" "" "$(typed)"
check "and nothing is held" "free" "$(held)"
touch -t 202001010000 a.txt
touch "$dir/status/ann.md"

# A clear: the command, the wait until the screen is the cleared one and
# idle, the line to rejoin, the wait until it is taken.
start claude-idle "$tmp/cleared $tmp/cleared" "$tmp/joined"
check "a clear succeeds" "0" "$(run crew_clear ann)"
check "it typed /clear, then the line to rejoin" "/clear
$line" "$(typed)"
check "it says so" "cleared ann: it took the line to rejoin (crew join ann) and to resume from its Next:" "$(cat "$tmp/out")"
check "the hold is released" "free" "$(held)"

# A clear that does not end: the command still waits on the input line.
# shellcheck disable=SC2034 # read by lib/context.sh
context_clear_looks=3
start claude-idle
printf '%s\n' claude-typed claude-typed claude-typed claude-typed claude-typed >"$tmp/after1"
check "a clear that does not end fails" "1" "$(run crew_clear ann)"
check "it says what the pane shows" "1" "$(grep -c "ann's /clear did not end within about a minute: its pane shows typed" "$tmp/err")"
check "nothing more is typed" "/clear" "$(typed)"
check "the hold is released" "free" "$(held)"
# shellcheck disable=SC2034 # read by lib/context.sh
context_clear_looks=30

# The line to rejoin, typed but left on the input line, is not taken.
# shellcheck disable=SC2034 # read by lib/context.sh
context_join_looks=2
start claude-idle "$tmp/cleared $tmp/cleared" "$tmp/unsent $tmp/unsent $tmp/unsent"
check "a line not taken fails" "1" "$(run crew_clear ann)"
check "it says the line was not taken" "1" "$(grep -c 'does not show the line to rejoin as taken' "$tmp/err")"
# shellcheck disable=SC2034 # read by lib/context.sh
context_join_looks=15

# Codex: /new, and its thread is forgotten, so no wake goes to the old one.
member ann tmux:%1 codex
echo old-thread >"$dir/threads/ann"
sed "s/^› Ask Codex to do anything/› $line/" "$fixtures/codex-new.txt" >"$tmp/codex-unsent"
awk -v l="$line" '/^› Ask Codex/ && !done { print "› " l; print "• Working (1s • esc to interrupt)"; done = 1 } { print }' \
    "$fixtures/codex-new.txt" >"$tmp/codex-joined"
start codex-after-turn "codex-new codex-new" "$tmp/codex-joined"
check "a Codex member is cleared" "0" "$(run crew_clear ann)"
check "with /new" "/new" "$(typed | head -n 1)"
check "its old thread is forgotten" "no" "$([ -e "$dir/threads/ann" ] && echo yes || echo no)"

# The wakes: held while the hold's process lives, then sent; a hold whose
# process is gone counts for nothing.
member ann tmux:%1 claude
mkdir -p "$dir/tmp/hold"
echo "$$" >"$dir/tmp/hold/ann"
start claude-idle
check "a held wake is not typed" "1" "$(wake_one "$dir" 7 bob ann 2>/dev/null; echo $?)"
check "it is kept for later" "bob" "$(cat "$dir/tmp/wake.7.ann")"
check "nothing is typed" "" "$(typed)"
check "it says the member is being cleared or compacted" "1" "$(wake_one "$dir" 7 bob ann 2>&1 >/dev/null | grep -c 'is being cleared or compacted')"
gone=$(sh -c 'echo $$')
echo "$gone" >"$dir/tmp/hold/ann"
check "a hold whose process is gone wakes" "0" "$(wake_one "$dir" 8 bob ann 2>/dev/null; echo $?)"
check "and is removed" "free" "$(held)"
check "the line is typed" "crew: message 0008 from bob. Run: crew unread ann" "$(typed)"
rm -f "$dir"/tmp/wake.*

# After a clear, the newest held wake is sent if not read yet, and only it.
echo 3 >"$dir/cursors/ann"
echo bob >"$dir/tmp/wake.4.ann"
echo cat >"$dir/tmp/wake.5.ann"
start claude-idle "$tmp/cleared $tmp/cleared" "$tmp/joined"
check "a clear with wakes held" "0" "$(run crew_clear ann)"
check "the newest held wake is sent after the line to rejoin" "crew: message 0005 from cat. Run: crew unread ann" "$(typed | tail -n 1)"
check "no held wake is left" "" "$(wakes)"
echo 6 >"$dir/cursors/ann"
echo bob >"$dir/tmp/wake.5.ann"
start claude-idle "$tmp/cleared $tmp/cleared" "$tmp/joined"
run crew_clear ann >/dev/null
check "a held wake already read is not sent" "2" "$(typed | wc -l | tr -d ' ')"
check "and is dropped" "" "$(wakes)"

# Compact: the command, then the wait until the compacted mark comes and
# the agent is idle; nothing typed after it. A background shell is fine.
start claude-after-turn "claude-compacting claude-compacting claude-compacted claude-compacted"
check "a compact succeeds" "0" "$(run crew_compact ann)"
check "it typed /compact only" "/compact" "$(typed)"
check "it says so" "compacted ann" "$(cat "$tmp/out")"
check "the hold is released" "free" "$(held)"
start claude-shell "claude-compacting claude-compacted claude-compacted"
check "a compact with a background shell succeeds" "0" "$(run crew_compact ann keep the plan and the open review)"
check "Claude Code takes the instructions" "/compact keep the plan and the open review" "$(typed)"
member ann tmux:%1 codex
start codex-after-turn
check "instructions for Codex are refused" "1" "$(run crew_compact ann keep the plan)"
check "it says only Claude Code takes them" "crew: only Claude Code's /compact takes instructions; ann is codex, so nothing was typed" "$(err)"
start codex-after-turn "codex-compacting codex-compacted codex-compacted"
check "a Codex compact succeeds" "0" "$(run crew_compact ann)"
member ann tmux:%1 agy
start agy-after-turn "agy-compacting agy-compacted agy-compacted"
check "an Antigravity compact succeeds" "0" "$(run crew_compact ann)"
# shellcheck disable=SC2034 # read by lib/context.sh
context_compact_looks=3
start agy-after-turn "agy-compacting agy-compacting agy-compacting agy-compacting agy-compacting agy-compacting agy-compacting agy-compacting"
check "a compact that does not end fails" "1" "$(run crew_compact ann)"
check "it says what the pane shows" "1" "$(grep -c "ann's /compact did not end within about 10 minutes: its pane shows working" "$tmp/err")"
check "the hold is released" "free" "$(held)"


# The commands of a restart (crew up --restart), and its refusal of a
# background shell, which would die with the agent.
check "the quit commands" "/exit /quit /quit" "$(context_command claude restart) $(context_command codex restart) $(context_command agy restart)"
member ann tmux:%1 claude
start claude-shell
check "a restart with a background shell is refused" "1" "$(run context_start restart ann)"
check "it says the shell would die with the agent" "1" "$(grep -c "it would die with the agent" "$tmp/err")"
start claude-idle
check "an idle member may be restarted" "0" "$(run context_start restart ann)"

finish
