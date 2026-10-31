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
# The version from the tag, in a checkout of its own: with no tag the commit,
# at a tag the tag, past it what git describe writes.
mkdir -p "$tmp/home" && cp -R "$CREW_HOME/bin" "$CREW_HOME/lib" "$tmp/home"
git init -q "$tmp/home" && git -C "$tmp/home" add bin lib
git -C "$tmp/home" -c user.name=t -c user.email=t@example.com commit -q -m first
day=$(git -C "$tmp/home" log -1 --format=%cs)
hash=$(git -C "$tmp/home" log -1 --format=%h)
check "version with no tag" "crew $hash ($day)" "$(sh "$tmp/home/bin/crew" version)"
git -C "$tmp/home" tag v1.0.0
check "version at a tag" "crew v1.0.0 ($day)" "$(sh "$tmp/home/bin/crew" version)"
git -C "$tmp/home" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m second
hash=$(git -C "$tmp/home" log -1 --format=%h)
check "version past a tag" "crew v1.0.0-1-g$hash ($day)" "$(sh "$tmp/home/bin/crew" version)"
check "version" "0" "$(crew version >/dev/null; echo $?)"
check "an unknown command" "2" "$(crew nosuch >/dev/null 2>&1; echo $?)"

# Counts and intervals are decimal: a leading zero is dropped (08 is 8, not an
# octal error), 0 is a count but not an interval, and a
# negative, a word, and a number too long for arithmetic are refused.
for n in 0 00 08 010; do
    check "log $n" "0" "$(crew log "$n" >/dev/null 2>&1; echo $?)"
    check "board $n" "0" "$(crew board "$n" >/dev/null 2>&1; echo $?)"
    check "down $n" "0" "$(crew down "$n" >/dev/null 2>&1; echo $?)"
done
check "log 010 is ten messages" "$(crew log 10)" "$(crew log 010)"
check "log 00 is none" "" "$(crew log 00)"
echo body | crew send codex claude "Plan: counts" >/dev/null 2>&1
last=$(ls "$dir/seq" | sort -n | tail -n 1)
check "show 0$last is show $last" "$(crew show "$last")" "$(crew show "0$last")"
check "show 000 is no message" "1" "$(crew show 000 >/dev/null 2>&1; echo $?)"
for n in -1 -08 word 1.5 12345678901; do
    check "log '$n' is refused" "2" "$(crew log "$n" >/dev/null 2>&1; echo $?)"
    check "show '$n' is refused" "2" "$(crew show "$n" >/dev/null 2>&1; echo $?)"
    check "board '$n' is refused" "2" "$(crew board "$n" >/dev/null 2>&1; echo $?)"
    check "board --live '$n' is refused" "2" "$(crew board --live "$n" >/dev/null 2>&1; echo $?)"
    check "down '$n' is refused" "2" "$(crew down "$n" >/dev/null 2>&1; echo $?)"
    check "peek '$n' is refused" "2" "$(crew peek tess "$n" >/dev/null 2>&1; echo $?)"
    check "invite '$n' is refused" "2" "$(crew invite tess "$n" >/dev/null 2>&1; echo $?)"
done
for n in 0 00 000; do
    check "board --live $n is refused, not a busy loop" "2" "$(crew board --live "$n" >/dev/null 2>&1; echo $?)"
    check "invite $n is refused, not a busy loop" "2" "$(crew invite tess "$n" >/dev/null 2>&1; echo $?)"
done
check "peek 08 gets as far as the pane" "1" "$(crew peek tess 08 >/dev/null 2>&1; echo $?)"
check "invite 08 gets as far as the pane" "1" "$(crew invite tess 08 >/dev/null 2>&1; echo $?)"
check "no owner machine path in README.md" "0" \
    "$(grep -cE 'Documents/repos|/Users/' "$CREW_HOME/README.md" || :)"
help_cmds=$(crew --help | awk '/^  [a-z][a-z-]*([ |]|$)/ { print $1 }')
qs_cmds=$(
    awk '/^## Quickstart$/ { on=1; next } /^## / { on=0 } on && /^crew [a-z]/ { print $2 }' "$CREW_HOME/README.md" |
        sort -u
)
check "Quickstart shows crew commands" "1" "$([ -n "$qs_cmds" ] && echo 1 || echo 0)"
for qc in $qs_cmds; do
    check "Quickstart command 'crew $qc' in --help" "1" \
        "$(printf '%s\n' "$help_cmds" | grep -qx "$qc" && echo 1 || echo 0)"
done

finish
