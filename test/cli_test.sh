#!/bin/sh
# The commands as the owner runs them: bin/crew, under its set -eu, so that
# a function that fails where it should say nothing stops the command here
# as it would stop it for the owner. Only commands that touch no terminal.
#
#   sh test/run.sh cli

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

crew() { sh "$CREW_HOME/bin/crew" "$@"; }
git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew init)
check "init" "$(pwd -P)/.crew" "$dir"
check "dir" "$dir" "$(crew dir)"
check "send" "0" "$(echo body | crew send codex claude "Plan: one" >/dev/null; echo $?)"
check "unread" "1" "$(crew unread claude | grep -c '^# 0001\. codex to claude: Plan: one$')"
check "log" "0" "$(crew log 1 >/dev/null; echo $?)"
check "show" "0" "$(crew show 1 >/dev/null; echo $?)"
# A status of a member crew never placed: no pane, no kind, no tab.
check "status" "0" "$(printf 'Agent: tess\nFiles: a.txt\n' | crew status tess >/dev/null; echo $?)"
check "board of a member with no kind" "1" "$(crew board 1 | grep -c '^== tess (no pane, 0 min ago)$')"
mkdir -p "$dir/kind" && echo codex >"$dir/kind/cx"
check "cost of a member with no log" "0" "$(crew cost >/dev/null; echo $?)"
check "board with a member's cost" "0" "$(crew board >/dev/null; echo $?)"
rm "$dir/kind/cx"
check "report" "0" "$(echo finished | crew report tess >/dev/null; echo $?)"
check "lock" "lock taken by tess" "$(crew lock tess)"
check "unlock" "lock released" "$(crew unlock tess)"
check "land with no reviewer stops" "1" "$(echo msg >"$tmp/msg"; crew land tess -F "$tmp/msg" -- a.txt >/dev/null 2>&1; echo $?)"
check "land says how to give one" "1" "$(crew land tess -F "$tmp/msg" -- a.txt 2>&1 | grep -c 'tess has no reviewer')"
check "land with no paths" "2" "$(crew land tess -F "$tmp/msg" >/dev/null 2>&1; echo $?)"
check "mute" "0" "$(crew mute tess >/dev/null; echo $?)"
check "unmute" "0" "$(crew unmute tess >/dev/null; echo $?)"
check "layout with no tab laid out" "0" "$(crew layout >/dev/null; echo $?)"
# A member's clone, recorded as spawn --clone does: on the board whether it
# is there, behind, or gone, and removed by leave when nothing is left.
git init -q --bare -b main "$tmp/origin.git"
git -C "$tmp/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first
git -C "$tmp/repo" branch -M main
git -C "$tmp/repo" remote add origin "$tmp/origin.git"
git -C "$tmp/repo" push -q origin main
git clone -q "$tmp/origin.git" "$tmp/repo-tess" 2>/dev/null
mkdir -p "$dir/clones"
echo "$tmp/repo-tess" >"$dir/clones/tess"
check "board with a clone" "1" "$(crew board | grep -c "^clone: $tmp/repo-tess, 0 behind origin/main")"
echo "$tmp/repo-gone" >"$dir/clones/tess"
check "board with a clone that is gone" "1" "$(crew board | grep -c "^clone: $tmp/repo-gone (gone)$")"
echo "$tmp/repo-tess" >"$dir/clones/tess"
check "leave keeps the clone" "1" "$(crew leave tess >/dev/null; [ -d "$tmp/repo-tess" ] && echo 1)"
check "leave --clone removes a clone with nothing left" "0" "$(crew leave tess --clone >/dev/null; echo $?)"
check "and the clone is gone" "1" "$([ -d "$tmp/repo-tess" ] || echo 1)"
check "leave" "0" "$(crew leave tess >/dev/null; echo $?)"
check "down with nothing to wait for" "nobody to wait for: no member has a pane or a line in the Crewfile
nothing is left" "$(crew down)"
check "archive" "0" "$(crew archive >/dev/null; echo $?)"
check "version" "0" "$(crew version >/dev/null; echo $?)"
check "an unknown command" "2" "$(crew nosuch >/dev/null 2>&1; echo $?)"

finish
