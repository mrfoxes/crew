# What every test file shares: crew's functions, a check that counts, a
# temporary directory, and screens read from fixtures. Sourced by each
# test/*_test.sh, which test/run.sh runs in a shell of its own. No pane is
# touched: nothing here opens, moves, closes, or types into a pane of a
# terminal.
set -u

here=$(cd "$(dirname "$0")" && pwd)
CREW_HOME=$(dirname "$here")
. "$CREW_HOME/lib/store.sh"
. "$CREW_HOME/lib/kinds.sh"
. "$CREW_HOME/lib/claims.sh"
. "$CREW_HOME/lib/term.sh"
. "$CREW_HOME/lib/layout.sh"
. "$CREW_HOME/lib/clones.sh"
. "$CREW_HOME/lib/panes.sh"
. "$CREW_HOME/lib/gate.sh"
. "$CREW_HOME/lib/doctor.sh"
. "$CREW_HOME/lib/cost.sh"
. "$CREW_HOME/lib/crewfile.sh"
. "$CREW_HOME/lib/up.sh"
export CREW_WAKE=0
# No test notifies the owner; the ones that test notifying fake crew_notify.
export CREW_NOTIFY=0
unset CREW_IDLE_MINUTES
# What an agent running the tests sets would change what join reads.
unset CLAUDECODE CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID
# Every line of a log carries the time: one time here.
crew_stamp() { echo 12:00:00; }

passed=0
failed=0
check() {
    if [ "$2" = "$3" ]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$2" "$3"
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# The owner's own files, and a crew of the checkout the tests run from,
# stay out of it.
export XDG_CONFIG_HOME="$tmp/config"
# So do the agents' own logs: the readers of crew cost find nothing there
# unless a test points them at fixtures.
export CREW_CODEX_HOME="$tmp/none" CREW_AGY_HOME="$tmp/none" CREW_CLAUDE_HOME="$tmp/none"
cd "$tmp" || exit 1

# A pane that shows the fixtures named with show, one a read, the last for
# good: a file fakes term_read with it. A name with a / is a file's path.
show() {
    screens=$*
    echo 1 >"$tmp/read.n"
}
fixture_read() {
    i=$(cat "$tmp/read.n")
    # shellcheck disable=SC2086 # the names, one a word
    set -- $screens
    [ "$i" -le $# ] || i=$#
    eval "f=\$$i"
    echo $((i + 1)) >"$tmp/read.n"
    case "$f" in
    */*) cat "$f" ;;
    *) cat "$here/fixtures/$f.txt" ;;
    esac
}

# The file's count, as test/run.sh adds them up; fails on a failure.
finish() {
    printf '%s: %d passed, %d failed\n' "$(basename "$0" _test.sh)" "$passed" "$failed"
    [ "$failed" -eq 0 ]
}
