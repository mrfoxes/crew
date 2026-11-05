#!/bin/sh
# The screen tests: what screen_of says of every captured screen of
# test/fixtures/, the text on an input line with its placeholder and dim
# suggestions taken off, the marks of a finished compact, and screen_state
# over a pane whose terminal is faked: no pane is read.
#
#   sh test/run.sh screen

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

fixtures=$CREW_HOME/test/fixtures
of() { screen_of "$1" <"$fixtures/$2.txt"; }

# Every captured screen, by kind: what one look says.
while read -r kind fixture want; do
    check "$fixture is $want" "$want" "$(of "$kind" "$fixture")"
done <<'EOF'
claude claude-idle idle
claude claude-idle-notice idle
claude claude-after-turn idle
claude claude-shell shell
claude claude-cleared shell
claude claude-compacted shell
claude claude-working working
claude claude-compacting working
claude claude-typed typed
claude claude-slash-menu typed
claude claude-asks typed
claude claude-run dialog
claude claude-edit dialog
claude claude-fetch dialog
claude claude-requires-approval dialog
claude claude-trust dialog
codex codex-after-turn idle
codex codex-compacted idle
codex codex-new idle
codex codex-working working
codex codex-compacting working
codex codex-idle working
codex codex-queued working
codex codex-typed typed
codex codex-slash-menu typed
codex codex-run dialog
codex codex-wrapped dialog
codex codex-trust dialog
agy agy-idle idle
agy agy-after-turn idle
agy agy-cleared idle
agy agy-compacted idle
agy agy-working working
agy agy-compacting working
agy agy-typed typed
agy agy-trust dialog
claude claude-idle-styled idle
claude claude-typed-styled typed
codex codex-idle-styled idle
codex codex-typed-styled typed
other other unknown
EOF

# A line of transcript with "…" and a parenthesis is no spinner; a spinner's
# parenthesis holds its timer, after a hook's name too.
check "a line of transcript is not a turn" "1" "$(printf '⏺ Wait… (see above)\n' | screen_working claude; echo $?)"
check "a spinner running a hook is a turn" "0" "$(printf '· Purring… (running PostToolUse hook · 2s · ↓ 18 tokens)\n' | screen_working claude; echo $?)"

# The input line's text: what was typed, never the placeholder.
check "claude's typed text" "half a line" "$(screen_input claude <"$fixtures/claude-typed.txt")"
check "codex's typed text" "half a line" "$(screen_input codex <"$fixtures/codex-typed.txt")"
check "agy's typed text" "half a line" "$(screen_input agy <"$fixtures/agy-typed.txt")"
check "claude's placeholder is no text" "" "$(screen_input claude <"$fixtures/claude-idle.txt")"
check "codex's placeholder is no text" "" "$(screen_input codex <"$fixtures/codex-after-turn.txt")"
check "a screen with no input line fails" "1" "$(printf 'Resume this session with:\nsh-3.2$\n' | screen_input claude >/dev/null; echo $?)"

# Read with its styles (tmux capture-pane -e, as captured from Claude Code
# 2.1.318 and Codex 0.166.0): dim text is a placeholder or a suggestion.
esc=$(printf '\033')
mark=$(printf '\342\235\257\302\240')
rule='────────────────────────────────────────'
styled() { printf '%s\n%s\n%s\n  [CAVEMAN]\n' "$rule" "$1" "$rule"; }
check "a dim suggestion is no text" "idle" "$(styled "${esc}[39m${mark}${esc}[2myes, proceed${esc}[0m" | screen_of claude)"
check "a dim placeholder is no text" "idle" "$(styled "${esc}[39m${mark}${esc}[2mTry \"refactor <filepath>\"${esc}[0m" | screen_of claude)"
check "text not dim is typed" "typed" "$(styled "${esc}[39m${mark}half a line" | screen_of claude)"
check "codex's bold mark and dim placeholder" "idle" "$(styled "${esc}[1m›${esc}[0m ${esc}[2mAsk Codex to do anything${esc}[0m" | screen_of codex)"
check "ESC[22m is not dim" "typed" "$(styled "${esc}[39m${mark}${esc}[22mtyped${esc}[0m" | screen_of claude)"
check "a truecolor whose numbers hold a 2 is not dim" "hello world" "$(styled "${esc}[39m${mark}${esc}[38;2;200;100;50mhello world" | screen_input claude)"
check "256-color green, 38;5;2, is not dim" "hello world" "$(styled "${esc}[39m${mark}${esc}[38;5;2mhello world" | screen_input claude)"
check "a background color then dim is dim" "" "$(styled "${esc}[39m${mark}${esc}[48;5;255;2msuggested${esc}[0m" | screen_input claude)"
check "dim ends at ESC[0m" "typed" "$(styled "${esc}[39m${mark}${esc}[2mghost${esc}[0mtyped" | screen_input claude)"

# The marks of a finished compact, one each.
check "claude's compacted mark" "1" "$(screen_compacted claude <"$fixtures/claude-compacted.txt")"
check "codex's compacted mark" "1" "$(screen_compacted codex <"$fixtures/codex-compacted.txt")"
check "agy's compacted mark" "1" "$(screen_compacted agy <"$fixtures/agy-compacted.txt")"
check "none while compacting" "0 0 0" "$(screen_compacted claude <"$fixtures/claude-compacting.txt") $(screen_compacted codex <"$fixtures/codex-compacting.txt") $(screen_compacted agy <"$fixtures/agy-compacting.txt")"

# screen_state over a faked terminal: the screens are files, and the second
# look reads the file the first look's pause names.
git init -q "$tmp/repo"
git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "Start the project"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
term_tty() { [ "$1" != tmux:%gone ] && echo /dev/ttys001; }
term_running() { [ ! -e "$tmp/exited" ]; }
term_read_styled() { cat "$tmp/screen"; }
screen_pause() { [ ! -f "$tmp/next" ] || cp "$tmp/next" "$tmp/screen"; }
pane() {
    echo "$2" >"$dir/panes/$1"
    kind_record "$dir" "$1" "$3"
}
look() {
    cp "$fixtures/$1.txt" "$tmp/screen"
    rm -f "$tmp/next"
    [ -z "${2:-}" ] || cp "$fixtures/$2.txt" "$tmp/next"
    screen_state "$dir" ann
}
check "no pane" "none" "$(screen_state "$dir" ann)"
pane ann tmux:%1 claude
check "an idle screen that stays" "idle" "$(look claude-idle)"
check "an idle screen that moves is working" "working" "$(look claude-idle claude-after-turn)"
check "a background shell" "shell" "$(look claude-shell)"
check "working" "working" "$(look claude-working)"
check "typed" "typed" "$(look claude-typed)"
check "a dialog" "dialog" "$(look claude-run)"
: >"$tmp/exited"
check "no agent in the foreground" "exited" "$(look claude-idle)"
rm "$tmp/exited"
pane ann tmux:%gone claude
check "a pane gone" "gone" "$(look claude-idle)"
pane ann tmux:%1 other
check "a kind with no input mark" "unknown" "$(look claude-idle)"

finish
