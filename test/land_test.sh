#!/bin/sh
# The landing tests: crew land commits only the given paths, adds the new
# ones, pushes, and tells the reviewer; stops before the lock without a
# reviewer or with a failing check; waits for a lock another holds, with the
# clock faked, and gives up; stops on a path that is not the member's or is
# another's; tells owner of a rejected push; lands from a clone; and leaves
# the lock free after each of them. All with git in temporary directories and
# a bare repository for origin: no network, no pane.
#
#   sh test/run.sh land

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

# A global identity, as on the owner's machine.
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --global user.name "Project Name"
git config --global user.email "project@example.com"
export GIT_CONFIG_NOSYSTEM=1

# The paths as git prints them, symbolic links resolved.
tmp=$(cd "$tmp" && pwd -P)
git init -q --bare -b main "$tmp/origin.git"
mkdir -p "$tmp/work"
git clone -q "$tmp/origin.git" "$tmp/work/proj" 2>/dev/null
cd "$tmp/work/proj" || exit 1
echo one >a.txt
echo two >b.txt
echo three >c.txt
git add .
git commit -q -m first
git push -q -u origin HEAD:main 2>/dev/null
git branch -q --set-upstream-to=origin/main main
proj=$PWD
dir=$(crew_init)
printf 'Add the things\n\nThe body.\n' >"$tmp/message"

# A clock that only the waits move, so that no test sleeps. A wait can also
# release the lock bob holds, at the wait numbered release_at.
echo 0 >"$tmp/clock"
: >"$tmp/waits"
release_at=0
land_now() { cat "$tmp/clock"; }
land_wait() {
    echo $(($(cat "$tmp/clock") + 10)) >"$tmp/clock"
    echo wait >>"$tmp/waits"
    [ "$(waits)" -ne "$release_at" ] || crew_unlock bob >/dev/null
}
waits() { wc -l <"$tmp/waits" | tr -d ' '; }

# edit <file>: gives the file a content it has not had yet.
edits=0
edit() {
    edits=$((edits + 1))
    echo "change $edits" >"$1"
}
# status <name> <files>: writes that member's status.
status() { printf 'Agent: %s\nFiles: %s\nNext: more\n' "$1" "$2" | crew_write status "$1" >/dev/null 2>&1; }
# land <args>: crew land with its words kept apart; prints its exit code.
land() {
    echo 0 >"$tmp/clock"
    : >"$tmp/waits"
    crew_land "$@" >"$tmp/out" 2>"$tmp/err"
    echo $?
}
lock() { if [ -d "$dir/lock" ]; then cut -d' ' -f1 "$dir/lock/owner"; else echo free; fi; }
# Back to what origin has, nothing changed, nothing new.
tidy() {
    git -C "$proj" fetch -q origin
    git -C "$proj" reset -q --hard origin/main
    git -C "$proj" clean -fdq
}
# The messages from <from> to <to> whose subject starts with <subject>.
sent() { printf '%s\n' "$dir"/messages/* | grep -c -- "-$1-to-$2-$3"; }
origin_head() { git -C "$tmp/origin.git" log -1 --format=%s main; }

status ann "a.txt new.txt clone.txt"
status bob "b.txt"

# A landing: only the given paths, the new one added, pushed, the lock free,
# the reviewer told. The check runs in the working tree.
edit a.txt
edit b.txt
echo fresh >new.txt
check "a landing succeeds" "0" "$(land ann -F "$tmp/message" --check "pwd >'$tmp/checkdir'" --to cat -- a.txt new.txt)"
hash=$(git rev-parse --short HEAD)
check "the check ran in the working tree" "$proj" "$(cat "$tmp/checkdir")"
check "origin has the commit" "Add the things" "$(origin_head)"
check "the commit is the given paths" "a.txt
new.txt" "$(git show --name-only --format= HEAD)"
check "the message file is the message" "The body." "$(git log -1 --format=%b | sed -n 1p)"
check "another changed file stays uncommitted" " M b.txt" "$(git status --porcelain)"
check "the lock is free" "free" "$(lock)"
check "a status with no Pushed: line gets one, and no other line changes" "Agent: ann
Files: a.txt new.txt clone.txt
Next: more
Pushed: $hash Add the things, CI pending" "$(cat "$dir/status/ann.md")"
check "it says what it did" "landed $hash Add the things
told cat" "$(cat "$tmp/out")"
check "the reviewer from --to is told" "1" "$(sent ann cat "pushed-$hash-add-the-things")"
check "the message is Pushed: with the hash and the subject" "1" "$(grep -c "^# 0001\. ann to cat: Pushed: $hash Add the things$" "$dir"/messages/*-ann-to-cat-*)"
check "and the stat of the commit" "1" "$(grep -c 'new.txt' "$dir"/messages/*-ann-to-cat-*)"
tidy

# A status with a Pushed: line has that line rewritten in place.
printf 'Agent: ann\nPushed: none\nFiles: a.txt\nNext: more\n' | crew_write status ann >/dev/null 2>&1
edit a.txt
check "a second landing succeeds" "0" "$(land ann -F "$tmp/message" --to cat -- a.txt)"
hash=$(git rev-parse --short HEAD)
check "the Pushed: line is rewritten where it was" "Agent: ann
Pushed: $hash Add the things, CI pending
Files: a.txt
Next: more" "$(cat "$dir/status/ann.md")"
tidy
status ann "a.txt new.txt clone.txt"

# The reviewer from the Crewfile, and on the board.
cat >"$dir/Crewfile" <<'EOF2'
tab main
member ann reviewer=bob -- claude
member bob reviewer=ann -- claude
EOF2
edit a.txt
check "the Crewfile's reviewer" "0" "$(land ann -F "$tmp/message" -- a.txt)"
hash=$(git rev-parse --short HEAD)
check "its reviewer is told" "1" "$(sent ann bob "pushed-$hash")"
check "the board names the reviewer" "== ann (no pane, reviewed by bob, 0 min ago)" "$(crew_board 1 | grep '^== ann')"
check "and another's" "== bob (no pane, reviewed by ann, 0 min ago)" "$(crew_board 1 | grep '^== bob')"
rm "$dir/Crewfile"
check "no Crewfile, no reviewer on the board" "== ann (no pane, 0 min ago)" "$(crew_board 1 | grep '^== ann')"
tidy

# No reviewer: it stops before the lock, which another holds and is left alone.
crew_lock bob >/dev/null
edit a.txt
check "no reviewer stops" "1" "$(land ann -F "$tmp/message" -- a.txt)"
check "it says how to give one" "1" "$(grep -c 'ann has no reviewer: give one with --to <member>, or reviewer=<member>' "$tmp/err")"
check "the lock was not tried" "0" "$(waits)"
check "the lock is still bob's" "bob" "$(lock)"
check "nothing was committed" "0" "$(git rev-list --count origin/main..HEAD)"
crew_unlock bob >/dev/null

# A failing check stops before the lock too, and shows the end of its output.
crew_lock bob >/dev/null
check "a failing check stops" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo first; echo boom; exit 3' -- a.txt)"
check "it says the check failed" "1" "$(grep -c '^crew: the check failed' "$tmp/err")"
check "it prints what the check said" "1" "$(grep -c '^  boom$' "$tmp/err")"
check "the lock was not tried" "0" "$(waits)"
check "nothing was committed" "0" "$(git rev-list --count origin/main..HEAD)"
crew_unlock bob >/dev/null

# Paths with no change stop it first, before the check and the lock.
crew_lock bob >/dev/null
check "paths with no change stop it" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- c.txt)"
check "it says so" "1" "$(grep -c '^crew: none of the paths has a change' "$tmp/err")"
check "the check did not run" "no" "$([ -e "$tmp/ran" ] && echo yes || echo no)"
check "the lock was not tried" "0" "$(waits)"
check "the lock is still bob's" "bob" "$(lock)"
crew_unlock bob >/dev/null

# A lock another holds is waited for, and said whose it is.
crew_lock bob >/dev/null
release_at=3
check "a lock released meanwhile is taken" "0" "$(land ann -F "$tmp/message" --to bob -- a.txt)"
check "it waited three times" "3" "$(waits)"
check "it said who holds the lock" "3" "$(grep -c 'the lock is held by bob; trying again in 10 seconds' "$tmp/err")"
check "the lock is free after" "free" "$(lock)"
release_at=0
tidy

# A lock held for good is given up after 5 minutes, and stays the holder's.
crew_lock bob >/dev/null
edit a.txt
check "a lock held for good stops it" "1" "$(land ann -F "$tmp/message" --to bob -- a.txt)"
check "it waited 5 minutes of 10 seconds" "30" "$(waits)"
check "it says it gave up" "1" "$(grep -c "the lock is still bob's after 5 minutes" "$tmp/err")"
check "the lock is still bob's" "bob" "$(lock)"
check "nothing was committed" "0" "$(git rev-list --count origin/main..HEAD)"
crew_unlock bob >/dev/null

# A path that is not on the member's Files: line, and one another claims.
edit c.txt
check "a path not on the Files: line stops it" "1" "$(land ann -F "$tmp/message" --to bob -- a.txt c.txt)"
check "it names the path" "1" "$(grep -c "^crew: c.txt is not on ann's Files: line" "$tmp/err")"
check "the lock is free" "free" "$(lock)"
check "nothing was committed" "0" "$(git rev-list --count origin/main..HEAD)"
status ann "a.txt c.txt"
status bob "b.txt c.txt"
check "a path another claims stops it" "1" "$(land ann -F "$tmp/message" --to bob -- a.txt c.txt)"
check "it names the path and who" "1" "$(grep -c '^crew: c.txt is also claimed by bob' "$tmp/err")"
check "the lock is free" "free" "$(lock)"
check "nothing was committed" "0" "$(git rev-list --count origin/main..HEAD)"
status ann "a.txt dir/"
mkdir dir
echo x >dir/x
check "a directory claim covers the new file under it" "0" "$(land ann -F "$tmp/message" --to bob -- ./dir/x)"
check "the new file is committed" "dir/x" "$(git show --name-only --format= HEAD)"
check "the lock is free" "free" "$(lock)"
check "a path outside the project stops it" "1" "$(land ann -F "$tmp/message" --to bob -- ../x)"

# Literal pathspecs only, directories without a trailing slash, files under a
# directory claim, and a file whose name holds a space.
edit a.txt
edit b.txt
status ann ":(top)* :/ * ? [ab].txt a.txt"
crew_lock bob >/dev/null
check "pathspec :(top)* is treated as a literal path" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- ':(top)*')"
check "pathspec :/ is treated as a literal path" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- ':/')"
check "glob * is treated as a literal path" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- '*')"
check "glob ? is treated as a literal path" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- '?')"
check "glob [ab].txt is treated as a literal path" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- '[ab].txt')"
check "globs and magic never ran the check or tried the lock" "no 0" "$([ -e "$tmp/ran" ] && echo yes || echo no) $(waits)"
echo y >dir/y
status ann "dir/y"
status bob "dir"
check "a file under another member's directory claim stops before check and lock" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- dir/y)"
check "it says the file is also claimed by the directory holder" "1" "$(grep -c '^crew: dir/y is also claimed by bob' "$tmp/err")"
status ann "dir"
status bob "dir/y"
check "landing a directory stops when a file under it is claimed by another" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- dir)"
check "it names the file under the directory" "1" "$(grep -c '^crew: dir/y is also claimed by bob' "$tmp/err")"
status ann "dir/x"
status bob "b.txt"
echo x2 >dir/x
check "landing a directory stops when an unclaimed file under it changed" "1" "$(land ann -F "$tmp/message" --to bob --check 'echo ran >"$tmp/ran"' -- dir)"
check "it names the unclaimed file under the directory" "1" "$(grep -c "^crew: dir/y is not on ann's Files: line" "$tmp/err")"
check "none of the directory conflicts ran the check or tried the lock" "no 0" "$([ -e "$tmp/ran" ] && echo yes || echo no) $(waits)"
crew_unlock bob >/dev/null
rm dir/y
status ann "dir"
check "a directory without a trailing slash lands the files under it" "0" "$(land ann -F "$tmp/message" --to bob -- dir)"
check "the changed file under the directory is committed" "dir/x" "$(git show --name-only --format= HEAD)"
echo spaced >"dir/two words.txt"
status ann '"dir/two words.txt"'
check "a file whose name holds a space lands" "0" "$(land ann -F "$tmp/message" --to bob -- "dir/two words.txt")"
check "the file with a space is committed" "dir/two words.txt" "$(git show --name-only --format= HEAD)"
tidy
status ann "a.txt new.txt clone.txt"
status bob "b.txt"

# A rejected push: owner is told, nothing is pulled, the lock is free.
git clone -q "$tmp/origin.git" "$tmp/other" 2>/dev/null
echo more >"$tmp/other/z.txt"
git -C "$tmp/other" add z.txt
git -C "$tmp/other" commit -q -m "Meanwhile"
git -C "$tmp/other" push -q origin HEAD:main
edit a.txt
check "a rejected push stops it" "1" "$(land ann -F "$tmp/message" --to bob -- a.txt)"
hash=$(git rev-parse --short HEAD)
check "owner is asked" "1" "$(sent ann owner "question-push-of-$hash-rejected")"
check "the question says what git said" "yes" "$(grep -q rejected "$dir"/messages/*-ann-to-owner-* && echo yes)"
check "the lock is free" "free" "$(lock)"
check "nothing was pulled" "0" "$(git log --format=%s | grep -c Meanwhile)"
check "the commit stays, unpushed" "1" "$(git rev-list --count origin/main..HEAD)"
check "the reviewer was not told" "0" "$(sent ann bob "pushed-$hash")"
check "origin is theirs" "Meanwhile" "$(origin_head)"
tidy

# From a clone: the commit goes to origin from there, the project is left.
git clone -q "$tmp/origin.git" "$tmp/work/proj-ann" 2>/dev/null
mkdir -p "$dir/clones"
echo "$tmp/work/proj-ann" >"$dir/clones/ann"
before=$(git rev-parse HEAD)
edit "$tmp/work/proj-ann/a.txt"
echo fresh >"$tmp/work/proj-ann/clone.txt"
edit "$tmp/work/proj-ann/c.txt"
check "a clone lands" "0" "$(land ann -F "$tmp/message" --to bob -- a.txt clone.txt)"
hash=$(git -C "$tmp/work/proj-ann" rev-parse --short HEAD)
check "origin has the clone's commit" "Add the things" "$(origin_head)"
check "it holds the given paths only" "a.txt
clone.txt" "$(git -C "$tmp/work/proj-ann" show --name-only --format= HEAD)"
check "the clone's other change stays" " M c.txt" "$(git -C "$tmp/work/proj-ann" status --porcelain)"
check "the project's tree was not touched" "$before" "$(git rev-parse HEAD)"
check "the lock is free" "free" "$(lock)"
check "the reviewer is told" "1" "$(sent ann bob "pushed-$hash")"
check "the message says where it landed from" "1" "$(grep -c "Landed from $tmp/work/proj-ann" "$dir"/messages/*-ann-to-bob-pushed-$hash-*)"
git -C "$tmp/work/proj-ann" checkout -q -- c.txt

# Two clones over a moved origin: a clean rebase and second check, a conflict,
# a check that fails after the rebase, and crew sync.
git clone -q "$tmp/origin.git" "$tmp/work/proj-bob" 2>/dev/null
echo "$tmp/work/proj-bob" >"$dir/clones/bob"
edit "$tmp/work/proj-bob/b.txt"
printf 'Bob lands first\n' >"$tmp/bob-msg"
check "bob lands from his clone" "0" "$(land bob -F "$tmp/bob-msg" --to ann -- b.txt)"
bob_val=$(cat "$tmp/work/proj-bob/b.txt")

# ann's clone is behind origin/main: crew land fetches, rebases, runs --check
# again on the rebased tree (which now has bob's b.txt), and pushes.
: >"$tmp/checks"
edit "$tmp/work/proj-ann/a.txt"
check "ann lands over a moved origin" "0" "$(land ann -F "$tmp/message" --to bob --check "cat b.txt >>'$tmp/checks'" -- a.txt)"
hash=$(git -C "$tmp/work/proj-ann" rev-parse --short HEAD)
check "origin has ann's rebased commit" "Add the things" "$(origin_head)"
check "the parent on origin is bob's commit" "Bob lands first" "$(git -C "$tmp/origin.git" log -1 --format=%s main~1)"
check "the check ran before and after the rebase" "2" "$(wc -l <"$tmp/checks" | tr -d ' ')"
check "the second check saw bob's change" "$bob_val" "$(tail -n 1 "$tmp/checks")"
check "the lock is free after a rebased land" "free" "$(lock)"
check "the reviewer is told the rebased hash" "1" "$(sent ann bob "pushed-$hash")"

# crew sync: refuses the shared tree and a dirty clone, syncs a clean clone,
# and aborts a conflicting rebase leaving the clone as it was.
check "sync with no arguments" "2" "$(crew_sync >/dev/null 2>&1; echo $?)"
check "sync refuses a member in the shared tree" "1" "$(crew_sync cat >/dev/null 2>"$tmp/err"; echo $?)"
check "it says crew sync is for a clone" "1" "$(grep -c 'shared tree' "$tmp/err")"
echo dirty >"$tmp/work/proj-bob/b.txt"
check "sync refuses a dirty clone" "1" "$(crew_sync bob >/dev/null 2>"$tmp/err"; echo $?)"
check "it says the clone has changes" "1" "$(grep -c 'has changes; left as it is' "$tmp/err")"
check "the dirty file stays" "dirty" "$(cat "$tmp/work/proj-bob/b.txt")"
git -C "$tmp/work/proj-bob" checkout -q -- b.txt
check "sync brings bob's clean clone up to origin/main" "0" "$(crew_sync bob >"$tmp/out" 2>"$tmp/err"; echo $?)"
check "bob's clone is at ann's commit" "$hash" "$(git -C "$tmp/work/proj-bob" rev-parse --short HEAD)"

# A conflict while crew sync rebases a local commit: aborted, clone unchanged.
echo "bob conflict" >"$tmp/work/proj-bob/a.txt"
git -C "$tmp/work/proj-bob" commit -q -am "Bob local a"
bob_local=$(git -C "$tmp/work/proj-bob" rev-parse HEAD)
edit "$tmp/work/proj-ann/a.txt"
check "ann lands another change to a.txt" "0" "$(land ann -F "$tmp/message" --to bob -- a.txt)"
check "sync aborts on a conflict" "1" "$(crew_sync bob >/dev/null 2>"$tmp/err"; echo $?)"
check "sync names the conflicting file" "1" "$(grep -c 'conflicted in a.txt' "$tmp/err")"
check "bob's clone is left at its commit" "$bob_local" "$(git -C "$tmp/work/proj-bob" rev-parse HEAD)"
check "no rebase is in progress after sync conflict" "no" "$([ -d "$tmp/work/proj-bob/.git/rebase-merge" ] || [ -d "$tmp/work/proj-bob/.git/rebase-apply" ] && echo yes || echo no)"
check "bob's working tree is clean" "" "$(git -C "$tmp/work/proj-bob" status --porcelain)"
git -C "$tmp/work/proj-bob" reset -q --hard origin/main

# A conflict while crew land rebases under the lock: git rebase --abort
# restores the commit as it was, releases the lock, and tells owner with the
# conflicting files.
status bob "a.txt b.txt"
status ann "a.txt new.txt clone.txt"
git -C "$tmp/work/proj-ann" reset -q --hard origin~1
status bob "a.txt"
status ann "new.txt"
edit "$tmp/work/proj-bob/a.txt"
check "bob lands a.txt" "0" "$(land bob -F "$tmp/bob-msg" --to ann -- a.txt)"
status bob "b.txt"
status ann "a.txt new.txt clone.txt"
edit "$tmp/work/proj-ann/a.txt"
check "a rebase conflict on land stops it" "1" "$(land ann -F "$tmp/message" --to bob -- a.txt)"
ann_commit=$(git -C "$tmp/work/proj-ann" rev-parse --short HEAD)
check "the commit stays as HEAD in the clone" "Add the things" "$(git -C "$tmp/work/proj-ann" log -1 --format=%s)"
check "no rebase is left in progress" "no" "$([ -d "$tmp/work/proj-ann/.git/rebase-merge" ] || [ -d "$tmp/work/proj-ann/.git/rebase-apply" ] && echo yes || echo no)"
check "the clone's working tree is clean" "" "$(git -C "$tmp/work/proj-ann" status --porcelain)"
check "the lock is free after a conflict" "free" "$(lock)"
check "origin stays at bob's commit" "Bob lands first" "$(origin_head)"
check "owner is told of the conflict" "1" "$(sent ann owner "question-rebase-of-$ann_commit-conflicted")"
check "the message names the conflicting file" "1" "$(grep -c 'a.txt' "$dir"/messages/*-ann-to-owner-question-rebase-of-"$ann_commit"-conflicted*)"
git -C "$tmp/work/proj-ann" reset -q --hard origin/main

# A check that fails after a clean rebase: nothing is pushed, the rebased
# commit stays as HEAD, and both hashes (ORIG_HEAD and HEAD) and the check's
# output are in the message to owner.
edit "$tmp/work/proj-bob/b.txt"
check "bob lands b.txt to move origin" "0" "$(land bob -F "$tmp/bob-msg" --to ann -- b.txt)"
bob_head=$(git -C "$tmp/work/proj-bob" rev-parse --short HEAD)
edit "$tmp/work/proj-ann/a.txt"
check "a check failing after rebase stops the push" "1" "$(land ann -F "$tmp/message" --to bob --check "if [ \"\$(git rev-parse --short HEAD~1)\" = '$bob_head' ]; then echo 'after-rebase-boom'; exit 4; fi" -- a.txt)"
rebased_hash=$(git -C "$tmp/work/proj-ann" rev-parse --short HEAD)
orig_hash=$(git -C "$tmp/work/proj-ann" rev-parse --short ORIG_HEAD)
check "the two hashes differ" "yes" "$([ "$orig_hash" != "$rebased_hash" ] && echo yes)"
check "origin did not receive the commit" "Bob lands first" "$(origin_head)"
check "the rebased commit stays as the clone's HEAD" "Add the things" "$(git -C "$tmp/work/proj-ann" log -1 --format=%s)"
check "and its parent is origin/main" "$bob_head" "$(git -C "$tmp/work/proj-ann" rev-parse --short HEAD~1)"
check "the lock is free after a post-rebase check failure" "free" "$(lock)"
check "owner is told of the failed check after rebase" "1" "$(sent ann owner "question-check-failed-after-rebasing-$orig_hash")"
check "the message names ORIG_HEAD" "yes" "$(grep -q "$orig_hash" "$dir"/messages/*-ann-to-owner-question-check-failed-after-rebasing-"$orig_hash"* && echo yes)"
check "the message names the rebased HEAD" "yes" "$(grep -q "$rebased_hash" "$dir"/messages/*-ann-to-owner-question-check-failed-after-rebasing-"$orig_hash"* && echo yes)"
check "the message has the check's output" "yes" "$(grep -q '^after-rebase-boom$' "$dir"/messages/*-ann-to-owner-question-check-failed-after-rebasing-"$orig_hash"* && echo yes)"
rm "$dir/clones/ann" "$dir/clones/bob"

# Arguments.
check "no arguments" "2" "$(land)"
check "no paths" "2" "$(land ann -F "$tmp/message" --to bob)"
check "no message file" "2" "$(land ann --to bob -- a.txt)"
check "a missing message file" "1" "$(land ann -F "$tmp/nosuch" --to bob -- a.txt)"
check "an unknown option" "2" "$(land ann -F "$tmp/message" --nosuch -- a.txt)"
check "a bad name" "2" "$(land ANN -F "$tmp/message" --to bob -- a.txt)"

finish
