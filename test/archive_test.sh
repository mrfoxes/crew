#!/bin/sh
# crew archive, crew reset, and crew restore: a session or a whole crew put
# aside under archive/, and brought back, never with its panes.
#
#   sh test/run.sh archive

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
# An archive is named after the second, here always the same one.
date() { case "$1" in '+%Y-%m-%d-%H%M%S') echo 2026-11-05-030000 ;; *) command date "$@" ;; esac; }
when=2026-11-05-030000

# A crew at work: its plan, its Crewfile, its members, its session, and
# what belongs to the project and to the machine.
printf '# Plan: reset\n' >"$dir/README.md"
printf 'tab main\nmember qa reviewer=dev1 -- claude\nmember dev1 reviewer=qa -- claude\n' >"$dir/Crewfile"
mkdir -p "$dir/layouts" "$dir/up" "$dir/work/qa" "$dir/exports/dev1" "$dir/sessions" "$dir/nopane" "$dir/clones" "$dir/tabs"
for m in qa dev1; do
    echo claude >"$dir/kind/$m"
    echo "session-$m" >"$dir/sessions/$m"
done
echo codex >"$dir/kind/rev"
echo thread-rev >"$dir/threads/rev"
echo "tmux:%8" >"$dir/panes/dev1"
: >"$dir/nopane/coord"
printf 'qa\ndev1\ntmux:%%6\n' >"$dir/tabs/main"
printf 'iterm:CC85\n' >"$dir/tabs/side"
echo grid >"$dir/layouts/main"
echo "tmux:%9" >"$dir/up/watch"
: >"$dir/muted/qa"
echo notes >"$dir/work/qa/notes.md"
echo cache >"$dir/exports/dev1/cache"
mkdir "$tmp/repo-dev1"
echo "$tmp/repo-dev1" >"$dir/clones/dev1"
echo "$tmp/repo-qa" >"$dir/clones/qa"
for f in rates forbid kinds; do echo "$f" >"$dir/$f"; done
: >"$dir/tmp/wake.1.qa"
echo 2 >"$dir/relay.last"
echo go | crew_send dev1 all "Plan: start" >/dev/null 2>&1
echo hi | crew_send dev1 qa "Pushed: abc1234 Add reset" >/dev/null 2>&1
printf 'Agent: dev1\nNext: reset\n' | crew_write status dev1 >/dev/null
echo landed | crew_write report dev1 >/dev/null
crew_unread qa >/dev/null

# What holds a reset or a restore back.
check "restore with no archive" "crew: no archive to restore" "$(crew_restore 2>&1)"
echo 1 >"$dir/relay.pid"
check "reset waits for the relay" "crew: a relay runs; stop it before the reset" "$(crew_reset 2>&1)"
check "restore waits for the relay" "crew: a relay runs; stop it before the restore" "$(crew_restore x 2>&1)"
rm -f "$dir/relay.pid"
mkdir "$dir/lock"
echo qa >"$dir/lock/owner"
check "reset waits for a landing" "crew: the lock is held by qa; let the landing end first" "$(crew_reset 2>&1)"
rm -rf "$dir/lock"
check "reset takes no word" "2" "$(crew_reset --all >/dev/null 2>&1; echo $?)"
check "restore takes one archive" "2" "$(crew_restore a b >/dev/null 2>&1; echo $?)"
check "nothing was put aside" "" "$(ls "$dir/archive" 2>/dev/null)"

# The reset: the whole crew aside, the directory as crew init makes it.
to=$(crew_reset 2>"$tmp/reset.err")
check "reset" "$dir/archive/$when" "$to"
check "reset names a pane that still runs its agent" "crew: dev1's pane tmux:%8 still runs its agent; it is no member now" "$(cat "$tmp/reset.err")"
missing=""
for e in README.md Crewfile messages seq cursors status reports work tabs layouts muted kind panes nopane threads sessions up; do
    [ -e "$to/$e" ] || missing="$missing $e"
done
check "reset puts the session and the crew aside" "" "$missing"
check "the plan aside is the crew's" "# Plan: reset" "$(cat "$to/README.md")"
check "the work aside" "notes" "$(cat "$to/work/qa/notes.md")"
check "reset leaves crew init's plan" "0" "$(cmp -s "$dir/README.md" "$CREW_HOME/share/plan.md"; echo $?)"
check "reset leaves crew init's directories, empty" "README.md archive clones cursors exports forbid kind kinds messages muted panes project rates reports seq status threads tmp" "$(ls "$dir" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
check "nothing in them" "" "$(find "$dir/messages" "$dir/seq" "$dir/cursors" "$dir/status" "$dir/reports" "$dir/panes" "$dir/threads" "$dir/muted" "$dir/kind" -type f)"
check "reset keeps the project's files" "rates forbid kinds" "$(cat "$dir/rates" "$dir/forbid" "$dir/kinds" | tr '\n' ' ' | sed 's/ $//')"
check "reset keeps the exports" "cache" "$(cat "$dir/exports/dev1/cache")"
check "reset keeps a clone on disk" "$tmp/repo-dev1" "$(cat "$dir/clones/dev1")"
check "reset takes the entry of a clone gone" "$tmp/repo-qa none" "$(cat "$to/clones/qa") $(cat "$dir/clones/qa" 2>/dev/null || echo none)"
check "reset forgets the wake claims" "" "$(ls "$dir"/tmp/wake.* "$dir/relay.last" 2>/dev/null)"
check "nothing to reset" "crew: nothing to reset" "$(crew_reset 2>&1)"

# The story of a reset reads the plan, the Crewfile, and the members aside.
story=$(crew_story "$when")
check "the story of a reset has its plan" "1" "$(printf '%s\n' "$story" | grep -c '^# Plan: reset$')"
check "and its Crewfile" "1" "$(printf '%s\n' "$story" | grep -c '^member qa reviewer=dev1 -- claude$')"
check "a member with its kind, tab, and clone aside" "1" "$(printf '%s\n' "$story" | grep -c "^- qa (claude, tab main, clone $tmp/repo-qa, reviewed by dev1)")"
check "a member whose clone is still on disk" "1" "$(printf '%s\n' "$story" | grep -c "^- dev1 (claude, tab main, clone $tmp/repo-dev1, reviewed by qa)")"
check "the live crew's story has crew init's plan" "0" "$(crew_story | grep -c '^# Plan: reset$')"

# The restore refuses a crew with a session, a plan, or a Crewfile of its own.
echo x | crew_send qa all "Plan: new" >/dev/null 2>&1
check "restore refuses a stream of its own" "crew: the crew has a session of its own (messages/); 'crew archive' or 'crew reset' puts it aside first" "$(crew_restore 2>&1)"
mv "$dir/messages" "$tmp/messages.new"
mv "$dir/seq" "$tmp/seq.new"
mkdir "$dir/messages" "$dir/seq"
echo "# Plan: new" >"$dir/README.md"
check "restore refuses a plan of its own" "crew: the crew has its own README.md; 'crew reset' puts it aside first" "$(crew_restore 2>&1)"
cp "$CREW_HOME/share/plan.md" "$dir/README.md"
echo "member x -- claude" >"$dir/Crewfile"
check "restore refuses a Crewfile of its own" "1" "$(crew_restore >/dev/null 2>&1; echo $?)"
rm -f "$dir/Crewfile"
echo "$tmp/repo-qa2" >"$dir/clones/qa"
check "restore refuses a clone of the same name" "crew: the crew has a clone for qa already" "$(crew_restore 2>&1)"
rm -f "$dir/clones/qa"
check "nothing was put back" "" "$(find "$dir/messages" "$dir/kind" -type f)"
check "restore of an archive that is not there" "crew: no archive at $dir/archive/nosuch" "$(crew_restore nosuch 2>&1)"

# The restore: the session and the crew back, never a pane.
out=$(crew_restore)
check "restore says what it did" "restored $dir/archive/$when|kept in $dir/archive/$when: panes up|run 'crew up' to bring the members back" "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')"
check "the stream is back" "2" "$(ls "$dir/seq" | wc -l | tr -d ' ')"
check "the plan is back" "# Plan: reset" "$(cat "$dir/README.md")"
check "the Crewfile is back" "3" "$(wc -l <"$dir/Crewfile" | tr -d ' ')"
check "the members are back" "dev1 qa rev" "$(ls "$dir/kind" | tr '\n' ' ' | sed 's/ $//')"
check "their sessions and threads" "session-dev1 thread-rev" "$(cat "$dir/sessions/dev1" "$dir/threads/rev" | tr '\n' ' ' | sed 's/ $//')"
check "the status, the report, the work, the cursor" "dev1.md dev1.md notes.md qa" "$(for d in status reports work/qa cursors; do ls "$dir/$d"; done | tr '\n' ' ' | sed 's/ $//')"
check "the mutes, the layouts, the no-pane members" "qa main coord" "$(for d in muted layouts nopane; do ls "$dir/$d"; done | tr '\n' ' ' | sed 's/ $//')"
check "a restored crew has no pane" "" "$(find "$dir/panes" "$dir/up" -type f 2>/dev/null)"
check "its tabs hold names, no pane" "qa dev1" "$(cat "$dir"/tabs/* | tr '\n' ' ' | sed 's/ $//')"
check "a tab of panes alone is gone" "main" "$(ls "$dir/tabs")"
check "the gone clone's entry is back" "$tmp/repo-qa" "$(cat "$dir/clones/qa")"
check "the panes stay aside" "tmux:%8 tmux:%9" "$(cat "$to/panes/dev1" "$to/up/watch" | tr '\n' ' ' | sed 's/ $//')"
check "a second restore finds nothing" "crew: nothing to restore in $to" "$(crew_restore 2>&1)"
rm -rf "$to"

# crew archive carries the work with the session; a restore of it keeps the
# live crew's plan and members, and needs no crew up.
mkdir -p "$dir/work/dev1"
echo log >"$dir/work/dev1/check.log"
rm -rf "$dir/work/qa"
rm -f "$dir"/messages/* "$dir"/seq/* "$dir"/status/* "$dir"/reports/*
check "work alone is a session to archive" "$dir/archive/$when" "$(crew_archive)"
check "archive carries the work" "log" "$(cat "$dir/archive/$when/work/dev1/check.log")"
check "archive leaves no work behind" "" "$(ls "$dir/work" 2>/dev/null)"
rm -rf "$dir/archive/$when"
echo x | crew_send dev1 qa "Plan: kept" >/dev/null 2>&1
to=$(crew_archive)
check "the plan stays with an archive" "# Plan: reset" "$(cat "$dir/README.md")"
out=$(crew_restore "$to")
check "restore of an archive by its path" "restored $to" "$out"
check "its stream is back" "1" "$(ls "$dir/seq" | wc -l | tr -d ' ')"
check "an emptied archive is gone" "" "$(ls "$dir/archive")"
check "the live crew's members stayed" "dev1 qa rev" "$(ls "$dir/kind" | tr '\n' ' ' | sed 's/ $//')"

# An archive crew archive made, restored by its name, leaves what it does
# not know in the archive.
to=$(crew_archive)
echo "# story" >"$to/story.md"
out=$(crew_restore "$when")
check "restore of an archive by its name" "restored $to|kept in $to: story.md" "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')"
rm -rf "$to"

# A crew with no pane leaves nothing aside once restored: its empty panes/
# goes with the archive.
rm -f "$dir"/panes/* "$dir"/messages/* "$dir"/seq/* "$dir"/status/* "$dir"/reports/* "$dir"/cursors/*
rm -rf "$dir/work"
to=$(crew_reset 2>/dev/null)
check "a reset of a crew with no pane" "1" "$([ -d "$to/panes" ] && echo 1)"
out=$(crew_restore)
check "its restore keeps nothing aside" "restored $to|run 'crew up' to bring the members back" "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')"
check "the archive is gone" "" "$(ls "$dir/archive")"

finish
