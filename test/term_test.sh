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

# Poke dispatches through the real terminal contract; only each terminal's
# type/key functions and the delay are faked, in a subshell so they cannot
# affect the later tests. Keep the bytes apart from the Return key.
poke() (
    tmux_type() { printf '%s' "$2" >"$tmp/poke.bytes"; }
    iterm_type() { printf '%s' "$2" >"$tmp/poke.bytes"; }
    tmux_key() { printf '%s\n' "$2" >>"$tmp/poke.keys"; }
    iterm_key() { printf '%s\n' "$2" >>"$tmp/poke.keys"; }
    sleep() { :; }
    rm -f "$tmp/poke.bytes" "$tmp/poke.keys"
    term_poke "$1" "$2" 2>"$tmp/poke.err"
    echo $?
)
poke_bytes() { od -An -tx1 "$tmp/poke.bytes" | tr -d ' \n'; }
for target in tmux:%1 iterm:X; do
    check "poke $target normalizes CR and LF" "0" "$(poke "$target" "$(printf 'a\rb\nc\r\nd')")"
    check "poke $target passes spaces to its terminal" "6120622063202064" "$(poke_bytes)"
    check "poke $target submits once after typing" "enter" "$(cat "$tmp/poke.keys")"

    literal=$(printf '%s' '"quotes" $dollar \backslash' " 'single'" ' café')
    check "poke $target accepts literal text" "0" "$(poke "$target" "$literal")"
    check "poke $target preserves every literal byte" "$literal" "$(cat "$tmp/poke.bytes")"

    for control in 001 011 033 037 177; do
        check "poke $target refuses control $control" "2" "$(poke "$target" "a$(printf "\\$control")b")"
        check "poke $target types nothing for control $control" "yes" "$([ ! -e "$tmp/poke.bytes" ] && [ ! -e "$tmp/poke.keys" ] && echo yes)"
        check "poke $target names key for control $control" "1" "$(grep -c 'crew key' "$tmp/poke.err")"
    done
done

# Spawning over a pane: tmux, faked, splits before it; a pane of the other
# terminal is refused before either is asked.
tmux() { echo "$*" >>"$tmp/tmux.args"; [ "$1" != split-window ] || echo %5; }
check "spawn above in tmux" "tmux:%5" "$(TMUX=1 term_spawn above true tmux:%3)"
check "spawn above in tmux splits over the pane" "split-window -d -v -b -t %3 -P -F #{pane_id}" "$(sed -n 1p "$tmp/tmux.args")"
check "spawn above in tmux refuses an iTerm2 pane" "1" "$(TMUX=1 term_spawn above true iterm:X 2>/dev/null; echo $?)"
check "spawn above in iTerm2 refuses a tmux pane" "1" "$(TMUX='' term_spawn above true tmux:%3 2>/dev/null; echo $?)"
# Beside a pane: tmux splits it side by side, then spreads the row out.
: >"$tmp/tmux.args"
check "spawn beside in tmux" "tmux:%5" "$(TMUX=1 term_spawn beside true tmux:%3)"
check "spawn beside in tmux splits the pane side by side, then evens the row" "split-window -d -h -t %3 -P -F #{pane_id}
select-layout -E -t %5" "$(sed -n 1,2p "$tmp/tmux.args")"
check "spawn beside in tmux refuses an iTerm2 pane" "1" "$(TMUX=1 term_spawn beside true iterm:X 2>/dev/null; echo $?)"
check "spawn beside in iTerm2 refuses a tmux pane" "1" "$(TMUX='' term_spawn beside true tmux:%3 2>/dev/null; echo $?)"
# The focus stays where it was: tmux opens a window, or splits a pane, with
# -d; iTerm2 gives it back, by unique id, to the pane that held it in the
# anchor's tab, then to the tab and the pane that held it in the window.
tmux() { echo "$*" >>"$tmp/tmux.args"; case $1 in new-window | split-window) echo %5 ;; esac; }
: >"$tmp/tmux.args"
TMUX=1 term_spawn tab true >/dev/null
TMUX=1 term_spawn below true tmux:%3 >/dev/null
TMUX=1 term_spawn split true >/dev/null
check "spawn in tmux leaves the focus where it was" "3" "$(grep -c -E '^(new-window|split-window) -d ' "$tmp/tmux.args")"
osascript() { cat >"$tmp/osascript.in"; echo Y; }
check "spawn in iTerm2" "iterm:Y" "$(TMUX='' term_spawn below true iterm:X)"
check "spawn in iTerm2 keeps who held the focus" "2" "$(grep -c -E 'set (fid|wid) to unique id of current session of (t|current tab of w)$' "$tmp/osascript.in")"
check "spawn in iTerm2 gives it back, the window's tab too" "1" "$(grep -c 'tell t2 to select' "$tmp/osascript.in")"
unset -f osascript

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
# shellcheck disable=SC2154 # set by lib/term-tmux.sh
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
# A session crew never tinted gives missing value for the variable, not "".
osascript() { cat >"$tmp/osascript.in"; }
term_color iterm:X '#d97757'
check "color in iTerm2 of a session never tinted" "1" "$(grep -c 'if saved is missing value then set saved to ""' "$tmp/osascript.in")"
check "name of no pane" "1" "$(term_name nowhere x 2>/dev/null; echo $?)"

# Closing a pane: tmux kills it, iTerm2 closes its session; a word that is
# no pane closes nothing.
tmux() { echo "tmux $*"; }
check "close in tmux" "tmux kill-pane -t %7" "$(term_close tmux:%7)"
osascript() { cat >"$tmp/close.script"; }
term_close iterm:X
check "close in iTerm2" "1" "$(grep -c 'tell s to close' "$tmp/close.script")"
check "close of no pane" "1" "$(term_close nowhere 2>/dev/null; echo $?)"

# What runs in the foreground of a tty: any program other than a shell, or
# the named process when one is given; a tty that cannot be read runs nothing.
ps() { cat "$tmp/ps.out"; }
printf 'Ss   -zsh\nS+   /opt/bin/claude\n' >"$tmp/ps.out"
check "running finds an agent in the foreground" "0" "$(term_running /dev/ttys001; echo $?)"
check "running finds the named agent in the foreground" "0" "$(term_running /dev/ttys001 claude; echo $?)"
check "running rejects an agent of another kind" "1" "$(term_running /dev/ttys001 codex; echo $?)"
printf 'S+   -zsh\n' >"$tmp/ps.out"
check "running rejects a shell" "1" "$(term_running /dev/ttys001; echo $?)"
check "running with a process rejects a shell" "1" "$(term_running /dev/ttys001 claude; echo $?)"
printf 'Ss   -zsh\nS+   vim\n' >"$tmp/ps.out"
check "running with a process rejects an editor" "1" "$(term_running /dev/ttys001 claude; echo $?)"
printf 'Ss   -zsh\nS    claude\nS+   vim\n' >"$tmp/ps.out"
check "running rejects a backgrounded agent behind an editor" "1" "$(term_running /dev/ttys001 claude; echo $?)"
printf 'Ss   /usr/bin/login\nS    -fish\nS+   claude\nS+   caffeinate\n' >"$tmp/ps.out"
check "running accepts a Claude pane keeping awake with caffeinate" "0" "$(term_running /dev/ttys001 claude; echo $?)"
printf 'Ss   -zsh\nS+   claude\nS+   vim\n' >"$tmp/ps.out"
check "running rejects an agent sharing the foreground with an editor" "1" "$(term_running /dev/ttys001 claude; echo $?)"
ps() { return 1; }
check "running rejects a tty that cannot be read" "1" "$(term_running /dev/ttys001 claude; echo $?)"

# Listing panes: inside tmux iTerm2 is not asked, as it is only the window
# tmux runs in, unless a pane of its own is; outside tmux both are. osascript
# records each call, says iTerm2 runs, and lists one session. The terminal
# functions faked above come back first.
. "$CREW_HOME/lib/term.sh"
osascript() {
    echo "osascript $*" >>"$tmp/list.calls"
    case "$*" in
    *'is running'*) echo true ;;
    *)
        cat >"$tmp/list.script"
        printf 'iterm:A\t/dev/ttys009\tone\n'
        ;;
    esac
}
tmux() { printf 'tmux:%%1\t/dev/ttys001\tmain:0.0 sh\n'; }
: >"$tmp/list.calls"
check "list inside tmux" "tmux:%1" "$(TMUX=1 term_list | cut -f1)"
check "list inside tmux asks iTerm2 nothing" "" "$(cat "$tmp/list.calls")"
check "a tmux pane gone, inside tmux, asks iTerm2 nothing" "1 0" "$(TMUX=1 term_gone tmux:%1; echo $?) $(wc -l <"$tmp/list.calls" | tr -d ' ')"
check "tty of a tmux pane outside tmux asks iTerm2 nothing" "/dev/ttys001 0" "$(TMUX='' term_tty tmux:%1) $(wc -l <"$tmp/list.calls" | tr -d ' ')"
check "tty of an iTerm2 pane inside tmux asks iTerm2" "/dev/ttys009" "$(TMUX=1 term_tty iterm:A)"
check "list outside tmux takes both" "iterm:A tmux:%1" "$(TMUX='' term_list | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
check "list iTerm2 within a timeout" "osascript - 5" "$(grep -v 'is running' "$tmp/list.calls" | tail -n 1)"
check "list iTerm2 with AppleScript's timeout around the tell" "1" "$(grep -c 'with timeout of (item 1 of argv as integer) seconds' "$tmp/list.script")"
# An iTerm2 that does not answer in time lists nothing and says so.
osascript() {
    case "$*" in
    *'is running'*) echo true ;;
    *)
        cat >/dev/null
        return 1
        ;;
    esac
}
check "an iTerm2 that does not answer lists nothing" "0 " "$(iterm_list 2>/dev/null; echo "$? $(iterm_list 2>/dev/null)")"
check "an iTerm2 that does not answer says so" "crew: iTerm2 did not list its sessions within 5 seconds" "$(iterm_list 2>&1 >/dev/null)"
check "list outside tmux goes on with tmux when iTerm2 does not answer" "tmux:%1" "$(TMUX='' term_list 2>/dev/null | cut -f1)"
unset -f osascript tmux

finish
