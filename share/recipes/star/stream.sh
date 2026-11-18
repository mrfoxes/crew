#!/bin/sh
# Prints every message of the crew stream, whole, as it arrives.
dir=$1
last=0
while :; do
    for f in $(ls "$dir/messages" 2>/dev/null | sort); do
        n=${f%%-*}
        n=$(echo "$n" | sed 's/^0*//'); n=${n:-0}
        [ "$n" -gt "$last" ] || continue
        printf '\033[1;36m%s\033[0m\n' "$f"
        cat "$dir/messages/$f"
        printf '\n\033[2m%s\033[0m\n\n' "────────────────────────────────────────"
        last=$n
    done
    sleep 2
done
