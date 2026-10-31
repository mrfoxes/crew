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
echo claude-idle.txt >"$tmp/screen1"
for m in claude:1 codex:2 agy:3 tess:4; do
    echo "tmux:%${m#*:}" >"$dir/panes/${m%:*}"
done
kind_record "$dir" claude claude
kind_record "$dir" codex codex
check "a pane with a prompt" "prompt" "$(live_state "$dir" codex)"
check "an agent back to its shell" "exited" "$(live_state "$dir" agy)"
check "a pane gone" "gone" "$(live_state "$dir" tess)"
check "no pane" "none" "$(live_state "$dir" nobody)"
check "an idle agent, at a first look" "idle" "$(live_state "$dir" claude)"
check "the same screen again" "idle" "$(live_state "$dir" claude)"
echo claude-idle-notice.txt >"$tmp/screen1"
check "a screen that changed" "working" "$(live_state "$dir" claude)"
echo codex-idle.txt >"$tmp/screen1"
check "an agent that says esc interrupts it" "working" "$(live_state "$dir" claude)"

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
check "a member's line" "codex     codex   proof    prompt   #187 step 3, the parser        0m 12.40" "$(printf '%s\n' "$frame" | sed -n 2p)"
check "a muted member's state" "1" "$(printf '%s\n' "$frame" | grep -c '^agy .* exited\*')"
check "a member with no status" "tess      -       -        gone     -                               - -" "$(printf '%s\n' "$frame" | grep '^tess')"
check "the lock" "1" "$(printf '%s\n' "$frame" | grep -cx 'lock: free')"
check "the relay" "1" "$(printf '%s\n' "$frame" | grep -cx 'relay: off')"
check "the last message" "1" "$(printf '%s\n' "$frame" | grep -c '^0001\. codex to claude: Review: the parser$')"
check "the last commit" "1" "$(printf '%s\n' "$frame" | grep -c 'Start the project$')"
check "live wants seconds" "2" "$(crew_board --live soon >/dev/null 2>&1; echo $?)"

finish
