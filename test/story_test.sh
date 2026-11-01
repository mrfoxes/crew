#!/bin/sh
# crew story: the session as one document, from a fixture crew and from
# its archive.
#
#   sh test/run.sh story

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
printf '# Plan: two members\n\nclaude lands, codex reviews.\n' >"$dir/README.md"
printf 'tab main\nmember claude reviewer=codex -- claude\nmember codex reviewer=claude -- codex\n' >"$dir/Crewfile"
mkdir -p "$dir/kind" "$dir/tabs" "$dir/clones"
echo claude >"$dir/kind/claude"
echo codex >"$dir/kind/codex"
printf 'claude\ncodex\n' >"$dir/tabs/main"
echo "$tmp/repo-claude" >"$dir/clones/claude"
echo go | crew_send codex all "Plan: start" >/dev/null
echo stat | crew_send claude codex "Pushed: abc1234 Fix the gate" >/dev/null
echo fine | crew_send codex claude "Review: abc1234 clean" >/dev/null
echo stat | crew_send codex claude "Pushed: def5678 Add a test" >/dev/null
printf 'Agent: claude\nFiles: lib/gate.sh\n' | crew_write status claude >/dev/null
echo "landed abc1234" | crew_write report claude >/dev/null
echo "reviewed abc1234" | crew_write report codex >/dev/null
echo "diff" >"$dir/reports/codex.patch"

story=$(crew_story)
check "story exits 0" "0" "$(crew_story >/dev/null; echo $?)"
check "the title names the project" "# The crew of repo" "$(printf '%s\n' "$story" | sed -n 1p)"
check "the range counts the messages" "1" "$(printf '%s\n' "$story" | grep -c '^From 20[0-9-]* [0-9:]* to 20[0-9-]* [0-9:]*: 4 messages\.$')"
check "the sections, in order" "The plan The Crewfile The members The stream The commits The reports" "$(printf '%s\n' "$story" | sed -n 's/^## //p' | tr '\n' ' ' | sed 's/ $//')"
check "the plan is whole" "1" "$(printf '%s\n' "$story" | grep -c '^claude lands, codex reviews\.$')"
check "the Crewfile is whole" "1" "$(printf '%s\n' "$story" | grep -c '^member codex reviewer=claude -- codex$')"
check "a member with its kind, tab, clone, and reviewer" "1" "$(printf '%s\n' "$story" | grep -c "^- claude (claude, tab main, clone $tmp/repo-claude, reviewed by codex)")"
check "a member with no clone" "1" "$(printf '%s\n' "$story" | grep -c '^- codex (codex, tab main, reviewed by claude)')"
check "the messages, whole and in order" "0001 0002 0003 0004" "$(printf '%s\n' "$story" | sed -n 's/^# \([0-9]*\)\. .*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
check "a commit with its review" "1" "$(printf '%s\n' "$story" | grep -c '^- abc1234 Fix the gate, landed by claude (0002), Review: abc1234 clean (0003, codex)$')"
check "a commit waiting for its review" "1" "$(printf '%s\n' "$story" | grep -c "^- def5678 Add a test, landed by codex (0004), waiting for claude's review$")"
check "the reports, each under its name" "claude codex" "$(printf '%s\n' "$story" | sed -n 's/^### //p' | tr '\n' ' ' | sed 's/ $//')"
check "a patch left" "1" "$(printf '%s\n' "$story" | grep -c '^A patch left by codex: reports/codex.patch$')"

# From the archive, once the stream is put aside. The archive is named after
# the second, here always the same one, so the next archive must keep apart.
date() { case "$1" in '+%Y-%m-%d-%H%M%S') echo 2026-11-01-000000 ;; *) command date "$@" ;; esac; }
when=$(basename "$(crew_archive)")
check "the live crew has no message now" "No message yet." "$(crew_story | sed -n 3p)"
check "the archive tells the same story" "0001 0002 0003 0004" "$(crew_story "$when" | sed -n 's/^# \([0-9]*\)\. .*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
check "an archive by its path" "4" "$(crew_story "$dir/archive/$when" | grep -c '^# 000[0-9]\. ')"
check "an archive that is not there" "1" "$(crew_story nosuch >/dev/null 2>&1; echo $?)"
check "story takes one argument at most" "2" "$(crew_story a b >/dev/null 2>&1; echo $?)"

# crew down --archive saves the story it archives. With no Crewfile and no
# pane, down has nobody to wait for and archives at once.
rm "$dir/Crewfile"
echo go | crew_send codex all "Plan: again" >/dev/null
check "down --archive saves the story" "1" "$(crew_down --archive >/dev/null; ls "$dir"/archive/*/story.md | wc -l | tr -d ' ')"
check "and the story is the archived session" "1" "$(cat "$dir"/archive/*/story.md | grep -c '^# 0001\. codex to all: Plan: again$')"
check "two archives in one second keep apart" "2" "$(ls "$dir/archive" | wc -l | tr -d ' ')"
check "and the second is named after the first" "1" "$([ -d "$dir/archive/2026-11-01-000000-2" ] && echo 1)"

finish
