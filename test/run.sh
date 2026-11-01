#!/bin/sh
# crew's tests, one file an area (test/<area>_test.sh), each run in a shell
# of its own so that what one fakes cannot leak into the next. No pane is
# touched: nothing here opens, moves, closes, or types into a pane of a
# terminal.
#
#   sh test/run.sh              every area
#   sh test/run.sh gate term    those areas only
#   sh test/run.sh e2e          the end-to-end run in a tmux server of its
#                               own (test/e2e_tmux.sh), never part of the rest
here=$(cd "$(dirname "$0")" && pwd)

if [ $# -eq 0 ]; then
    set -- "$here"/*_test.sh
else
    for area in "$@"; do
        shift
        case "$area" in
        e2e) set -- "$@" "$here/e2e_tmux.sh" ;;
        *) set -- "$@" "$here/${area}_test.sh" ;;
        esac
    done
fi
status=0
out=""
for f in "$@"; do
    if [ ! -f "$f" ]; then
        echo "crew: no tests at $f" >&2
        status=2
        continue
    fi
    line=$(sh "$f") || status=1
    printf '%s\n' "$line"
    area=${f##*/}
    area=${area%_test.sh}
    area=${area%_tmux.sh}
    summary=$(printf '%s\n' "$line" | tail -n 1)
    if ! printf '%s\n' "$summary" | awk -v area="$area" '
        $2 ~ /^[0-9]+$/ && $0 == (area ": " $2 " passed, 0 failed") { complete = 1 }
        END { exit !complete }'; then
        echo "crew: $area did not finish successfully; expected '$area: <n> passed, 0 failed'" >&2
        status=1
    fi
    out="$out$summary
"
done
# Every file ends with "<area>: <n> passed, <m> failed".
printf '%s' "$out" | awk '/^[a-z0-9-]+: [0-9]+ passed, [0-9]+ failed$/ { p += $2; f += $4 }
    END { printf "%d passed, %d failed\n", p, f }'
exit "$status"
