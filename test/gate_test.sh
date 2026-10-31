#!/bin/sh
# The gate's tests: the prompts it reads from screens captured from the real
# agents, the rules it holds commands by, and its looks at a pane.
#
#   sh test/run.sh gate

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

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

# One look of the gate at a pane, with the screen read from a fixture and
# the keys it would press printed instead.
gate_rules=$CREW_HOME/share/forbid
gate_state=$tmp/gate
mkdir -p "$gate_state/held" "$gate_state/answered"
gate_dry=""
term_read() { fixture_read; }
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
# The key that answers yes is the kind's (share/kinds): the owner's kinds
# can change it, and a kind with none has its prompts held.
mkdir -p "$XDG_CONFIG_HOME/crew"
echo 'codex codex CODEX_THREAD_ID › enter #000000' >"$XDG_CONFIG_HOME/crew/kinds"
rm -f "$gate_state/answered/codex"
show codex-run codex-run
check "gate presses the kind's key" "pressed enter
12:00:00 approved codex: cargo test --test editors" "$(gate_look codex tmux:%1)"
echo 'codex codex CODEX_THREAD_ID › - #000000' >"$XDG_CONFIG_HOME/crew/kinds"
rm -f "$gate_state/answered/codex" "$gate_state/held/codex"
show codex-run
check "gate holds a kind with no key" "12:00:00 HOLD codex (no key approves a codex prompt): cargo test --test editors" "$(gate_look codex tmux:%1)"
rm -r "$XDG_CONFIG_HOME/crew"

finish
