#!/bin/sh
# crew's tests: the gate's reading of screens and its rules, and the stream.
# No pane is touched: nothing here types into a terminal.
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

# The gate reads the prompt at the bottom of a screen.
prompt() { gate_prompt <"$here/fixtures/$1.txt"; }
field() { prompt "$1" | cut -f"$2"; }

check "codex prompt" "codex" "$(field codex-run 1)"
check "codex command" "cargo test --test editors" "$(field codex-run 2)"
check "codex wrapped, joined" "cd /Users/mrfoxes/Documents/repos/github.com/mrfoxes/tess && git sta sh push -m wip" "$(field codex-wrapped 2)"
check "codex wrapped, tight" "cd /Users/mrfoxes/Documents/repos/github.com/mrfoxes/tess && git stash push -m wip" "$(field codex-wrapped 3)"
check "codex idle" "" "$(prompt codex-idle)"
# claude-run.txt follows the strings in Claude Code's binary, not a captured
# screen: replace it with one from 'crew peek <name> 40' at the first chance.
check "claude prompt" "claude" "$(field claude-run 1)"
check "claude command" "git status --short Show working tree status" "$(field claude-run 2)"
check "other prompt" "other" "$(field other 1)"
check "other text" "Allow access to this URL? https://example.com/notes > Yes, allow access No, deny access" "$(field other 2)"

# The rules hold what they forbid, and nothing else.
rule() { gate_forbidden "$CREW_HOME/share/forbid" "$1" >/dev/null && echo hold || echo approve; }
while IFS='|' read -r want command; do
    check "rule: $command" "$want" "$(rule "$command")"
done <<'EOF'
approve|cargo test --test editors
approve|cargo fmt --all --check
approve|cargo fmt -p tess --all -- --check
approve|git commit -s -F /tmp/message -- compiler/src/a.rs
approve|git add compiler/src/a.rs compiler/tests/b.rs
approve|git push origin main && rm -r /p/.crew/lock
approve|git push origin --delete tmp-codex
approve|git -C /p checkout -b topic
approve|gh run watch 123
approve|git -C /p -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin main
approve|ps -axo pid,command | rg cargo
hold|cargo fmt --all
hold|cargo fmt --all --check && cargo fmt --all
hold|git add -A
hold|git add .
hold|git commit -am wip
hold|git commit -s --all
hold|git stash push -m wip
hold|git -C /p reset --hard
hold|git checkout -- compiler/src/a.rs
hold|git restore compiler/src/a.rs
hold|git pull --rebase
hold|git push --force origin main
hold|git push origin --delete main
hold|git push origin :main
hold|git -c 'credential.helper=!gh auth git-credential' push -f origin main
hold|kill -TERM -- -42985
hold|cargo test; pkill -f nvim
hold|sudo rm /etc/hosts
hold|rm -rf target
hold|rm -r /p/.crew/lock/../messages && rm -rf src
EOF
check "rule named" "git +reset" "$(gate_forbidden "$CREW_HOME/share/forbid" "git reset --hard")"

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

i=1
while [ "$i" -le 8 ]; do
    echo "body $i" | crew_send codex all "Plan: slice $i" >/dev/null &
    i=$((i + 1))
done
wait
check "eight numbers" "1 2 3 4 5 6 7 8" "$(ls "$dir/seq" | sort -n | tr '\n' ' ' | sed 's/ $//')"
check "eight messages" "8" "$(ls "$dir/messages" | wc -l | tr -d ' ')"

echo "to claude" | crew_send agy claude "Question: which allocator?" >/dev/null
echo "to agy" | crew_send claude agy "Answer: TLSF" >/dev/null
check "unread to claude" "9" "$(crew_unread claude | grep -c '^# ')"
check "unread marks read" "No new messages for claude." "$(crew_unread claude)"
check "unread skips own" "0" "$(crew_unread codex | grep -c '^# ')"
check "message file" "0010-claude-to-agy-answer-tlsf.md" "$(ls "$dir/messages" | grep '^0010')"
check "bad name" "2" "$(echo x | crew_send Codex all "x" >/dev/null 2>&1; echo $?)"

check "lock taken" "lock taken by codex" "$(crew_lock codex)"
check "lock busy" "1" "$(crew_lock claude 2>/dev/null; echo $?)"
check "unlock by another" "1" "$(crew_unlock claude 2>/dev/null; echo $?)"
check "unlock" "lock released" "$(crew_unlock codex)"

printf '%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
