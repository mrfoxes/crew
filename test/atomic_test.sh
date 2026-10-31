#!/bin/sh
# The atomic writes' tests: a status, a report, and a cursor are written
# whole or not at all, so a reader never sees one empty or cut.
#
#   sh test/run.sh atomic

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)

body='Agent: ada
Start: 21:45  End: 22:45
Issue: a long enough line to take more than one write to land on disk
Files: lib/store.sh, test/atomic_test.sh
Pushed: nothing
Next: land
Blocked on: nothing'
printf '%s\n' "$body" | crew_write status ada >/dev/null
printf '%s\n' "$body" | crew_write report ada >/dev/null

# A reader that never sees the file empty or cut, while it is written again
# and again.
bad=0
n=0
(
    i=0
    while [ "$i" -lt 300 ]; do
        printf '%s\n' "$body" | crew_write status ada >/dev/null
        printf '%s\n' "$body" | crew_write report ada >/dev/null
        i=$((i + 1))
    done
    : >"$tmp/writer.done"
) &
while [ ! -f "$tmp/writer.done" ] || [ "$n" -lt 300 ]; do
    for f in "$dir/status/ada.md" "$dir/reports/ada.md"; do
        [ "$(wc -l <"$f")" -eq 7 ] || bad=$((bad + 1))
    done
    n=$((n + 1))
done
wait
check "a status and a report are never read empty or cut" "0" "$bad"

# A cursor is moved whole, and no temporary file is left behind.
# (crew_send sets tmp, the harness's own: it runs in a subshell.)
(printf 'x\n' | crew_send ada all "Plan: one" >/dev/null)
crew_unread bob >/dev/null
check "the cursor holds the last number" "1" "$(cat "$dir/cursors/bob")"
check "no temporary file is left" "0" "$(find "$dir/tmp" -name 'status.*' -o -name 'report.*' -o -name 'cursor.*' | wc -l | tr -d ' ')"

finish
