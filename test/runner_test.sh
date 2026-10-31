#!/bin/sh
# The runner must see the area's final summary as well as a successful exit.
# Its test scripts live beside a copy of run.sh in a temporary directory.
#
#   sh test/run.sh runner

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

mkdir "$tmp/runner"
cp "$here/run.sh" "$tmp/runner/run.sh"
run() {
    sh "$tmp/runner/run.sh" "$@" >"$tmp/runner.out" 2>"$tmp/runner.err"
    echo $?
}

printf 'exit 0\n' >"$tmp/runner/early_test.sh"
check "an early successful exit fails its area" "1" "$(run early)"
check "the missing summary is explained" "crew: early did not end with 'early: <n> passed, 0 failed'" "$(cat "$tmp/runner.err")"

printf "echo 'good: 2 passed, 0 failed'\n" >"$tmp/runner/good_test.sh"
check "a completed area passes" "0" "$(run good)"
check "the final summary is counted" "2 passed, 0 failed" "$(tail -n 1 "$tmp/runner.out")"

printf "echo 'another: 2 passed, 0 failed'\n" >"$tmp/runner/wrong_test.sh"
check "another area's summary does not count" "1" "$(run wrong)"

printf "echo 'late: 2 passed, 0 failed'\necho 'still running'\n" >"$tmp/runner/late_test.sh"
check "a summary before the end does not count" "1" "$(run late)"

printf "echo 'failed: 2 passed, 1 failed'\n" >"$tmp/runner/failed_test.sh"
check "a failure count fails even with exit zero" "1" "$(run failed)"

printf "echo 'error: 2 passed, 0 failed'\nexit 1\n" >"$tmp/runner/error_test.sh"
check "a successful summary cannot hide a failed exit" "1" "$(run error)"

check "one incomplete area fails the run" "1" "$(run early good)"
check "later areas still run" "1" "$(grep -c '^good: 2 passed, 0 failed$' "$tmp/runner.out")"

finish
