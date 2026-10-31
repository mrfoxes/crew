#!/bin/sh
# The terminals' tests: keys, opening a pane next to another, and moving
# one, with tmux and osascript faked so that no live pane is touched.
#
#   sh test/run.sh term

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

# Keys, as tmux gets them.
tmux() { echo "tmux $*"; }
check "key alt-m" "tmux send-keys -t %1 M-m" "$(term_key tmux:%1 alt-m)"
check "key ctrl-c" "tmux send-keys -t %1 C-c" "$(term_key tmux:%1 ctrl-c)"
check "key y" "tmux send-keys -t %1 -l -- y" "$(term_key tmux:%1 y)"
check "key delete" "tmux send-keys -t %1 DC" "$(term_key tmux:%1 delete)"
check "key unknown" "2" "$(term_key tmux:%1 f13 2>/dev/null; echo $?)"

# Spawning over a pane: tmux, faked, splits before it; a pane of the other
# terminal is refused before either is asked.
tmux() { echo "$*" >>"$tmp/tmux.args"; [ "$1" != split-window ] || echo %5; }
check "spawn above in tmux" "tmux:%5" "$(TMUX=1 term_spawn above true tmux:%3)"
check "spawn above in tmux splits over the pane" "split-window -v -b -t %3 -P -F #{pane_id}" "$(sed -n 1p "$tmp/tmux.args")"
check "spawn above in tmux refuses an iTerm2 pane" "1" "$(TMUX=1 term_spawn above true iterm:X 2>/dev/null; echo $?)"
check "spawn above in iTerm2 refuses a tmux pane" "1" "$(TMUX='' term_spawn above true tmux:%3 2>/dev/null; echo $?)"
# Beside a pane: tmux splits it side by side, then spreads the row out.
: >"$tmp/tmux.args"
check "spawn beside in tmux" "tmux:%5" "$(TMUX=1 term_spawn beside true tmux:%3)"
check "spawn beside in tmux splits the pane side by side, then evens the row" "split-window -h -t %3 -P -F #{pane_id}
select-layout -E -t %5" "$(sed -n 1,2p "$tmp/tmux.args")"
check "spawn beside in tmux refuses an iTerm2 pane" "1" "$(TMUX=1 term_spawn beside true iterm:X 2>/dev/null; echo $?)"
check "spawn beside in iTerm2 refuses a tmux pane" "1" "$(TMUX='' term_spawn beside true tmux:%3 2>/dev/null; echo $?)"

# Moving a pane: tmux joins it to the other, the focus left where it is,
# beside it (the row evened out), under it, or over it; panes of two
# terminals, or a pane and itself, are refused before either is asked.
# iTerm2 is faked too, so that a slip moves no live pane.
osascript() { echo "$*" >>"$tmp/osascript.args"; return 1; }
moved() { : >"$tmp/tmux.args"; term_move "$@"; cat "$tmp/tmux.args"; }
check "move beside in tmux" "join-pane -d -h -s %4 -t %3
select-layout -E -t %4" "$(moved tmux:%4 beside tmux:%3)"
check "move below in tmux" "join-pane -d -v -s %4 -t %3" "$(moved tmux:%4 below tmux:%3)"
check "move above in tmux" "join-pane -d -v -b -s %4 -t %3" "$(moved tmux:%4 above tmux:%3)"
check "move refuses panes of two terminals" "" "$(moved tmux:%4 beside iterm:X 2>/dev/null)"
check "move refuses panes of two terminals, failing" "1" "$(term_move iterm:X below tmux:%3 2>/dev/null; echo $?)"
check "move refuses a pane next to itself" "" "$(moved tmux:%4 above tmux:%4 2>/dev/null)"
check "move refuses a pane next to itself, failing" "1" "$(term_move tmux:%4 above tmux:%4 2>/dev/null; echo $?)"
check "move wants a place it knows" "2" "$(term_move tmux:%4 left tmux:%3 2>/dev/null; echo $?)"
tmux() { return 1; }
check "move fails when tmux does" "1" "$(term_move tmux:%4 beside tmux:%3 2>/dev/null; echo $?)"
check "move in tmux asks no iTerm2" "" "$(cat "$tmp/osascript.args" 2>/dev/null)"
unset -f osascript

# Naming and coloring a pane. tmux keeps both in the pane's options and
# shows them in its border, which it turns on for the pane's window.
tmux() { echo "$*" >>"$tmp/tmux.args"; }
named() { : >"$tmp/tmux.args"; "$@"; cat "$tmp/tmux.args"; }
check "name in tmux" "set-option -p -t %4 @crew_name claude2
set-option -w -t %4 pane-border-status top
set-option -w -t %4 pane-border-format $tmux_border" "$(named term_name tmux:%4 claude2)"
check "name off in tmux" "set-option -p -u -t %4 @crew_name" "$(named term_name tmux:%4 "")"
check "color in tmux" "set-option -p -t %4 @crew_color #d97757" "$(named term_color tmux:%4 '#d97757')"
check "color off in tmux" "set-option -p -u -t %4 @crew_color" "$(named term_color tmux:%4)"
# iTerm2 shows the name as the session's badge, set by the escape sequence
# written to its tty, and tints its background through osascript.
term_tty() { echo "$tmp/tty"; }
term_name iterm:X claude2
check "name in iTerm2" "$(printf '\033]1337;SetBadgeFormat=%s\007' "$(printf claude2 | base64)")" "$(cat "$tmp/tty")"
term_name iterm:X ""
check "name off in iTerm2" "$(printf '\033]1337;SetBadgeFormat=\007')" "$(cat "$tmp/tty")"
osascript() { shift; echo "$*" >"$tmp/osascript.args"; }
term_color iterm:X '#d97757'
check "color in iTerm2" "X 217 119 87" "$(cat "$tmp/osascript.args")"
term_color iterm:X
check "color off in iTerm2" "X" "$(cat "$tmp/osascript.args" | sed 's/ *$//')"
check "name of no pane" "1" "$(term_name nowhere x 2>/dev/null; echo $?)"

finish
