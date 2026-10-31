#!/bin/sh
# Every captured screen has exactly one VERSIONS entry, and every entry
# names a screen. The regression examples copy an existing captured screen.
#
#   sh test/run.sh fixtures

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

fixture_parity() {
    for fixture in "$1"/*.txt; do
        [ -f "$fixture" ] || continue
        basename "$fixture" .txt
    done | LC_ALL=C sort >"$tmp/fixture.names"
    awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$1/VERSIONS" |
        LC_ALL=C sort >"$tmp/version.names"
    diff -u "$tmp/fixture.names" "$tmp/version.names"
}

parity() {
    fixture_parity "$1" >"$tmp/parity.diff" 2>&1
    echo $?
}

check "captured screens and VERSIONS match one to one" "0" "$(parity "$here/fixtures")"
[ ! -s "$tmp/parity.diff" ] || cat "$tmp/parity.diff"

mkdir "$tmp/screens"
cp "$here/fixtures/claude-run.txt" "$tmp/screens/claude-run.txt"
printf 'claude-run claude 2.1.314\n' >"$tmp/screens/VERSIONS"
check "a documented screen matches" "0" "$(parity "$tmp/screens")"

: >"$tmp/screens/VERSIONS"
check "a screen missing from VERSIONS fails" "1" "$(parity "$tmp/screens")"

printf 'claude-run claude 2.1.314\nmissing claude 2.1.314\n' >"$tmp/screens/VERSIONS"
check "an entry without a screen fails" "1" "$(parity "$tmp/screens")"

printf 'claude-run claude 2.1.314\nclaude-run claude 2.1.314\n' >"$tmp/screens/VERSIONS"
check "duplicate entries fail" "1" "$(parity "$tmp/screens")"

finish
