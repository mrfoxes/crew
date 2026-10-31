#!/bin/sh
# crew's tests: the gate's reading of screens, its rules, and its looks at a
# pane; the stream, the lock, the board, and joining. No pane is touched:
# nothing here types into a terminal.
#
#   sh test/run.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
CREW_HOME=$(dirname "$here")
. "$CREW_HOME/lib/store.sh"
. "$CREW_HOME/lib/term.sh"
. "$CREW_HOME/lib/panes.sh"
. "$CREW_HOME/lib/gate.sh"
export CREW_WAKE=0

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
hold|git add .
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
approved codex: cargo test --test editors" "$(gate_look codex tmux:%1)"
check "gate answers a screen once" "" "$(gate_look codex tmux:%1)"
show codex-idle
check "gate idle" "" "$(gate_look codex tmux:%1)"
show codex-run
check "gate approves again after a redraw" "pressed y
approved codex: cargo test --test editors" "$(gate_look codex tmux:%1)"
show codex-wrapped
check "gate holds the wrapped stash" "HOLD codex (git +(stash|restore|clean|rebase|pull|merge|checkout|switch)( |\$)): cd /Users/mrfoxes/Documents/repos/github.com/mrfoxes/tess && git sta sh push -m wip" "$(gate_look codex tmux:%1)"
check "gate says a hold once" "" "$(gate_look codex tmux:%1)"
show claude-fetch
check "gate holds a fetch" "HOLD claude (not a command): Do you want to allow Claude to fetch this content? ❯ 1. Yes 2. Yes, and don't ask again for example.com 3. No, and tell Claude what to do differently (esc)" "$(gate_look claude tmux:%2)"
gate_dry=--dry
show claude-run
check "gate dry" "would approve claude: touch /private/tmp/crew-fixture-touch" "$(gate_look claude tmux:%2)"
# The press waits for a second read: the same prompt is answered, one gone
# in between is not.
gate_dry=""
rm -f "$gate_state/held/codex" "$gate_state/answered/codex"
show codex-run codex-idle
check "gate presses nothing for a prompt gone" "" "$(gate_look codex tmux:%1)"
rm -f "$gate_state/answered/codex"
show codex-run codex-run
check "gate presses for the same prompt" "pressed y
approved codex: cargo test --test editors" "$(gate_look codex tmux:%1)"

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
check "board status" "== codex (no pane)" "$(printf '%s\n' "$board" | grep -x '== codex (no pane)')"
check "board lock" "== lock: free" "$(printf '%s\n' "$board" | grep -x '== lock: free')"
check "board messages" "3" "$(printf '%s\n' "$board" | grep -c '^00[0-9][0-9]-')"
check "join with a pane" "You are claude, in the crew at $dir, in the pane tmux:%7: a message to you is typed into it." "$(crew_join claude --pane 'tmux:%7' | sed -n 1p)"
check "join keeps the pane" "tmux:%7" "$(cat "$dir/panes/claude")"
check "join refuses a recipient" "2" "$(crew_join all >/dev/null 2>&1; echo $?)"

# The wake line: number, sender, command; never the subject.
term_poke() { echo "$1 <- $2"; }
check "wake line" "tmux:%7 <- crew: message 0012 from codex. Run: crew unread claude" "$(crew_wake "$dir" 12 codex claude "Review: @nogc")"

# The relay: a step wakes what came after its last number; while it runs
# (its pid file fresh), crew send leaves the waking to it.
n=$(basename "$(echo body | crew_send codex claude "Heads-up: relayed")" | cut -c1-4 | sed 's/^0*//')
echo "$((n - 1))" >"$tmp/relay.last"
nn=$(printf '%04d' "$n")
check "relay step wakes the new message" "tmux:%7 <- crew: message $nn from codex. Run: crew unread claude
relay: $nn from codex to claude" "$(crew_relay_step "$dir" "$tmp/relay.last")"
check "relay step moves on" "$n" "$(cat "$tmp/relay.last")"
check "relay step wakes nothing twice" "" "$(crew_relay_step "$dir" "$tmp/relay.last")"
check "no relay" "1" "$(crew_relay_alive "$dir"; echo $?)"
echo 1 >"$dir/relay.pid"
check "relay alive" "0" "$(crew_relay_alive "$dir"; echo $?)"
check "send leaves waking to the relay" "" "$(CREW_WAKE=1; echo x | crew_send codex claude "Heads-up: quiet" 2>&1 >/dev/null)"
touch -t 202001010000 "$dir/relay.pid"
check "relay stale" "1" "$(crew_relay_alive "$dir"; echo $?)"
m=$(printf '%04d' $((n + 2)))
check "send wakes when the relay is gone" "tmux:%7 <- crew: message $m from codex. Run: crew unread claude" "$(CREW_WAKE=1; echo x | crew_send codex claude "Heads-up: loud" | tail -n 1)"
rm -f "$dir/relay.pid"

printf '%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
