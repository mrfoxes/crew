#!/bin/sh
# Wakes the keeper (by exiting) when any member of the mesh sits at its
# prompt (idle or shell) with a large context and no compact running.
# Prints "<name> <percent>%" for each, hq-lead first, then the coordinators,
# then the other members. svc-keeper is left out.
# The percent is read from the agent's status line ("NN% NNNk/1M", which a
# narrow pane cuts to "NN% NN…").
# Usage: ctx.sh <crew dir> [percent, default 40]. Run it in the background.
dir=$1
max=${2:-40}
while :; do
    sleep 120
    over=""
    for f in "$dir/panes/hq-lead" "$dir"/panes/*-coord "$dir"/panes/*; do
        [ -f "$f" ] || continue
        m=${f##*/}
        case "$m" in svc-keeper) continue ;; esac
        case " $over " in *" $m:"*) continue ;; esac
        [ -e "$dir/tmp/hold/$m" ] && continue
        pane=$(sed 's/^tmux://' "$f")
        pct=$(tmux capture-pane -p -t "$pane" 2>/dev/null | grep -oE '[0-9]+% [0-9]' | tail -1 | cut -d% -f1)
        [ -n "$pct" ] && [ "$pct" -ge "$max" ] && over="$over $m:$pct"
    done
    [ -n "$over" ] || continue
    board=$(crew board 2>/dev/null | grep '^== ')
    out=""
    for e in $over; do
        m=${e%%:*}
        printf '%s\n' "$board" | grep -qE "^== $m \(.*, (idle|shell)" && out="$out$m ${e#*:}%
"
    done
    [ -n "$out" ] && { printf '%s' "$out"; exit 0; }
done
