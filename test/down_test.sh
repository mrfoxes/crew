#!/bin/sh
# Ending a crew: End: sent, Done: waited for with a clock that is faked, what
# is left said, the watch and the board stopped, the archive and the closing
# of panes, with the terminal faked and a temporary repository with a bare
# origin.
#
#   sh test/run.sh down

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git() { command git -c user.name=t -c user.email=t@example.com "$@"; }
command git init -q --bare -b main "$tmp/origin.git"
command git init -q -b main "$tmp/repo"
cd "$tmp/repo" || exit 1
echo one >a.txt
git add a.txt
git commit -q -m first
git remote add origin "$tmp/origin.git"
git push -q -u origin main
dir=$(crew_init)
real=$(pwd -P)
kind_of_self() { :; }

# The terminal: the coordinator in tmux:%1, ada, bo, and cy in %2..%4, the
# watch and the board in %5 and %6; "running" lists the ttys with an agent
# (or a watch) in the foreground. Nothing else is touched.
for n in 1 2 3 4 5 6; do printf 'tmux:%%%d\t/dev/ttys00%d\tsh\n' "$n" "$n"; done >"$tmp/panes.list"
term_self() { echo tmux:%1; }
term_list() { cat "$tmp/panes.list"; }
term_tty() { echo "/dev/ttys00${1#tmux:%}"; }
term_running() { grep -qx "$1" "$tmp/running"; }
term_key() {
    echo "key $1 $2" >>"$tmp/calls"
    # ctrl-c brings the watch back to a shell, and the relay stops; the
    # board holds on.
    if [ "$1" = tmux:%5 ]; then
        grep -vx /dev/ttys005 "$tmp/running" >"$tmp/running.new"
        mv "$tmp/running.new" "$tmp/running"
        rm -f "$dir/relay.pid"
    fi
}
term_close() { echo "close $1" >>"$tmp/calls"; }
calls() {
    cat "$tmp/calls" 2>/dev/null
    rm -f "$tmp/calls"
}
printf '/dev/ttys002\n/dev/ttys003\n/dev/ttys004\n/dev/ttys005\n/dev/ttys006\n' >"$tmp/running"
for m in ada:2 bo:3 cy:4; do echo "tmux:%${m#*:}" >"$dir/panes/${m%:*}"; done
mkdir -p "$dir/up" "$dir/clones"
echo tmux:%5 >"$dir/up/watch"
echo tmux:%6 >"$dir/up/board"

# The clock: each sleep is thirty seconds; the first one brings ada's and
# bo's Done:, as their turns would between two polls.
echo 1000 >"$tmp/now"
down_now() { cat "$tmp/now"; }
down_sleep() {
    echo $(($(cat "$tmp/now") + 30)) >"$tmp/now"
    if [ ! -f "$tmp/dones" ]; then
        : >"$tmp/dones"
        echo ok | crew_send ada all "Done: landed" >/dev/null
        echo ok | crew_send bo owner "Done: patch saved" >/dev/null
        [ ! -f "$tmp/cy.answers" ] || echo ok | crew_send cy all "Done: nothing to land" >/dev/null
    fi
}

# What the crew left: an unpushed commit and a changed file in the shared
# tree, an unpushed commit in ada's clone, a patch, and the lock.
echo two >>a.txt
git commit -q -a -m "second"
echo three >b.txt
git add b.txt
command git clone -q "$tmp/origin.git" "$tmp/repo-ada" 2>/dev/null
echo x >"$tmp/repo-ada/c.txt"
git -C "$tmp/repo-ada" add c.txt
git -C "$tmp/repo-ada" commit -q -m "ada's work"
echo more >>"$tmp/repo-ada/a.txt"
git -C "$tmp/repo-ada" stash -q
echo "$tmp/repo-ada" >"$dir/clones/ada"
echo diff >"$dir/reports/bo.patch"
crew_lock cy >/dev/null

out=$(crew_down 1 2>&1)
status=$?
second=$(git -C "$tmp/repo" log -1 --format=%h)
adas=$(git -C "$tmp/repo-ada" log -1 --format=%h)
adastash=$(git -C "$tmp/repo-ada" stash list)
check "a crew where one never answers: the wait, the Dones, and what is left" "sent End: to all; waiting up to 1 minutes for Done:
waiting for: ada bo cy
ada: Done: sent
bo: Done: sent
waiting for: cy
left:
  no Done: from cy (running)
  the shared tree: unpushed commit $second second
  the shared tree: changed file A  b.txt
  ada's clone $tmp/repo-ada: unpushed commit $adas ada's work
  ada's clone $tmp/repo-ada: stash $adastash
  patch to apply: $tmp/repo/.crew/reports/bo.patch
  the lock is held: cy $(date '+%H:%M')
stopped the watch in tmux:%5
stopped the board in tmux:%6" "$(printf '%s\n' "$out" | sed "s|$real|$tmp/repo|g")"
check "and it exits 1" "1" "$status"
git -C "$tmp/repo-ada" stash drop -q
check "the End: is from the owner, to all, in the stream" "# 0001. owner to all: End: land or save a patch, write your report, send Done:" "$(sed -n 1p "$dir/seq/1")"
check "and points to the protocol" "1" "$(grep -c '"The end" in the protocol' "$dir/seq/1")"
check "the watch and the board got ctrl-c" "key tmux:%5 ctrl-c
key tmux:%6 ctrl-c" "$(calls)"
check "and are forgotten" "" "$(ls "$dir/up")"
check "nothing was archived" "3" "$(ls "$dir/seq" | wc -l | tr -d ' ')"

# --archive with something left archives nothing, and says so.
out=$(crew_down 0 --archive 2>&1)
check "--archive holds when something is left" "1" "$(printf '%s\n' "$out" | grep -c '^not archived: something is left$')"
check "and the stream stays" "1" "$([ -f "$dir/seq/1" ] && echo 1)"

# A member whose agent exited, a pane gone, and the coordinator joined as a
# member do not hold the wait; nobody is closed without --close.
echo tmux:%1 >"$dir/panes/lead"
echo tmux:%9 >"$dir/panes/dead"
grep -vx /dev/ttys004 "$tmp/running" >"$tmp/running.new"
mv "$tmp/running.new" "$tmp/running"
out=$(crew_down 0 2>&1)
check "who does not hold the wait" "3" "$(printf '%s\n' "$out" | grep -c -e '^cy: has exited: the wait does not hold for it$' -e '^dead: has no pane any more: the wait does not hold for it$' -e "^lead: is this pane, the coordinator's: the wait does not hold for it$")"
check "nothing is closed without --close" "" "$(calls)"
rm "$dir/panes/dead"

# What is left made clean: pushed, put back, no patch, no lock. Then
# --archive archives, after the watch let go of the relay.
git reset -q
rm -f b.txt "$dir/reports/bo.patch"
git push -q origin main
git -C "$tmp/repo-ada" reset -q --hard origin/main
git -C "$tmp/repo-ada" clean -q -f
crew_unlock cy >/dev/null
printf '/dev/ttys002\n/dev/ttys003\n/dev/ttys004\n/dev/ttys005\n/dev/ttys006\n' >"$tmp/running"
echo tmux:%5 >"$dir/up/watch"
echo tmux:%6 >"$dir/up/board"
echo $$ >"$dir/relay.pid"
calls >/dev/null
rm -f "$tmp/dones"
: >"$tmp/cy.answers"
out=$(crew_down 1 --archive 2>&1)
status=$?
check "a clean crew says so" "1" "$(printf '%s\n' "$out" | grep -c '^nothing is left$')"
check "and exits 0" "0" "$status"
check "--archive archived the stream" "1" "$(ls "$dir/archive" | wc -l | tr -d ' ')"
check "and started it over" "" "$(ls "$dir/seq")"
calls >/dev/null

# --close closes what exited: cy's pane, and the watch once it is back at a
# shell; never a running agent, never the coordinator's own pane, never the
# board when ctrl-c did not stop it.
printf '/dev/ttys002\n/dev/ttys003\n/dev/ttys005\n/dev/ttys006\n' >"$tmp/running"
echo tmux:%5 >"$dir/up/watch"
echo tmux:%6 >"$dir/up/board"
out=$(crew_down 0 --close 2>&1)
check "--close closed what exited, not a running agent, not the coordinator, not the board that holds on" "key tmux:%5 ctrl-c
key tmux:%6 ctrl-c
close tmux:%4
close tmux:%5" "$(calls)"
check "the board that holds on is said" "1" "$(printf '%s\n' "$out" | grep -c '^tmux:%6 still runs something: left open$')"

# The arguments.
check "a word that is not minutes" "2" "$(crew_down soon >/dev/null 2>&1; echo $?)"
check "and a flag that is not known" "2" "$(crew_down --kill >/dev/null 2>&1; echo $?)"

# A pane crew cannot read the tty of is never closed: its agent may run.
term_gone() { return 1; }
term_tty() { return 1; }
term_close() { echo "CLOSED $1"; }
check "a pane of unknown state is left open" "tmux:%77: crew cannot tell what runs there: left open" "$(down_close tmux:%77)"

finish
