#!/bin/sh
# A new crew's first look: crew init writes a plan to start from, never over
# one that is there, and crew board says what to do while the crew is empty.
#
#   sh test/run.sh plan

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
cd "$tmp/repo" || exit 1
dir=$(crew_init)

check "init writes a plan" "$(cat "$CREW_HOME/share/plan.md")" "$(cat "$dir/README.md")"
check "the plan has a goal, lanes, reviewers, and an end" "4" "$(grep -c '^\(Goal\|Lanes\|Reviewers\|End\):' "$dir/README.md")"
echo "my own plan" >"$dir/README.md"
crew_init >/dev/null
check "init keeps a plan that is there" "my own plan" "$(cat "$dir/README.md")"

empty="no members yet: run 'crew up <preset>' or 'crew spawn <name> --join <command>'"
check "an empty board says what to do" "$empty" "$(crew_board | sed -n 1p)"
printf 'Agent: ada\nIssue: #1\n' >"$dir/status/ada.md"
check "a board with a member does not" "0" "$(crew_board | grep -c '^no members yet')"
rm "$dir/status/ada.md"
echo "tmux:%1" >"$dir/panes/ada"
check "a member with a pane is a member" "0" "$(crew_board | grep -c '^no members yet')"

finish
