#!/bin/sh
# The live board: what each member's pane shows, the members in the order
# of their tabs, and a frame, with the terminal faked.
#
#   sh test/run.sh live

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "Start the project"
cd "$tmp/repo" || exit 1
dir=$(crew_init)

# Panes %1 (idle claude), %2 (codex at a prompt), %3 (back to a shell),
# %4 (gone): the terminal lists %1 to %3.
term_tty() {
    case "$1" in
    tmux:%1 | tmux:%2 | tmux:%3) echo "/dev/ttys00${1#tmux:%}" ;;
    *) return 1 ;;
    esac
}
term_running() { [ "$1" != /dev/ttys003 ]; }
term_read() {
    case "$1" in
    tmux:%1) cat "$here/fixtures/$(cat "$tmp/screen1")" ;;
    tmux:%2) cat "$here/fixtures/codex-run.txt" ;;
    esac
}
term_read_styled() { term_read "$@"; }
echo claude-idle.txt >"$tmp/screen1"
for m in claude:1 codex:2 agy:3 tess:4; do
    echo "tmux:%${m#*:}" >"$dir/panes/${m%:*}"
done
kind_record "$dir" claude claude
kind_record "$dir" codex codex
kind_record "$dir" agy agy
check "a pane with a prompt" "dialog" "$(live_state "$dir" codex)"
check "an agent back to its shell" "exited" "$(live_state "$dir" agy)"
check "a pane gone" "gone" "$(live_state "$dir" tess)"
check "no pane" "none" "$(live_state "$dir" nobody)"
check "an idle agent, at a first look" "idle" "$(live_state "$dir" claude)"
check "the same screen again" "idle" "$(live_state "$dir" claude)"
echo claude-idle-notice.txt >"$tmp/screen1"
check "a screen that changed" "working" "$(live_state "$dir" claude)"
echo claude-working.txt >"$tmp/screen1"
check "an agent in a turn" "working" "$(live_state "$dir" claude)"
check "still in it" "working" "$(live_state "$dir" claude)"
echo claude-typed.txt >"$tmp/screen1"
check "text on the input line" "typed" "$(live_state "$dir" claude)"

# The members: each tab's, as the tab lists them, then the others by name.
tab_add "$dir" proof codex
tab_add "$dir" proof claude
tab_add "$dir" proof tmux:%9
printf 'Agent: zed\n' >"$dir/status/zed.md"
check "the members in the board's order" "codex claude agy tess zed" "$(live_members "$dir" | tr '\n' ' ' | sed 's/ $//')"

# A frame: a line a member, then the lock, the relay, the messages, git.
echo claude-idle.txt >"$tmp/screen1"
printf 'Agent: codex\nIssue: #187 step 3, the parser\n' >"$dir/status/codex.md"
crew_mute agy >/dev/null
echo x | crew_send codex claude "Review: the parser" >/dev/null
printf 'codex 12.40\n' >"$dir/tmp/live.cost"
gh() { return 1; }
frame=$(live_frame "$dir")
check "the frame's head" "member    kind    tab      state    issue                         age spent" "$(printf '%s\n' "$frame" | sed -n 1p)"
check "a member's line" "codex     codex   proof    dialog   #187 step 3, the parser        0m 12.40" "$(printf '%s\n' "$frame" | sed -n 2p)"
check "a member with unread has + on its state" "1" "$(printf '%s\n' "$frame" | grep -c '^claude .* working+')"
check "a muted member's state" "1" "$(printf '%s\n' "$frame" | grep -c '^agy .* exited\*')"
check "a member with no status" "tess      -       -        gone     -                               - -" "$(printf '%s\n' "$frame" | grep '^tess')"
check "the lock" "1" "$(printf '%s\n' "$frame" | grep -cx 'lock: free')"
check "the relay" "1" "$(printf '%s\n' "$frame" | grep -cx 'relay: off')"
check "the last message" "1" "$(printf '%s\n' "$frame" | grep -c '^0001\. codex to claude: Review: the parser$')"
check "the last commit" "1" "$(printf '%s\n' "$frame" | grep -c 'Start the project$')"
(crew_unread claude >/dev/null)
echo x | crew_send codex claude "Pushed: 1234567 the parser" >/dev/null
check "a reviewer with a commit waiting has ? on its state" "1" "$(live_frame "$dir" | grep -c '^claude .* idle?+')"
(crew_unread claude >/dev/null)
check "reading clears + while ? stays" "1" "$(live_frame "$dir" | grep -c '^claude .* idle? ')"
echo x | crew_send claude codex "Review: 1234567 looks good" >/dev/null
check "an answered review clears ?" "1" "$(live_frame "$dir" | grep -c '^claude .* idle ')"
echo x | crew_send claude coord "Idle: nothing left" >/dev/null 2>&1
check "idle with nothing to do is free" "1" "$(live_frame "$dir" | grep -c '^claude .* free ')"
check "live wants seconds" "2" "$(crew_board --live soon >/dev/null 2>&1; echo $?)"

# The board's reviews section: a push waiting, one answered by its reviewer
# with a prefix of 7 or more, one answered by the wrong member, and a short
# hash that does not answer; and status with empty non-tty stdin.
check "status with empty stdin prints and keeps the file" "$(printf 'Agent: codex\nIssue: #187 step 3, the parser')" "$(crew_status codex </dev/null)"
reviews() { crew_board 1 | sed -n '/^== reviews/,/^$/p'; }
check "no push, no reviews section" "0" "$(crew_board 1 | grep -c '^== reviews')"
echo stat | crew_send agy claude "Pushed: 123456789abc first slice" >/dev/null
echo stat | crew_send claude codex "Pushed: fedcba987654 second slice" >/dev/null
echo stat | crew_send agy claude "Pushed: abcdef123456 third slice" >/dev/null
check "waiting pushes on the board" "== reviews
123456789abc first slice (agy to claude, 0 min ago)
fedcba987654 second slice (claude to codex, 0 min ago)
abcdef123456 third slice (agy to claude, 0 min ago)" "$(reviews)"
echo ok | crew_send claude agy "Review: 1234567, looks good" >/dev/null
echo wrong | crew_send agy claude "Review: fedcba987654, wrong reviewer" >/dev/null
echo short | crew_send claude agy "Review: abcdef, hash too short" >/dev/null
check "answered push leaves the board; wrong member and short hash stay" "== reviews
fedcba987654 second slice (claude to codex, 0 min ago)
abcdef123456 third slice (agy to claude, 0 min ago)" "$(reviews)"
echo "fedcba987 clean" | crew_send codex claude "Review: second slice" >/dev/null
echo ok | crew_send claude agy "Review: abcdef1, clean" >/dev/null
check "all pushes answered, no reviews section" "0" "$(crew_board 1 | grep -c '^== reviews')"
echo stat | crew_send agy all "Pushed: abcdef7 broadcast" >/dev/null
echo ok | crew_send claude agy "Review: abcdef7 clean" >/dev/null
check "a broadcast push answered by any reviewer leaves the board" "0" "$(crew_board 1 | grep -c '^== reviews')"

finish
