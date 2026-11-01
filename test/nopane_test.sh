#!/bin/sh
# A member with no pane: joined with --no-pane, it reads the stream on its
# own, and crew unread --wait blocks until something arrives for it.
#
#   sh test/run.sh nopane

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
# The terminal, as every machine sees it: one tmux pane, %7, claude's.
term_list() { printf 'tmux:%%7\t/dev/ttys001\tsh\n'; }
term_self() { echo tmux:%7; }
term_poke() { echo "$1 <- $2"; }
crew_label() { :; }
crew_unlabel() { :; }
kind_of_self() { :; }

# Joining with --no-pane records the choice, even from inside a pane.
check "join --no-pane says so" "You are coord, of kind other, in the crew at $dir, in no pane, as you asked: a message to you waits for your next 'crew unread coord', which 'crew unread coord --wait' blocks for." "$(crew_join coord --no-pane | sed -n 1p)"
check "join --no-pane records the choice" "1" "$([ -e "$dir/nopane/coord" ] && echo 1)"
check "join --no-pane keeps no pane" "0" "$([ -e "$dir/panes/coord" ] && echo 1 || echo 0)"
check "join --no-pane after a pane forgets the pane" "0" "$(crew_join coord >/dev/null; crew_join coord --no-pane >/dev/null; [ -e "$dir/panes/coord" ] && echo 1 || echo 0)"
check "join from a pane takes the choice back" "0" "$(crew_join coord >/dev/null; [ -e "$dir/nopane/coord" ] && echo 1 || echo 0)"
crew_join coord --no-pane >/dev/null

# A message to it waits, and says so without reading as an error.
check "wake names the member that reads on its own" "crew: coord reads the stream on its own; the message waits for its next 'crew unread coord'" "$(crew_wake "$dir" 3 codex coord "Question: when?" 2>&1)"
check "wake types nothing for it" "0" "$(crew_wake "$dir" 3 codex coord "Question: when?" 2>/dev/null | grep -c '<-')"
term_running() { return 0; }
kind_record "$dir" claude claude
check "a message to all passes it by" "" "$(crew_join claude >/dev/null; crew_wake "$dir" 4 codex all "Plan: go" 2>&1 >/dev/null)"
check "and wakes the one with a pane" "tmux:%7 <- crew: message 0004 from codex. Run: crew unread claude" "$(crew_wake "$dir" 4 codex all "Plan: go" 2>/dev/null)"

# It has no pane to read, type into, or list.
check "peek says it joined with --no-pane" "crew: coord joined with --no-pane: there is no pane to read or type into" "$(crew_pane coord 2>&1 >/dev/null)"
check "panes lists it after the panes" "coord other - no pane - -" "$(crew_panes | tail -n 1 | awk '{ print $1, $2, $3, $4, $5, $6, $7 }')"
check "leave forgets the choice" "0" "$(crew_leave coord >/dev/null; [ -e "$dir/nopane/coord" ] && echo 1 || echo 0)"


# crew unread --wait blocks until a message for the member arrives, then
# prints it as unread does; on a timeout it prints nothing, exits 1, and
# leaves the cursor where it was.
(sleep 1 && echo later | crew_send codex coord "Answer: now" >/dev/null) &
check "wait ends with the message that arrives" "1" "$(crew_unread coord --wait 10 | grep -c '^# 0001\. codex to coord: Answer: now$')"
wait
check "wait moves the cursor" "No new messages for coord." "$(crew_unread coord)"
check "wait times out with nothing printed" "" "$(crew_unread coord --wait 1)"
check "and exits 1" "1" "$(crew_unread coord --wait 1 >/dev/null; echo $?)"
check "wait leaves the cursor" "1" "$(cat "$dir/cursors/coord")"
(sleep 1 && echo mine | crew_send coord all "Plan: mine" >/dev/null) &
check "a message to all from the member itself does not end the wait" "1" "$(crew_unread coord --wait 3 >/dev/null; echo $?)"
wait
check "wait wants seconds" "2" "$(crew_unread coord --wait x >/dev/null 2>&1; echo $?)"
check "unread takes no other flag" "2" "$(crew_unread coord --now >/dev/null 2>&1; echo $?)"
echo again | crew_send codex coord "Answer: again" >/dev/null
check "unread --peek --wait keeps the message unread" "1" "$(crew_unread coord --peek --wait 1 >/dev/null; crew_unread coord | grep -c '^# 0003\. codex to coord: Answer: again$')"

finish
