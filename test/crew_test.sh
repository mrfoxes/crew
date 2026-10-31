#!/bin/sh
# The crew's tests: the stream, the lock, the board, joining, spawning,
# moving, waking, the relay, muting, the archive, and inviting, in one
# crew made in a temporary repository, one step after another.
#
#   sh test/run.sh crew

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

tmux() { echo "tmux $*"; }
term_read() { fixture_read; }
# The agent a join runs under: none, unless a check says otherwise; the
# tests run under whatever agent runs them.
kind_of_self() { :; }
# The names and colors a pane gets, one a line, instead of the terminal's.
term_name() { echo "name $1 $2" >>"$tmp/labels"; }
term_color() { echo "color $1 ${2:-}" >>"$tmp/labels"; }
term_tab() { echo "tab $1 $2" >>"$tmp/labels"; }

# A member runs the tests from its pane, CREW_DIR naming its live crew: the
# harness forgets both, so no test reaches that crew or that pane.
check "the tests leave the crew and the pane they run from" "" "${CREW_DIR:-}${TMUX:-}${TMUX_PANE:-}${ITERM_SESSION_ID:-}${TERM_SESSION_ID:-}"

# The stream: init, numbering under contention, routing, and the lock.
git init -q "$tmp/repo"
git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$tmp/repo/a/b"
cd "$tmp/repo/a/b" || exit 1
dir=$(crew_init)
check "init at the root" "$(cd "$tmp/repo" && pwd -P)/.crew" "$dir"
check "init excluded" "/.crew/" "$(grep -x '/.crew/' "$tmp/repo/.git/info/exclude")"
check "found from below" "$dir" "$(crew_dir)"
git -C "$tmp/repo" worktree add -q "$tmp/wt" 2>/dev/null
check "found from a worktree" "$dir" "$(cd "$tmp/wt" && crew_dir)"

# The crew kept at home: ~/.crew/<project>, with the tree untouched, found
# from the project and below it, after the one in the tree.
home=$tmp/home
git init -q "$tmp/repo2"
root2=$(cd "$tmp/repo2" && pwd -P)
dir2=$home/.crew/$(printf '%s' "$root2" | tr -c 'A-Za-z0-9' '-')
check "init at home" "$dir2" "$(HOME=$home; cd "$tmp/repo2" && crew_init --home)"
check "init at home names the project" "$root2" "$(cat "$dir2/project")"
check "init at home leaves the tree alone" "" "$(find "$tmp/repo2" -mindepth 1 -maxdepth 1 ! -name .git)"
check "init at home excludes nothing" "" "$(grep '/.crew/' "$tmp/repo2/.git/info/exclude" 2>/dev/null)"
check "found at home" "$dir2" "$(HOME=$home; cd "$tmp/repo2" && crew_dir)"
mkdir -p "$tmp/repo2/x/y"
check "found at home from below" "$dir2" "$(HOME=$home; cd "$tmp/repo2/x/y" && crew_dir)"
check "board at home finds git" "1" "$(HOME=$home; cd "$tmp/repo2" && crew_board | grep -c '^== git')"
(HOME=$home; crew_init --home >/dev/null)
check "the crew in the tree comes first" "$dir" "$(HOME=$home; cd "$tmp/repo" && crew_dir)"
check "no crew" "1" "$(HOME=$home; cd "$tmp" && crew_dir >/dev/null 2>&1; echo $?)"
# ~/.crew holds the crews kept at home; from below it, it is not one.
mkdir -p "$home/work/other"
check "no crew under home" "1" "$(HOME=$home; cd "$home/work/other" && crew_dir >/dev/null 2>&1; echo $?)"
check "unread needs a crew" "1" "$(HOME=$home; cd "$home/work/other" && crew_unread codex >/dev/null 2>&1; echo $?)"

i=1
while [ "$i" -le 8 ]; do
    echo "body $i" | crew_send codex all "Plan: slice $i" >/dev/null &
    i=$((i + 1))
done
wait
check "eight numbers" "1 2 3 4 5 6 7 8" "$(ls "$dir/seq" | sort -n | tr '\n' ' ' | sed 's/ $//')"
check "eight messages" "8" "$(ls "$dir/messages" | wc -l | tr -d ' ')"
check "time with date" "1" "$(grep -c '^Time: [0-9]\{4\}-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]$' "$dir/seq/1")"

echo "to claude" | crew_send agy claude "Question: which allocator?" >/dev/null
echo "to agy" | crew_send claude agy "Answer: TLSF" >/dev/null
check "unread to claude" "9" "$(crew_unread claude | grep -c '^# ')"
check "unread marks read" "No new messages for claude." "$(crew_unread claude)"
check "unread skips own" "0" "$(crew_unread codex | grep -c '^# ')"
check "message file" "0010-claude-to-agy-answer-tlsf.md" "$(basename "$dir"/messages/0010-*)"
check "bad name" "2" "$(echo x | crew_send Codex all "x" >/dev/null 2>&1; echo $?)"
# A body is not a header: lines in it that look like one route nothing.
echo "To: claude" | crew_send codex agy "Heads-up: a header line in a body" >/dev/null
echo "From: claude" | crew_send codex claude "Heads-up: another" >/dev/null
check "unread reads the header, not the body" "0012" "$(crew_unread claude | sed -n 's/^# \([0-9]*\)\..*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
check "send to one who has not joined says so" "crew: nobody has no pane; the message waits for 'crew unread nobody'" "$(CREW_WAKE=1; echo x | crew_send codex nobody "Question: anyone?" 2>&1 >/dev/null)"

check "lock taken" "lock taken by codex" "$(crew_lock codex)"
check "lock busy" "1" "$(crew_lock claude 2>/dev/null; echo $?)"
check "lock busy says who" "1" "$(crew_lock claude 2>&1 | grep -c 'held by codex')"
touch -t 202001010000 "$dir/lock"
check "lock stale" "1" "$(crew_lock claude 2>&1 | grep -c 'stale')"
check "unlock by another" "1" "$(crew_unlock claude 2>/dev/null; echo $?)"
check "unlock" "lock released" "$(crew_unlock codex)"

# The board, and joining with a pane given.
printf 'Agent: codex\nIssue: #1\n' >"$dir/status/codex.md"
board=$(crew_board 3)
check "board status" "== codex (no pane, 0 min ago)" "$(printf '%s\n' "$board" | grep -x '== codex (no pane, 0 min ago)')"
check "board lock" "== lock: free" "$(printf '%s\n' "$board" | grep -x '== lock: free')"
check "board messages" "3" "$(printf '%s\n' "$board" | grep -c '^00[0-9][0-9]-')"
check "board wants a count" "2" "$(crew_board three >/dev/null 2>&1; echo $?)"
check "peek wants a count" "2" "$(crew_peek tmux:%1 many >/dev/null 2>&1; echo $?)"

# Spawning: the line the owner's shell gets, with the pane faked.
term_spawn() { printf '%s\n' "$2" >"$tmp/spawn.line"; echo tmux:%9; }
check "spawn" "agy: tmux:%9" "$(crew_spawn agy claude --model 'x y' "it's")"
check "spawn keeps each word whole" "cd $(cd "$tmp/repo" && pwd -P) && claude --model 'x y' 'it'\\''s'" "$(cat "$tmp/spawn.line")"
check "spawn records the pane" "tmux:%9" "$(cat "$dir/panes/agy")"
crew_spawn agy --tab runtime 'cd sub && codex' >/dev/null
check "spawn passes one word to the shell" "cd $(cd "$tmp/repo" && pwd -P) && cd sub && codex" "$(cat "$tmp/spawn.line")"
check "spawn wants a command" "2" "$(crew_spawn agy --tab runtime >/dev/null 2>&1; echo $?)"
check "spawn wants a tab's name" "2" "$(crew_spawn agy --tab >/dev/null 2>&1; echo $?)"
term_spawn() { printf '%s %s\n' "$1" "${3:-}" >"$tmp/spawn.where"; echo tmux:%9; }
crew_spawn codex --below agy codex >/dev/null
check "spawn below a member" "below tmux:%9" "$(cat "$tmp/spawn.where")"
check "spawn below one with no pane" "1" "$(crew_spawn codex --below nobody codex >/dev/null 2>&1; echo $?)"
check "spawn below wants a member" "2" "$(crew_spawn codex --below >/dev/null 2>&1; echo $?)"
crew_spawn codex --above agy codex >/dev/null
check "spawn above a member" "above tmux:%9" "$(cat "$tmp/spawn.where")"
crew_spawn codex --above iterm:X codex >/dev/null
check "spawn above a pane" "above iterm:X" "$(cat "$tmp/spawn.where")"
check "spawn above one with no pane" "1" "$(crew_spawn codex --above nobody codex >/dev/null 2>&1; echo $?)"
check "spawn above wants a member" "2" "$(crew_spawn codex --above >/dev/null 2>&1; echo $?)"
crew_spawn codex --beside agy codex >/dev/null
check "spawn beside a member" "beside tmux:%9" "$(cat "$tmp/spawn.where")"
crew_spawn codex --beside iterm:X codex >/dev/null
check "spawn beside a pane" "beside iterm:X" "$(cat "$tmp/spawn.where")"
check "spawn beside one with no pane" "1" "$(crew_spawn codex --beside nobody codex >/dev/null 2>&1; echo $?)"
check "spawn beside wants a member" "2" "$(crew_spawn codex --beside >/dev/null 2>&1; echo $?)"

# Moving: the panes of the two go to the terminal, and the pane recorded
# stays: a moved pane keeps its id.
term_move() { printf '%s %s %s\n' "$1" "$2" "$3" >"$tmp/move.args"; }
echo tmux:%8 >"$dir/panes/codex"
check "move beside a member" "agy: tmux:%9, now beside codex" "$(crew_move agy --beside codex)"
check "move passes both panes" "tmux:%9 beside tmux:%8" "$(cat "$tmp/move.args")"
check "move keeps the panes recorded" "tmux:%9 tmux:%8" "$(cat "$dir/panes/agy" "$dir/panes/codex" | tr '\n' ' ' | sed 's/ $//')"
crew_move agy --above iterm:X >/dev/null
check "move over a pane" "tmux:%9 above iterm:X" "$(cat "$tmp/move.args")"
crew_move tmux:%7 --below agy >/dev/null
check "move a pane under a member" "tmux:%7 below tmux:%9" "$(cat "$tmp/move.args")"
check "move one with no pane" "1" "$(crew_move nobody --beside agy >/dev/null 2>&1; echo $?)"
check "move beside one with no pane" "1" "$(crew_move agy --beside nobody >/dev/null 2>&1; echo $?)"
check "move wants a place" "2" "$(crew_move agy codex >/dev/null 2>&1; echo $?)"
check "move wants a place it knows" "2" "$(crew_move agy --left codex >/dev/null 2>&1; echo $?)"
term_move() { return 1; }
check "move that fails prints no place" "1" "$(crew_move agy --beside codex 2>/dev/null; echo $?)"
rm -f "$dir/panes/agy" "$dir/panes/codex"
# The terminal, as every machine sees it: one tmux pane, %7.
term_list() { printf 'tmux:%%7\t/dev/ttys001\tsh\n'; }
check "a pane the terminal lists" "1" "$(term_gone tmux:%7; echo $?)"
check "a pane the terminal lost" "0" "$(term_gone tmux:%8; echo $?)"
check "a pane of a terminal that cannot be asked" "1" "$(term_gone iterm:X; echo $?)"
check "join with a pane" "You are claude, of kind other, in the crew at $dir, in the pane tmux:%7: a message to you is typed into it." "$(crew_join claude --pane 'tmux:%7' | sed -n 1p)"
check "join keeps the pane" "tmux:%7" "$(cat "$dir/panes/claude")"
check "join refuses a recipient" "2" "$(crew_join all >/dev/null 2>&1; echo $?)"
# A sandbox that hides the pane does not lose the one spawn recorded.
term_self() { return 1; }
check "join from a hidden pane keeps the spawned one" "tmux:%7" "$(crew_join claude >/dev/null; cat "$dir/panes/claude")"
check "join from nowhere says so" "You are agy, of kind codex, in the crew at $dir, in no pane crew can find: run 'crew unread agy' often." "$(crew_join agy | sed -n 1p)"
# A subject is one line.
f=$(echo x | crew_send codex agy "Heads-up: one
two")
check "subject on one line" "codex to agy: Heads-up: one two" "$(sed -n '1s/^# [0-9]*\. //p' "$f")"

# The wake line: number, sender, command; never the subject.
term_poke() { echo "$1 <- $2"; }
check "wake line" "tmux:%7 <- crew: message 0012 from codex. Run: crew unread claude" "$(crew_wake "$dir" 12 codex claude "Review: @nogc")"

# The relay: while it runs (its pid file fresh), crew send leaves the waking
# to it, and a step wakes what came after its last number; a message its
# sender woke, or posted with CREW_WAKE=0, it leaves alone.
number() { basename "$1" | cut -c1-4 | sed 's/^0*//'; }
check "no relay" "1" "$(crew_relay_alive "$dir"; echo $?)"
echo 1 >"$dir/relay.pid"
check "relay alive" "0" "$(crew_relay_alive "$dir"; echo $?)"
f=$(CREW_WAKE=1; echo x | crew_send codex claude "Heads-up: relayed" 2>&1)
check "send leaves waking to the relay" "$dir/messages/$(basename "$f")" "$f"
n=$(number "$f")
echo "$((n - 1))" >"$tmp/relay.last"
nn=$(printf '%04d' "$n")
check "relay step wakes the new message" "tmux:%7 <- crew: message $nn from codex. Run: crew unread claude
12:00:00 relay: $nn from codex to claude" "$(crew_relay_step "$dir" "$tmp/relay.last")"
check "relay step moves on" "$n" "$(cat "$tmp/relay.last")"
check "relay step wakes nothing twice" "" "$(crew_relay_step "$dir" "$tmp/relay.last")"
touch -t 202001010000 "$dir/relay.pid"
check "relay stale" "1" "$(crew_relay_alive "$dir"; echo $?)"
m=$(printf '%04d' $((n + 1)))
check "send wakes when the relay is gone" "tmux:%7 <- crew: message $m from codex. Run: crew unread claude" "$(CREW_WAKE=1; echo x | crew_send codex claude "Heads-up: loud" | tail -n 1)"
echo body | crew_send codex claude "Heads-up: silent" >/dev/null
check "relay step leaves woken and silent messages alone" "" "$(crew_relay_step "$dir" "$tmp/relay.last")"
check "relay step still moves on" "$((n + 2))" "$(cat "$tmp/relay.last")"
rm -f "$dir/relay.pid"

# Reading the stream again: the last few, or one by number.
check "log" "3" "$(crew_log 3 | grep -c '^# ')"
check "log ends with the last" "$((n + 2))" "$(crew_log 1 | sed -n 's/^# \([0-9]*\)\..*/\1/p' | sed 's/^0*//')"
check "log wants a count" "2" "$(crew_log five >/dev/null 2>&1; echo $?)"
check "show" "# 0009. agy to claude: Question: which allocator?" "$(crew_show 0009 | sed -n 2p)"
check "show two" "2" "$(crew_show 9 10 | grep -c '^# ')"
check "show a missing one" "1" "$(crew_show 9999 >/dev/null 2>&1; echo $?)"

# Status and report from stdin, and the age of a status on the board.
check "status" "$dir/status/agy.md" "$(printf 'Agent: agy\nNext: nothing\n' | crew_write status agy)"
check "status written" "Next: nothing" "$(sed -n 2p "$dir/status/agy.md")"
check "board shows the age and the kind" "1" "$(crew_board 1 | grep -c '^== agy (codex, tab runtime, no pane, 0 min ago)$')"
check "report" "$dir/reports/agy.md" "$(echo finished | crew_write report agy)"
check "status wants a name" "2" "$(echo x | crew_write status >/dev/null 2>&1; echo $?)"
check "gate wants a name" "2" "$(gate_setup --dry >/dev/null 2>&1; echo $?)"

# Leaving, and the archive: the stream starts over; the plan and the panes stay.
check "leave" "claude has no pane now; messages to claude wait for 'crew unread claude'" "$(crew_leave claude)"
check "leave forgets the pane" "" "$(cat "$dir/panes/claude" 2>/dev/null)"
echo plan >"$dir/README.md"
echo "tmux:%7" >"$dir/panes/claude"
echo 1 >"$dir/relay.pid"
check "archive waits for the relay" "1" "$(crew_archive >/dev/null 2>&1; echo $?)"
rm -f "$dir/relay.pid"
to=$(crew_archive)
check "archive" "$dir/archive" "$(dirname "$to")"
check "archive keeps the messages" "$((n + 2))" "$(ls "$to/messages" | wc -l | tr -d ' ')"
check "archive keeps the statuses" "2" "$(ls "$to/status" | wc -l | tr -d ' ')"
check "archive starts the stream over" "" "$(ls "$dir/seq")"
check "archive keeps the plan and the panes" "plan tmux:%7" "$(cat "$dir/README.md" "$dir/panes/claude" | tr '\n' ' ' | sed 's/ $//')"
check "archive forgets the wake claims" "" "$(ls -d "$dir"/tmp/wake.* 2>/dev/null)"
check "nothing to archive" "crew: nothing to archive" "$(crew_archive)"
check "numbers start over" "0001" "$(basename "$(echo x | crew_send codex claude "Plan: again")" | cut -c1-4)"

# Joining from Codex: its daemon's variables name another pane, so the
# recorded one stays, a gone one goes, and the thread is kept for the wake.
echo "tmux:%7" >"$dir/panes/codex"
term_self() { echo tmux:%8; }
check "join keeps a recorded pane over the one the environment names" "tmux:%7" "$(crew_join codex >/dev/null; cat "$dir/panes/codex")"
echo "tmux:%8" >"$dir/panes/codex"
term_self() { echo tmux:%7; }
check "join drops a recorded pane that is gone" "tmux:%7" "$(crew_join codex >/dev/null; cat "$dir/panes/codex")"
term_self() { return 1; }
check "join records the thread" "abc-123" "$(CODEX_THREAD_ID=abc-123 crew_join codex >/dev/null; cat "$dir/threads/codex")"
rm -f "$dir/panes/codex"
check "join with a thread and no pane says so" "You are codex, of kind codex, in the crew at $dir, in no pane crew can find; a message to you is queued to your Codex thread." "$(crew_join codex | sed -n 1p)"
check "self in Codex ignores the daemon's pane" "1" "$(CODEX_THREAD_ID=abc ITERM_SESSION_ID=w0t0p0:X term_self >/dev/null; echo $?)"
# The wake goes through the thread first, the pane when the thread is gone,
# and to every member with either.
codex() { echo "codex $*" >"$tmp/codex.args"; }
check "wake queues to the thread" "" "$(crew_wake "$dir" 12 claude codex "x")"
check "wake queue line" "codex queue --thread abc-123 --message crew: message 0012 from claude. Run: crew unread codex" "$(cat "$tmp/codex.args")"
codex() { return 1; }
check "wake with the thread gone and no pane" "crew: codex has no pane; the message waits for 'crew unread codex'" "$(crew_wake "$dir" 12 claude codex "x" 2>&1)"
echo "tmux:%7" >"$dir/panes/codex"
check "wake with the thread gone types into the pane" "tmux:%7 <- crew: message 0012 from claude. Run: crew unread codex" "$(crew_wake "$dir" 12 claude codex "x" 2>&1)"
rm -f "$dir/panes/codex"
codex() { echo "codex $*" >"$tmp/codex.args"; }
check "wake to all reaches a member with a thread only" "tmux:%7 <- crew: message 0012 from agy. Run: crew unread claude
codex queue --thread abc-123 --message crew: message 0012 from agy. Run: crew unread codex" "$(crew_wake "$dir" 12 agy all "x" 2>&1; cat "$tmp/codex.args")"
# A muted member is woken by a message to its name, not by one to all, and
# reads both.
check "mute" "codex is muted: a message to all no longer wakes it, one to codex still does" "$(crew_mute codex)"
rm -f "$tmp/codex.args"
check "wake to all passes over a muted member" "tmux:%7 <- crew: message 0012 from agy. Run: crew unread claude
crew: codex is muted; the message waits for 'crew unread codex'" "$(crew_wake "$dir" 12 agy all "x" 2>&1)"
check "wake to all queues nothing to a muted member" "" "$(cat "$tmp/codex.args" 2>/dev/null)"
check "wake to a muted member by name" "codex queue --thread abc-123 --message crew: message 0012 from claude. Run: crew unread codex" "$(crew_wake "$dir" 12 claude codex "x"; cat "$tmp/codex.args")"
echo x | crew_send claude all "Heads-up: to everyone" >/dev/null
check "a muted member reads a message to all" "1" "$(crew_unread codex | grep -c 'claude to all: Heads-up: to everyone$')"
check "mute refuses a recipient" "2" "$(crew_mute all >/dev/null 2>&1; echo $?)"
check "unmute" "codex is woken by messages to all again" "$(crew_unmute codex)"
rm -f "$tmp/codex.args"
check "wake to all reaches an unmuted member" "codex queue --thread abc-123 --message crew: message 0012 from agy. Run: crew unread codex" "$(crew_wake "$dir" 12 agy all "x" >/dev/null 2>&1; cat "$tmp/codex.args")"
check "leave forgets the thread" "" "$(crew_leave codex >/dev/null; cat "$dir/threads/codex" 2>/dev/null)"

# The board tells a pane that is gone.
printf 'Agent: agy\n' >"$dir/status/agy.md"
echo "tmux:%8" >"$dir/panes/agy"
check "board tells a pane that is gone" "1" "$(crew_board 1 | grep -c '^== agy (codex, tab runtime, tmux:%8 gone, 0 min ago)$')"
printf 'Agent: claude\n' >"$dir/status/claude.md"
check "board tells a pane that is there" "1" "$(crew_board 1 | grep -c '^== claude (tmux:%7, 0 min ago)$')"
crew_mute claude >/dev/null
check "board tells a muted member" "1" "$(crew_board 1 | grep -c '^== claude (tmux:%7, muted, 0 min ago)$')"
crew_unmute claude >/dev/null
rm -f "$dir/panes/agy"

# Inviting: once something other than the shell runs in the pane and the
# screen has settled, the join line goes in; a prompt waiting is printed.
term_tty() { echo /dev/ttys001; }
term_running() { return 0; }
show codex-idle
check "invite" 'tmux:%7 <- Run: crew join claude. Then follow the protocol it prints. Work in caveman mode ($caveman) from now on.
claude invited' "$(crew_invite claude 5)"
show codex-trust
check "invite finds a prompt waiting" "crew: claude waits on a prompt: Trust this folder? Codex can read, edit, and run files here, subject to your permission settings. Folder settings can run code automatically, even without a model request. Continue only if you trust these files. Your trust decision will be saved. › 1. Trust and continue 2. Back to Agent Command Center enter continue · esc back" "$(crew_invite claude 5 2>&1 >/dev/null | sed -n 1p)"
term_running() { return 1; }
show codex-idle
check "invite gives up on a shell" "crew: nothing but a shell in claude's pane after 1 seconds" "$(crew_invite claude 1 2>&1 >/dev/null)"
check "invite wants seconds" "2" "$(crew_invite claude soon >/dev/null 2>&1; echo $?)"
# An idle agent redraws: a notice comes and goes (Claude Code 2.1.316), a
# hint turns. Its input line, drawn on two reads in a row, is enough.
term_running() { return 0; }
kind_record "$dir" claude claude
show claude-idle claude-idle-notice claude-idle claude-idle-notice claude-idle claude-idle-notice
check "invite an idle agent whose notices come and go" 'tmux:%7 <- Run: crew join claude. Then follow the protocol it prints. Work in caveman mode ($caveman) from now on.
claude invited' "$(crew_invite claude 3)"
sed 's/❯ Try "how does <filepath> work?"/❯ Try "write a test for <filepath>"/' "$here/fixtures/claude-idle.txt" >"$tmp/hint.txt"
show claude-idle "$tmp/hint.txt" claude-idle "$tmp/hint.txt"
check "invite an idle agent whose hint turns" "claude invited" "$(crew_invite claude 3 | tail -n 1)"
kind_record "$dir" claude other
show claude-idle claude-idle-notice claude-idle claude-idle-notice claude-idle claude-idle-notice
check "invite gives up on a screen that never settles" "crew: claude's agent runs, but after 2 seconds its screen has not settled, nor shown its input line" "$(crew_invite claude 2 2>&1 >/dev/null | sed -n 1p)"
term_running() { return 1; }
crew_invite() { echo "invite $1"; }
check "spawn with --join invites" "agy: tmux:%9
invite agy" "$(crew_spawn agy --tab runtime --join true)"
rm -f "$dir/panes/agy"


finish
