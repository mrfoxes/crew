#!/bin/sh
# The claims' tests: the warning crew status gives for a path another member
# lists, a directory claim, the words that mean no file, and the board's
# conflicts and unclaimed sections.
#
#   sh test/run.sh claims

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
git config user.email t@example.com
git config user.name t
mkdir src
echo a >src/a.rs
echo b >src/b.rs
echo c >c.txt
git add .
git commit -q -m init
dir=$(crew_init)

# status <name> <files>: writes a status with that Files: line, prints what
# it says on stderr.
status() {
    printf 'Agent: %s\nFiles: %s\nNext: more\n' "$1" "$2" | { crew_write status "$1" >/dev/null; } 2>&1
}
forget() { rm -f "$dir"/status/*.md; }

# The warning.
check "the first claim warns of nothing" "" "$(status ann src/a.rs)"
warning=$(status bob "src/a.rs")
check "the second claim warns" "1" "$(printf '%s\n' "$warning" | grep -c '^crew: src/a.rs is also claimed by ann (src/a.rs on its Files: line, written 0 min ago)')"
check "the warning says what to do" "1" "$(printf '%s\n' "$warning" | grep -c 'Heads-up:')"
check "the status is written anyway" "Files: src/a.rs" "$(sed -n 2p "$dir/status/bob.md")"
check "the exit is 0" "0" "$(printf 'Files: src/a.rs\n' | crew_write status bob >/dev/null 2>&1; echo $?)"
check "the path is still printed on stdout" "$dir/status/bob.md" "$(printf 'Files: src/a.rs\n' | crew_write status bob 2>/dev/null)"
check "a report does not warn" "" "$(echo 'Files: src/a.rs' | crew_write report bob 2>&1 >/dev/null)"

# A member's own earlier status is not a conflict with itself.
forget
status ann src/a.rs >/dev/null
check "no conflict with oneself" "" "$(status ann src/a.rs)"

# A directory against a file, either way round, with or without a trailing /.
forget
status ann "src/a.rs, c.txt" >/dev/null
check "a directory claim against a file" "1" "$(status bob "src/" | grep -c 'src/ is also claimed by ann (src/a.rs')"
check "a directory without slash against a file" "1" "$(status bob "src" | grep -c 'src is also claimed by ann (src/a.rs')"
forget
status ann "src/" >/dev/null
check "a file against a directory claim" "1" "$(status bob "src/a.rs" | grep -c 'src/a.rs is also claimed by ann (src/ on')"
forget
status ann "src" >/dev/null
check "a file against a directory without slash" "1" "$(status bob "src/a.rs" | grep -c 'src/a.rs is also claimed by ann (src on')"
check "a file beside a directory is not under it" "" "$(status bob "src.txt")"
check "a name that starts like a directory is not under it" "" "$(status bob "src-old/x.rs")"

# No overlap, and the same path written two ways.
forget
status ann "src/a.rs" >/dev/null
check "no overlap, no warning" "" "$(status bob "src/b.rs c.txt")"
check "./ is stripped" "1" "$(status bob "./src/a.rs" | grep -c 'src/a.rs is also claimed by ann')"
status ann "src/a.rs c.txt" >/dev/null
check "commas and spaces separate" "2" "$(status bob "src/a.rs,c.txt src/a.rs" | grep -c 'also claimed by ann')"

# The words that mean no file.
forget
status ann "src/a.rs" >/dev/null
for none in none nothing None n/a -; do
    check "'$none' claims nothing" "" "$(status bob "$none")"
done
check "a status with no Files: line claims nothing" "" "$(printf 'Agent: bob\n' | crew_write status bob 2>&1 >/dev/null)"

# The board's conflicts.
forget
board() { crew_board 1 | sed -n '/^== conflicts/,/^$/p'; }
status ann "src/a.rs c.txt" >/dev/null
status bob "src/b.rs" >/dev/null
check "no conflict, no section" "0" "$(crew_board 1 | grep -c '^== conflicts')"
status bob "./src/a.rs, src/b.rs" >/dev/null
check "a path two members claim" "== conflicts
src/a.rs: ann, bob" "$(board)"
status cat "src/" >/dev/null
check "a directory claim counts against the paths under it" "== conflicts
src/a.rs: ann, bob, cat
src/b.rs: bob, cat" "$(board)"
status cat "src" >/dev/null
check "a directory without slash counts against the paths under it" "== conflicts
src/a.rs: ann, bob, cat
src/b.rs: bob, cat" "$(board)"
check "the conflicts come after the statuses and before the lock" "yes" "$(crew_board 1 | awk '/^== cat/ { s = 1 } /^== conflicts/ { c = s } /^== lock/ { if (c) print "yes" }')"

# The board's unclaimed files.
forget
unclaimed() { crew_board 1 | sed -n '/^== unclaimed/,/^$/p'; }
status ann "src/a.rs" >/dev/null
check "a clean tree, no section" "0" "$(crew_board 1 | grep -c '^== unclaimed')"
echo more >>src/a.rs
check "a changed file somebody claims" "0" "$(crew_board 1 | grep -c '^== unclaimed')"
echo more >>src/b.rs
check "a modified file nobody claims" "== unclaimed
src/b.rs" "$(unclaimed)"
echo new >src/new.rs
check "an untracked file nobody claims" "== unclaimed
src/b.rs
src/new.rs" "$(unclaimed)"
status bob "src/" >/dev/null
check "a directory claim covers the files under it" "0" "$(crew_board 1 | grep -c '^== unclaimed')"
status bob "src" >/dev/null
check "a directory without slash covers the files under it" "0" "$(crew_board 1 | grep -c '^== unclaimed')"
forget
status ann "src/a.rs" >/dev/null
echo spaced >"src/two words.rs"
check "an untracked file with a space is unclaimed" "== unclaimed
src/b.rs
src/new.rs
src/two words.rs" "$(unclaimed)"
status ann "src/a.rs, src/two words.rs" >/dev/null
check "a file with a space on Files: is claimed and warns" "1" "$(status bob '"src/two words.rs"' | grep -c 'src/two words.rs is also claimed by ann')"
check "a file with a space counts in conflicts" "== conflicts
src/two words.rs: ann, bob" "$(board)"
rm -f "src/two words.rs"
forget
status ann "src/a.rs" >/dev/null
git add src/b.rs
git mv c.txt d.txt
git add src/new.rs
git commit -q -m more
git mv d.txt e.txt
check "a renamed file counts by its new path" "== unclaimed
e.txt" "$(unclaimed)"
git reset -q --hard
check "a tree back to clean has no section" "0" "$(crew_board 1 | grep -c '^== unclaimed')"

# Nothing outside git.
mkdir "$tmp/plain"
cd "$tmp/plain" || exit 1
dir=$(CREW_DIR=$tmp/plain/.crew crew_init)
echo x >loose.txt
check "outside git, no unclaimed section" "0" "$(CREW_DIR=$dir crew_board 1 | grep -c '^== unclaimed')"

finish
