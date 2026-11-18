#!/bin/sh
# Prints the messages of the crew stream that match the owner's filter, whole,
# as they arrive. The filter is one line of words in
# <crew dir>/work/hq-lead/stream.filter, read on each pass; hq when empty:
#   *        every message
#   <word>:  a subject that starts with <word>: (Question:, Contract:)
#   <word>   a member named <word>, or with <word> as a dash-separated part
#            of its name (api: api-dev1 ...; coord: every <area>-coord)
# A message from or to owner always matches. After a change, the last 5
# messages that match are printed again, then the new ones as they come.
# Usage: stream.sh <crew dir>
set -f
filter_file=$1/work/hq-lead/stream.filter
until cd "$1/messages" 2>/dev/null; do sleep 2; done
filter=
last=0

# The names of the messages numbered after <n>, in order.
after() {
    ls | awk -v l="$1" '{ n = $0; sub(/-.*/, "", n); if (n + 0 > l) print }' | sort
}

# Of the messages named on stdin, the ones that match the filter.
pick() {
    xargs awk -v filter="$filter" '
        function part(n, x) { return n != "" && index("-" n "-", "-" x "-") > 0 }
        function hit(   i, x) {
            if (from == "owner" || to == "owner") return 1
            for (i = 1; i <= nw; i++) {
                x = w[i]
                if (x == "*") return 1
                if (x ~ /:$/) { if (index(subject, x) == 1) return 1; continue }
                if (part(from, x) || part(to, x)) return 1
            }
            return 0
        }
        BEGIN { nw = split(filter, w, " ") }
        FNR == 1 { subject = $0; sub(/^# [0-9]+\. [^:]*: /, "", subject); from = ""; to = ""; next }
        /^From: / { from = $2; next }
        /^To: / { to = $2; if (hit()) print FILENAME; nextfile }
        FNR > 8 { nextfile }'
}

show() {
    printf '\033[1;36m%s\033[0m\n' "$1"
    cat "$1"
    printf '\n\033[2m%s\033[0m\n\n' "────────────────────────────────────────"
}

while :; do
    # crew archive starts the stream over at 1: follow it from there.
    top=$(ls | awk '{ n = $0; sub(/-.*/, "", n); if (n + 0 > m) m = n + 0 } END { print m + 0 }')
    [ "$top" -ge "$last" ] || last=0
    now=$(cat "$filter_file" 2>/dev/null)
    [ -n "$now" ] || now=hq
    if [ "$now" != "$filter" ]; then
        filter=$now
        printf '\033[1;33m── filter: %s ──\033[0m\n\n' "$filter"
        names=$(after 0 | tail -200)
        for f in $(printf '%s\n' "$names" | pick | tail -5); do show "$f"; done
    else
        names=$(after "$last")
        for f in $(printf '%s\n' "$names" | pick); do show "$f"; done
    fi
    newest=$(printf '%s\n' "$names" | tail -1)
    [ -z "$newest" ] || last=$(expr "${newest%%-*}" + 0)
    sleep 2
done
