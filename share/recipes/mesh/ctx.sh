#!/bin/sh
# Wakes the keeper (by exiting) when hq-lead or a coordinator sits at its
# prompt with a large context. Prints "<name> <percent>%" for each.
# The percent is read from the agent's status line ("NN% NNNk/1M").
# Usage: ctx.sh <crew dir> [percent, default 70]. Run it in the background.
dir=$1
max=${2:-70}
while :; do
    sleep 120
    over=""
    for f in "$dir/panes/hq-lead" "$dir"/panes/*-coord; do
        [ -f "$f" ] || continue
        m=${f##*/}
        pane=$(sed 's/^tmux://' "$f")
        pct=$(tmux capture-pane -p -t "$pane" 2>/dev/null | grep -oE '[0-9]+% [0-9]+k/1M' | tail -1 | cut -d% -f1)
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
