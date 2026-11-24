#!/bin/sh
# Wakes the coordinator (by exiting) when the crew looks stuck:
# - a member sits on a permission prompt for two checks in a row, or its pane
#   is gone or its agent exited for two checks in a row;
# - no new message for QUIET minutes, no member is working, and some member's
#   status has a "Blocked on:" other than nothing or the owner (a hand-over
#   loop or a lost answer).
# Usage: stuck.sh <crew dir> [quiet minutes, default 5]. Run it in the background.
dir=$1
quiet=${2:-5}
prompted="" gonewas=""
while :; do
    sleep 60
    board=$(crew board 2>/dev/null | grep '^== ' | grep -v '^== coordinator' | grep -v '^== keeper')

    # A member's background shell can show ", exited" for one check; only two checks in a row count.
    gonenow=$(printf '%s\n' "$board" | grep -E ' gone[,)]|, exited' | awk '{print $2}' | tr '\n' ' ')
    for m in $gonenow; do
        case " $gonewas " in *" $m "*) echo "gone: $m"; exit 0 ;; esac
    done
    gonewas=$gonenow

    now_prompt=$(printf '%s\n' "$board" | grep -E ', (dialog|typed)' | awk '{print $2}' | tr '\n' ' ')
    for m in $now_prompt; do
        case " $prompted " in *" $m "*) echo "prompt: $m"; exit 0 ;; esac
    done
    prompted=$now_prompt

    printf '%s\n' "$board" | grep -q ', working' && continue
    newest=$(ls -t "$dir/messages" 2>/dev/null | head -1)
    [ -n "$newest" ] || continue
    mtime=$(stat -f %m "$dir/messages/$newest" 2>/dev/null || stat -c %Y "$dir/messages/$newest")
    age=$(( ($(date +%s) - mtime) / 60 ))
    [ "$age" -ge "$quiet" ] || continue

    blocked=""
    for m in $(printf '%s\n' "$board" | awk '{print $2}'); do
        b=$(sed -n 's/^Blocked on: *//p' "$dir/status/$m.md" 2>/dev/null | head -1)
        case "$b" in "" | nothing* | Nothing* | owner* | Owner*) ;; *) blocked="$blocked $m" ;; esac
    done
    [ -n "$blocked" ] && { echo "stuck:$blocked (nobody working, no message for ${age}m)"; exit 0; }
done
