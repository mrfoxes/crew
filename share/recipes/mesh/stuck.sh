#!/bin/sh
# Wakes its caller (by exiting) when its scope of the mesh looks stuck:
# - a member shows a dialog (a permission prompt) or typed text on its input
#   line two checks in a row, or its pane is gone, or its agent exited;
# - no message from or to the scope for QUIET minutes, no member of the scope
#   works, and some member's status has a "Blocked on:" other than nothing.
# The scope is words matched on names as the stream filter does: api is
# api-*, coord is every <area>-coord, svc is the services. The caller is left out.
# Usage: stuck.sh <crew dir> <you> <quiet minutes> <word>... Run it in the background.
#   hq-lead:      stuck.sh "$(crew dir)" hq-lead 5 coord svc
#   <area>-coord: stuck.sh "$(crew dir)" api-coord 5 api
set -f
dir=$1 me=$2 quiet=$3
shift 3
scope=$*
held=""
while :; do
    sleep 60
    board=$(crew board 2>/dev/null | awk -v scope="$scope" -v me="$me" '
        /^== / && $2 != me {
            k = split(scope, w, " ")
            for (i = 1; i <= k; i++) if (index("-" $2 "-", "-" w[i] "-")) { print; next }
        }')
    [ -n "$board" ] || continue
    names=$(printf '%s\n' "$board" | awk '{ print $2 }' | tr '\n' ' ')

    gone=$(printf '%s\n' "$board" | grep -E ' gone[,)]|, exited' | awk '{ print $2 }' | tr '\n' ' ')
    [ -n "$gone" ] && { echo "gone: $gone"; exit 0; }

    now=$(printf '%s\n' "$board" | grep -E ', (dialog|typed)' | awk '{ print $2 }' | tr '\n' ' ')
    for m in $now; do
        case " $held " in *" $m "*) echo "dialog or typed text: $m"; exit 0 ;; esac
    done
    held=$now

    printf '%s\n' "$board" | grep -q ', working' && continue
    newest=$(ls -t "$dir/messages" 2>/dev/null | awk -v names="$names" '
        BEGIN { k = split(names, n, " ") }
        { for (i = 1; i <= k; i++) if (index($0, "-" n[i] "-to-") || index($0, "-to-" n[i] "-")) { print; exit } }')
    [ -n "$newest" ] || continue
    mtime=$(stat -f %m "$dir/messages/$newest" 2>/dev/null || stat -c %Y "$dir/messages/$newest")
    age=$(( ($(date +%s) - mtime) / 60 ))
    [ "$age" -ge "$quiet" ] || continue

    blocked=""
    for m in $names; do
        b=$(sed -n 's/^Blocked on: *//p' "$dir/status/$m.md" 2>/dev/null | head -1)
        case "$b" in "" | nothing* | Nothing*) ;; *) blocked="$blocked $m" ;; esac
    done
    [ -n "$blocked" ] && { echo "stuck:$blocked (nobody working, no message for ${age}m)"; exit 0; }
done
