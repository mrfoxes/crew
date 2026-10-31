#!/bin/sh
# Bringing a pane to the front: what each terminal is asked, and crew focus
# going to a member's pane and back.
#
#   sh test/run.sh focus

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

# tmux: the session, the window, the pane; a zoom let go, or made.
zoomed=0
tmux() {
    echo "$*" >>"$tmp/tmux.args"
    [ "$1" != display-message ] || echo "$zoomed"
}
asked() { : >"$tmp/tmux.args"; "$@"; grep -v '^display-message' "$tmp/tmux.args"; }
check "focus in tmux" "switch-client -t %4
select-window -t %4
select-pane -t %4" "$(asked term_focus tmux:%4)"
zoomed=1
check "focus in tmux lets a zoom go" "switch-client -t %4
select-window -t %4
select-pane -t %4
resize-pane -Z -t %4" "$(asked term_focus tmux:%4)"
zoomed=0
check "zoom in tmux" "resize-pane -Z -t %4" "$(asked term_zoom tmux:%4)"
zoomed=1
check "zoom in tmux zooms once" "" "$(asked term_zoom tmux:%4)"
# iTerm2: the window, the tab, and the session selected; no zoom.
osascript() { cat >"$tmp/osascript.in"; shift; echo "$*" >"$tmp/osascript.args"; }
term_focus iterm:X
check "focus in iTerm2 asks for the session" "X" "$(cat "$tmp/osascript.args")"
check "focus in iTerm2 selects the window, the tab, the session" "3" "$(grep -c -E 'tell (w|t|s) to select' "$tmp/osascript.in")"
check "zoom in iTerm2 says it cannot" "1" "$(term_zoom iterm:X 2>/dev/null; echo $?)"

# crew focus: a member's pane, and back to where it was run from.
git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
echo tmux:%4 >"$dir/panes/codex"
# The terminal's half is faked; term_focus and term_zoom stay crew's.
tmux_focus() { echo "focus tmux:$1"; }
tmux_zoom() { echo "zoom tmux:$1"; }
term_self() { echo tmux:%1; }
check "focus a member" "focus tmux:%4" "$(crew_focus codex)"
check "focus keeps where it came from" "tmux:%1" "$(cat "$dir/tmp/focus.from")"
check "focus and zoom" "focus tmux:%4
zoom tmux:%4" "$(crew_focus codex --zoom)"
check "focus a pane" "focus tmux:%9" "$(crew_focus tmux:%9)"
term_self() { echo tmux:%4; }
check "focus back" "focus tmux:%1" "$(crew_focus -)"
check "and back again" "tmux:%4" "$(cat "$dir/tmp/focus.from")"
check "focus one with no pane" "1" "$(crew_focus nobody >/dev/null 2>&1; echo $?)"
check "focus wants a name" "2" "$(crew_focus >/dev/null 2>&1; echo $?)"
check "focus knows only --zoom" "2" "$(crew_focus codex --big >/dev/null 2>&1; echo $?)"
rm "$dir/tmp/focus.from"
check "focus back with nowhere to go" "1" "$(crew_focus - >/dev/null 2>&1; echo $?)"

finish
