#!/bin/sh
# crew send's tests: the body from stdin, from -m, or from -F; a body from two
# places refused; a recipient the crew does not know posted with a warning
# that names the members.
#
#   sh test/run.sh send

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
mkdir -p "$dir/status" "$dir/nopane"
: >"$dir/status/ada.md"
: >"$dir/nopane/bob"
echo '%' >"$tmp/pane"
mkdir -p "$dir/panes"
echo tmux:%1 >"$dir/panes/cyd"

# crew_send sets tmp, the harness's own: each call runs in a subshell. send
# prints the message's path; err is what it said on stderr.
send() { (crew_send "$@" 2>"$tmp/err"); }
body() { sed -n '/^Time: /,$p' "$1" | sed '1,2d'; }

check "stdin is the body" "from stdin" "$(body "$(printf 'from stdin\n' | send ada bob "Plan: one")")"
check "-m is the body" "from -m" "$(body "$(send ada bob "Plan: two" -m 'from -m' </dev/null)")"
check "--message is the body" "from --message" "$(body "$(send ada bob --message 'from --message' "Plan: three" </dev/null)")"
printf 'from a file\nsecond line\n' >"$tmp/body.txt"
check "-F is the body" "from a file
second line" "$(body "$(send ada bob "Plan: four" -F "$tmp/body.txt" </dev/null)")"
check "--file is the body" "from a file
second line" "$(body "$(send ada bob "Plan: five" --file "$tmp/body.txt" </dev/null)")"
check "-F - reads stdin" "piped" "$(body "$(printf 'piped\n' | send ada bob "Plan: six" -F -)")"
check "the subject is what is not a flag" "1" "$(grep -c '^# 0007\. ada to bob: Plan: seven$' "$(send ada bob Plan: seven -m x </dev/null)")"
check "-m leaves stdin alone" "from -m" "$(body "$(printf 'ignored\n' | send ada bob "Plan: eight" -m 'from -m')")"

check "a body from two places is refused" "2" "$(send ada bob "Plan: nine" -m a -F "$tmp/body.txt" </dev/null >/dev/null; echo $?)"
check "-m with no text is refused" "2" "$(send ada bob "Plan: ten" -m </dev/null >/dev/null; echo $?)"
check "no subject is refused" "2" "$(send ada bob -m x </dev/null >/dev/null; echo $?)"
check "a missing body file stops" "1" "$(send ada bob "Plan: eleven" -F "$tmp/nosuch" </dev/null >/dev/null; echo $?)"
check "it says which file" "1" "$(grep -c "the body file $tmp/nosuch does not exist" "$tmp/err")"
check "nothing was posted for the refusals" "8" "$(ls "$dir/seq" | wc -l | tr -d ' ')"

# A recipient the crew does not know is posted, with a warning.
check "an unknown recipient is posted" "0" "$(send ada agy4 "Question: who" -m x </dev/null >/dev/null; echo $?)"
check "the warning names it" "1" "$(grep -c '^crew: agy4 is not a member of this crew' "$tmp/err")"
check "and the members" "1" "$(grep -c '(members: ada, bob, cyd)' "$tmp/err")"
check "the message is there" "1" "$(printf '%s\n' "$dir"/messages/*-ada-to-agy4-* | grep -c 'ada-to-agy4-')"
for to in all owner ada bob cyd; do
    send ada "$to" "Plan: to $to" -m x </dev/null >/dev/null
    check "no warning for $to" "0" "$(grep -c 'is not a member' "$tmp/err")"
done
mkdir -p "$dir/threads"
echo t >"$dir/threads/dee"
send ada dee "Plan: dee" -m x </dev/null >/dev/null
check "a thread makes a member" "0" "$(grep -c 'is not a member' "$tmp/err")"
printf 'tab main\nmember ed reviewer=eve -- claude\nmember eve reviewer=ed -- claude\n' >"$dir/Crewfile"
send ada ed "Plan: ed" -m x </dev/null >/dev/null
check "a Crewfile line makes a member" "0" "$(grep -c 'is not a member' "$tmp/err")"

finish
