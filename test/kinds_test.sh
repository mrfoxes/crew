#!/bin/sh
# The kinds' tests: share/kinds read and overridden, a kind read from a
# spawn line and from the agent a join runs under, and each member's kind
# recorded, shown, and forgotten.
#
#   sh test/run.sh kinds

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

check "kinds" "claude codex agy" "$(kinds_names | tr '\n' ' ' | sed 's/ $//')"
check "a field" "y" "$(kind_field codex approve)"
check "a field that is none" "" "$(kind_field agy approve)"
check "the idle mark" "❯" "$(kind_field claude idle)"
check "a kind crew does not know" "" "$(kind_field vim approve)"
check "a field crew does not know" "" "$(kind_field codex smell)"
check "other is a kind" "0" "$(kind_known other; echo $?)"
check "an unknown kind" "1" "$(kind_known vim; echo $?)"

# The owner's kinds, then a crew's own, add kinds and replace them.
mkdir -p "$XDG_CONFIG_HOME/crew"
printf '# mine\ncodex codex CODEX_THREAD_ID › enter #000000\nmycc mycc - ❯ enter #111111\n' >"$XDG_CONFIG_HOME/crew/kinds"
check "the owner's line replaces one" "enter" "$(kind_field codex approve)"
check "the owner's kind is added, after the others" "claude codex agy mycc" "$(kinds_names | tr '\n' ' ' | sed 's/ $//')"
mkdir -p "$tmp/crew/seq"
printf 'codex codex CODEX_THREAD_ID › n #222222\n' >"$tmp/crew/kinds"
check "the crew's line replaces the owner's" "n" "$(CREW_DIR=$tmp/crew kind_field codex approve)"
check "a crew's line leaves the rest" "#111111" "$(CREW_DIR=$tmp/crew kind_field mycc color)"
rm -r "$XDG_CONFIG_HOME/crew" "$tmp/crew"

# The kind a spawn line runs.
while IFS='|' read -r want line; do
    check "line: $line" "$want" "$(kind_of_line "$line")"
done <<'EOF2'
claude|claude --model 'x y'
codex|cd sub && codex
codex|env CREW_DIR=/x /opt/homebrew/bin/codex --yolo
agy|agy -i 'ask claude'
claude|(cd /p/claude-proj; claude)
claude|'claude' --resume
|vim notes.md
|claude-proj
EOF2

# The agent a join runs under: the nearest ancestor that is one, its
# variable when ps cannot tell.
ps() {
    case "$*" in
    "-o comm= -p $$") echo /bin/sh ;;
    "-o ppid= -p $$") echo 300 ;;
    "-o comm= -p 300") echo /Users/x/.local/bin/agy ;;
    "-o ppid= -p 300") echo 1 ;;
    *) return 1 ;;
    esac
}
check "self from an ancestor" "agy" "$(kind_of_self)"
check "an ancestor before a variable" "agy" "$(CLAUDECODE=1 kind_of_self)"
ps() { return 1; }
check "self from a variable" "codex" "$(CODEX_THREAD_ID=abc kind_of_self)"
check "self from the first variable set" "claude" "$(CLAUDECODE=1 CODEX_THREAD_ID=abc kind_of_self)"
check "self from nothing" "" "$(kind_of_self)"

# The input line of an idle agent, near the bottom of its screen, and
# none on a screen of another kind or of no kind.
drawn() { kind_drawn "$1" <"$here/fixtures/$2.txt" && echo yes || echo no; }
check "claude's input line" "yes" "$(drawn claude claude-idle)"
check "claude's input line with a notice" "yes" "$(drawn claude claude-idle-notice)"
check "codex's input line" "yes" "$(drawn codex codex-idle)"
check "agy's input line" "yes" "$(drawn agy agy-idle)"
check "another kind's input line" "no" "$(drawn claude codex-idle)"
check "a kind with no mark" "no" "$(drawn other claude-idle)"
check "a screen with no input line" "no" "$(drawn codex other)"
# A menu's cursor is drawn the same way: invite reads the prompt first.
check "a prompt's cursor" "yes" "$(drawn codex codex-run)"

# A member's kind: spawn records it, join records the one it runs under or
# keeps the spawned one, leave forgets it.
git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
term_spawn() { echo tmux:%9; }
term_name() { echo "name $1 $2" >>"$tmp/labels"; }
term_color() { echo "color $1 ${2:-}" >>"$tmp/labels"; }
labels() { cat "$tmp/labels"; rm -f "$tmp/labels"; }
crew_spawn agy 'cd sub && codex' >/dev/null
check "spawn records the kind of its command" "codex" "$(kind_member "$dir" agy)"
check "spawn names the pane and colors it for its kind" "name tmux:%9 agy
color tmux:%9 #10a37f" "$(labels)"
(CREW_COLOR=0 crew_spawn agy 'cd sub && codex' >/dev/null)
check "spawn with CREW_COLOR=0 names the pane only" "name tmux:%9 agy
color tmux:%9 " "$(labels)"
crew_spawn agy --kind agy codex >/dev/null
check "spawn records the kind given" "agy" "$(kind_member "$dir" agy)"
rm -f "$tmp/labels"
crew_spawn agy vim >/dev/null
check "spawn of no kind records other" "other" "$(kind_member "$dir" agy)"
check "a pane of no kind gets no color" "name tmux:%9 agy
color tmux:%9 " "$(labels)"
check "spawn refuses a kind crew does not know" "2" "$(crew_spawn agy --kind vim vim >/dev/null 2>&1; echo $?)"
check "spawn names the kinds it knows" "crew: 'vim' is not a kind crew knows: claude codex agy other" "$(crew_spawn agy --kind vim vim 2>&1 >/dev/null)"
crew_spawn agy claude >/dev/null
term_list() { printf 'tmux:%%9\t/dev/ttys009\tclaude\n'; }
term_self() { echo tmux:%9; }
kind_of_self() { :; }
check "join keeps the spawned kind" "claude" "$(crew_join agy >/dev/null; kind_member "$dir" agy)"
kind_of_self() { echo agy; }
rm -f "$tmp/labels"
check "join records the kind it runs under" "agy" "$(crew_join agy >/dev/null; kind_member "$dir" agy)"
check "join names its pane and colors it" "name tmux:%9 agy
color tmux:%9 #4285f4" "$(labels)"
check "join says the kind" "You are agy, of kind agy, in the crew at $dir, in the pane tmux:%9: a message to you is typed into it." "$(crew_join agy | sed -n 1p)"
kind_of_self() { :; }
check "join of no kind records other" "other" "$(crew_join codex --pane tmux:%9 >/dev/null; kind_member "$dir" codex)"
check "panes show the kind" "agy      agy     tmux:%9" "$(rm "$dir/panes/codex"; crew_panes | cut -c1-24)"
printf 'Agent: agy\n' >"$dir/status/agy.md"
check "board shows the kind" "1" "$(crew_board 1 | grep -c '^== agy (agy, tmux:%9, 0 min ago)$')"
rm -f "$tmp/labels"
crew_leave agy >/dev/null
check "leave forgets the kind" "" "$(kind_member "$dir" agy)"
check "leave takes the name and color off a pane still there" "name tmux:%9 
color tmux:%9 " "$(labels)"
check "board without a kind" "1" "$(crew_board 1 | grep -c '^== agy (no pane, 0 min ago)$')"

finish
