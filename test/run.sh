#!/bin/sh
# crew's tests: the gate's reading of screens, its rules, and its looks at a
# pane; the stream, the lock, the board, joining, spawning, and moving. No
# pane is touched: nothing here opens, moves, closes, or types into a pane
# of a terminal.
#
#   sh test/run.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
CREW_HOME=$(dirname "$here")
. "$CREW_HOME/lib/store.sh"
. "$CREW_HOME/lib/term.sh"
. "$CREW_HOME/lib/layout.sh"
. "$CREW_HOME/lib/panes.sh"
. "$CREW_HOME/lib/gate.sh"
export CREW_WAKE=0
# Every line of a log carries the time: one time here.
crew_stamp() { echo 12:00:00; }

passed=0
failed=0
check() {
    if [ "$2" = "$3" ]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$2" "$3"
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The gate reads the prompt at the bottom of a screen. Every fixture is a
# screen captured from the real agent with 'crew peek <name> 40'.
prompt() { gate_prompt <"$here/fixtures/$1.txt"; }
field() { prompt "$1" | cut -f"$2"; }
# Two screens one above the other: a prompt still drawn above a newer one.
stacked() { cat "$here/fixtures/$1.txt" "$here/fixtures/$2.txt" | gate_prompt | cut -f"$3"; }

check "codex prompt" "codex" "$(field codex-run 1)"
check "codex command" "cargo test --test editors" "$(field codex-run 2)"
check "codex wrapped, joined" "cd /Users/mrfoxes/Documents/repos/github.com/mrfoxes/tess && git sta sh push -m wip" "$(field codex-wrapped 2)"
check "codex wrapped, tight" "cd /Users/mrfoxes/Documents/repos/github.com/mrfoxes/tess && git stash push -m wip" "$(field codex-wrapped 3)"
check "codex idle" "" "$(prompt codex-idle)"
check "claude prompt" "claude" "$(field claude-run 1)"
check "claude command" "touch /private/tmp/crew-fixture-touch" "$(field claude-run 2)"
check "claude fetch" "other" "$(field claude-fetch 1)"
check "claude fetch text" "Do you want to allow Claude to fetch this content? ❯ 1. Yes 2. Yes, and don't ask again for example.com 3. No, and tell Claude what to do differently (esc)" "$(field claude-fetch 2)"
check "other prompt" "other" "$(field other 1)"
check "other text" "Allow access to this URL? https://example.com/notes > Yes, allow access No, deny access" "$(field other 2)"
check "claude edit is held" "other" "$(field claude-edit 1)"
check "claude command needing approval" "crew unread codex" "$(field claude-requires-approval 2)"
check "agy trust is held" "other" "$(field agy-trust 1)"
check "agy trust text" "Do you trust the contents of this project? Antigravity CLI requires permission to read, edit, and execute files here. > Yes, I trust this folder No, exit ↑/↓ Navigate · enter Confirm" "$(field agy-trust 2)"
check "codex trust is held" "other" "$(field codex-trust 1)"
check "codex working with a queued line" "" "$(prompt codex-queued)"
check "a question with no choices under it" "" "$(prompt claude-asks)"
check "a question below a Bash prompt is the one waiting" "other" "$(stacked claude-run other 1)"
check "a Bash prompt above a fetch does not approve it" "other" "$(stacked claude-run claude-fetch 1)"
check "the lower of two Bash prompts" "touch /private/tmp/crew-fixture-touch" "$(stacked claude-run claude-run 2)"
# The description above the rules is the agent's own text: one that ends in
# a question mark is not a question of another prompt.
check "a description ending in ?" "touch /private/tmp/crew-fixture-touch" "$(sed '16s/.*/ Does the file exist?/' "$here/fixtures/claude-run.txt" | gate_prompt | cut -f2)"

# The rules hold what they forbid, and nothing else.
rule() { gate_forbidden "$CREW_HOME/share/forbid" "$1" >/dev/null && echo hold || echo approve; }
while IFS='|' read -r want command; do
    check "rule: $command" "$want" "$(rule "$command")"
done <<'EOF2'
approve|cargo test --test editors
approve|cargo fmt --all --check
approve|cargo fmt -p tess --all -- --check
approve|git commit -s -F /tmp/message -- compiler/src/a.rs
approve|git commit --author=x -F m -- a.rs
approve|git add compiler/src/a.rs compiler/tests/b.rs
approve|git add -v compiler/src/a.rs
approve|git commit --author x -F m -- a.rs
approve|git branch --format %(refname) --list
approve|git push --follow-tags origin topic
approve|git push origin main && rm -r /p/.crew/lock
approve|git push -u origin topic
approve|git push origin --delete tmp-codex
approve|git -C /p checkout -b topic
approve|git checkout -b topic origin/main
approve|git switch -c topic
approve|git branch -d topic
approve|gh run watch 123
approve|git -C /p -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin main
approve|ps -axo pid,command | rg cargo
approve|gofmt -l .
approve|gofmt -w main.go
approve|prettier --write src/a.ts
approve|prettier --check .
approve|black --check .
approve|black src/a.py
approve|ruff format --check src
approve|ruff format src/a.py
approve|rm foo.txt
approve|find . -name '*.rs' -newer x
hold|cargo fmt --all
hold|cargo fmt --all --check && cargo fmt --all
hold|go fmt ./...
hold|gofmt -w .
hold|gofmt -w ./...
hold|npx prettier --write .
hold|prettier -w "src/**/*.ts"
hold|black .
hold|black --check . && black src/
hold|ruff format
hold|ruff format .
hold|git add -A
hold|git add -Av
hold|git add -u
hold|git add --update
hold|git add .
hold|git cherry-pick abc123
hold|git am 0001-fix.patch
hold|git filter-branch -f --tree-filter 'rm x' HEAD
hold|git filter-repo --path src
hold|git commit -am wip
hold|git commit -s --all
hold|git commit --amend --no-edit
hold|git stash push -m wip
hold|git -C /p reset --hard
hold|git checkout -- compiler/src/a.rs
hold|git checkout HEAD -- compiler/src/a.rs
hold|git checkout main
hold|git switch main
hold|git merge topic
hold|git restore compiler/src/a.rs
hold|git pull --rebase
hold|git branch -D topic
hold|git branch -f topic HEAD~3
hold|git worktree remove --force ../wt
hold|git push --force origin main
hold|git push -fu origin main
hold|git push --force-with-lease=main:abc origin main
hold|git push --mirror backup
hold|git push origin +main
hold|git push origin --delete main
hold|git push origin -d main
hold|git push origin :main
hold|git -c 'credential.helper=!gh auth git-credential' push -f origin main
hold|kill -TERM -- -42985
hold|cargo test; pkill -f nvim
hold|sudo rm /etc/hosts
hold|rm -rf target
hold|rm -f -r build
hold|rm --recursive target
hold|rm -r /p/.crew/lock/../messages && rm -rf src
hold|find . -name '*.o' -delete
EOF2
check "rule named" "git +reset" "$(gate_forbidden "$CREW_HOME/share/forbid" "git reset --hard")"

# Keys, as tmux gets them.
tmux() { echo "tmux $*"; }
check "key alt-m" "tmux send-keys -t %1 M-m" "$(term_key tmux:%1 alt-m)"
check "key ctrl-c" "tmux send-keys -t %1 C-c" "$(term_key tmux:%1 ctrl-c)"
check "key y" "tmux send-keys -t %1 -l -- y" "$(term_key tmux:%1 y)"
check "key delete" "tmux send-keys -t %1 DC" "$(term_key tmux:%1 delete)"
check "key unknown" "2" "$(term_key tmux:%1 f13 2>/dev/null; echo $?)"

# One look of the gate at a pane, with the screen read from a fixture and
# the keys it would press printed instead.
gate_rules=$CREW_HOME/share/forbid
gate_state=$tmp/gate
mkdir -p "$gate_state/held" "$gate_state/answered"
gate_dry=""
# The pane shows the fixtures named with show, one a read, the last for good.
show() { screens=$*; echo 1 >"$tmp/read.n"; }
term_read() {
    i=$(cat "$tmp/read.n")
    set -- $screens
    [ "$i" -le $# ] || i=$#
    eval "f=\$$i"
    echo $((i + 1)) >"$tmp/read.n"
    cat "$here/fixtures/$f.txt"
}
term_key() { echo "pressed $2"; }
show codex-run
check "gate approves" "pressed y
12:00:00 approved codex: cargo test --test editors" "$(gate_look codex tmux:%1)"
check "gate answers a screen once" "" "$(gate_look codex tmux:%1)"
show codex-idle
check "gate idle" "" "$(gate_look codex tmux:%1)"
show codex-run
check "gate approves again after a redraw" "pressed y
12:00:00 approved codex: cargo test --test editors" "$(gate_look codex tmux:%1)"
show codex-wrapped
check "gate holds the wrapped stash" "12:00:00 HOLD codex (git +(stash|restore|clean|rebase|pull|merge|checkout|switch|cherry-pick|am)( |\$)): cd /Users/mrfoxes/Documents/repos/github.com/mrfoxes/tess && git sta sh push -m wip" "$(gate_look codex tmux:%1)"
check "gate says a hold once" "" "$(gate_look codex tmux:%1)"
show claude-fetch
check "gate holds a fetch" "12:00:00 HOLD claude (not a command): Do you want to allow Claude to fetch this content? ❯ 1. Yes 2. Yes, and don't ask again for example.com 3. No, and tell Claude what to do differently (esc)" "$(gate_look claude tmux:%2)"
gate_dry=--dry
show claude-run
check "gate dry" "12:00:00 would approve claude: touch /private/tmp/crew-fixture-touch" "$(gate_look claude tmux:%2)"
# The press waits for a second read: the same prompt is answered, one gone
# in between is not.
gate_dry=""
rm -f "$gate_state/held/codex" "$gate_state/answered/codex"
show codex-run codex-idle
check "gate presses nothing for a prompt gone" "" "$(gate_look codex tmux:%1)"
rm -f "$gate_state/answered/codex"
show codex-run codex-run
check "gate presses for the same prompt" "pressed y
12:00:00 approved codex: cargo test --test editors" "$(gate_look codex tmux:%1)"

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

# Spawning over a pane: tmux, faked, splits before it; a pane of the other
# terminal is refused before either is asked.
tmux() { echo "$*" >>"$tmp/tmux.args"; [ "$1" != split-window ] || echo %5; }
check "spawn above in tmux" "tmux:%5" "$(TMUX=1 term_spawn above true tmux:%3)"
check "spawn above in tmux splits over the pane" "split-window -v -b -t %3 -P -F #{pane_id}" "$(sed -n 1p "$tmp/tmux.args")"
check "spawn above in tmux refuses an iTerm2 pane" "1" "$(TMUX=1 term_spawn above true iterm:X 2>/dev/null; echo $?)"
check "spawn above in iTerm2 refuses a tmux pane" "1" "$(TMUX='' term_spawn above true tmux:%3 2>/dev/null; echo $?)"
# Beside a pane: tmux splits it side by side, then spreads the row out.
: >"$tmp/tmux.args"
check "spawn beside in tmux" "tmux:%5" "$(TMUX=1 term_spawn beside true tmux:%3)"
check "spawn beside in tmux splits the pane side by side, then evens the row" "split-window -h -t %3 -P -F #{pane_id}
select-layout -E -t %5" "$(sed -n 1,2p "$tmp/tmux.args")"
check "spawn beside in tmux refuses an iTerm2 pane" "1" "$(TMUX=1 term_spawn beside true iterm:X 2>/dev/null; echo $?)"
check "spawn beside in iTerm2 refuses a tmux pane" "1" "$(TMUX='' term_spawn beside true tmux:%3 2>/dev/null; echo $?)"

# Moving a pane: tmux joins it to the other, the focus left where it is,
# beside it (the row evened out), under it, or over it; panes of two
# terminals, or a pane and itself, are refused before either is asked.
# iTerm2 is faked too, so that a slip moves no live pane.
osascript() { echo "$*" >>"$tmp/osascript.args"; return 1; }
moved() { : >"$tmp/tmux.args"; term_move "$@"; cat "$tmp/tmux.args"; }
check "move beside in tmux" "join-pane -d -h -s %4 -t %3
select-layout -E -t %4" "$(moved tmux:%4 beside tmux:%3)"
check "move below in tmux" "join-pane -d -v -s %4 -t %3" "$(moved tmux:%4 below tmux:%3)"
check "move above in tmux" "join-pane -d -v -b -s %4 -t %3" "$(moved tmux:%4 above tmux:%3)"
check "move refuses panes of two terminals" "" "$(moved tmux:%4 beside iterm:X 2>/dev/null)"
check "move refuses panes of two terminals, failing" "1" "$(term_move iterm:X below tmux:%3 2>/dev/null; echo $?)"
check "move refuses a pane next to itself" "" "$(moved tmux:%4 above tmux:%4 2>/dev/null)"
check "move refuses a pane next to itself, failing" "1" "$(term_move tmux:%4 above tmux:%4 2>/dev/null; echo $?)"
check "move wants a place it knows" "2" "$(term_move tmux:%4 left tmux:%3 2>/dev/null; echo $?)"
tmux() { return 1; }
check "move fails when tmux does" "1" "$(term_move tmux:%4 beside tmux:%3 2>/dev/null; echo $?)"
check "move in tmux asks no iTerm2" "" "$(cat "$tmp/osascript.args" 2>/dev/null)"
unset -f osascript
tmux() { echo "tmux $*"; }

# Spawning: the line the owner's shell gets, with the pane faked.
term_spawn() { printf '%s\n' "$2" >"$tmp/spawn.line"; echo tmux:%9; }
check "spawn" "agy: tmux:%9" "$(crew_spawn agy claude --model 'x y' "it's")"
check "spawn keeps each word whole" "cd $(cd "$tmp/repo" && pwd -P) && claude --model 'x y' 'it'\\''s'" "$(cat "$tmp/spawn.line")"
check "spawn records the pane" "tmux:%9" "$(cat "$dir/panes/agy")"
crew_spawn agy --tab 'cd sub && codex' >/dev/null
check "spawn passes one word to the shell" "cd $(cd "$tmp/repo" && pwd -P) && cd sub && codex" "$(cat "$tmp/spawn.line")"
check "spawn wants a command" "2" "$(crew_spawn agy --tab >/dev/null 2>&1; echo $?)"
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
check "join with a pane" "You are claude, in the crew at $dir, in the pane tmux:%7: a message to you is typed into it." "$(crew_join claude --pane 'tmux:%7' | sed -n 1p)"
check "join keeps the pane" "tmux:%7" "$(cat "$dir/panes/claude")"
check "join refuses a recipient" "2" "$(crew_join all >/dev/null 2>&1; echo $?)"
# A sandbox that hides the pane does not lose the one spawn recorded.
term_self() { return 1; }
check "join from a hidden pane keeps the spawned one" "tmux:%7" "$(crew_join claude >/dev/null; cat "$dir/panes/claude")"
check "join from nowhere says so" "You are agy, in the crew at $dir, in no pane crew can find: run 'crew unread agy' often." "$(crew_join agy | sed -n 1p)"
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
check "board shows the age" "1" "$(crew_board 1 | grep -c '^== agy (no pane, 0 min ago)$')"
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
check "join with a thread and no pane says so" "You are codex, in the crew at $dir, in no pane crew can find; a message to you is queued to your Codex thread." "$(crew_join codex | sed -n 1p)"
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
check "board tells a pane that is gone" "1" "$(crew_board 1 | grep -c '^== agy (tmux:%8 gone, 0 min ago)$')"
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
crew_invite() { echo "invite $1"; }
check "spawn with --join invites" "agy: tmux:%9
invite agy" "$(crew_spawn agy --tab --join true)"
rm -f "$dir/panes/agy"

printf '%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
