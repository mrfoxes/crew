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
check "mute" "0" "$(crew mute tess >/dev/null; echo $?)"
check "unmute" "0" "$(crew unmute tess >/dev/null; echo $?)"
check "layout with no tab laid out" "0" "$(crew layout >/dev/null; echo $?)"
check "leave" "0" "$(crew leave tess >/dev/null; echo $?)"
check "archive" "0" "$(crew archive >/dev/null; echo $?)"
check "version" "0" "$(crew version >/dev/null; echo $?)"
check "an unknown command" "2" "$(crew nosuch >/dev/null 2>&1; echo $?)"

finish
