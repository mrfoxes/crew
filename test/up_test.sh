#!/bin/sh
# Bringing a crew up from its Crewfile: the file read and refused, presets,
# a dry run, the first crew up, and the next ones, with the terminal faked.
#
#   sh test/run.sh up

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
kind_of_self() { :; }

cat >"$dir/Crewfile" <<'EOF2'
# the coordinator's tab, then two lanes
tab main layout=main watch board
tab proof layout=table
member claude   reviewer=claude2 -- claude --model claude-opus-5-5 --effort high
member claude2  reviewer=claude clone cache=.lake -- cd sub && claude   # not a comment: after --
tab runtime layout=grid
member agy      reviewer=codex mute budget=20 -- agy
member codex    kind=codex reviewer=agy mute noinvite budget=60 -- codex
member tess     # started and joined by hand
EOF2
check "the Crewfile read" "tab	main	main	1	1
tab	proof	table	0	0
member	proof	claude	-	0	1	0	-	claude2	-	claude --model claude-opus-5-5 --effort high
member	proof	claude2	-	0	1	1	.lake	claude	-	cd sub && claude   # not a comment: after --
tab	runtime	grid	0	0
member	runtime	agy	-	1	1	0	-	codex	20	agy
member	runtime	codex	codex	1	0	0	-	agy	60	codex
member	runtime	tess	-	0	1	0	-	-	-	-" "$(crewfile_read "$dir/Crewfile")"
check "a member's reviewer" "claude2" "$(crewfile_get "$dir" claude reviewer)"
check "a member's budget" "60" "$(crewfile_get "$dir" codex budget)"
check "a member's tab" "runtime" "$(crewfile_get "$dir" agy tab)"
check "a member with none" "" "$(crewfile_get "$dir" tess budget)"
check "a member not there" "" "$(crewfile_get "$dir" nobody reviewer)"

# What the reader refuses, each with its line, and nothing printed then.
refused() { printf '%s\n' "$@" >"$tmp/bad"; crewfile_read "$tmp/bad" 2>&1 >/dev/null | sed "s|$tmp/bad|F|"; }
check "a member before a tab" "crew: F:1: a member comes after a tab" "$(refused 'member a -- x')"
check "a word crew does not know" "crew: F:2: a line is a tab or a member, not lane" "$(refused 'tab t' 'lane x')"
check "a tab's option" "crew: F:1: a tab takes layout=, watch, and board, not mute" "$(refused 'tab t mute')"
check "a member's option" "crew: F:2: a member takes kind=, mute, noinvite, clone, cache=, reviewer=, and budget=, not watch" "$(refused 'tab t' 'member a watch')"
check "a layout crew does not know" "crew: F:1: layout zigzag is not table, grid, main, or <columns>x<rows>" "$(refused 'tab t layout=zigzag')"
check "a name crew does not take" "crew: F:2: a member needs a name: lower-case letters, digits, and dashes, not all or owner" "$(refused 'tab t' 'member Ada')"
check "a member twice" "crew: F:3: member a is there twice" "$(refused 'tab t' 'member a' 'member a')"
check "a tab twice" "crew: F:2: tab t is there twice" "$(refused 'tab t' 'tab t')"
check "a reviewer who is not a member" "crew: F:2: reviewer b is not a member" "$(refused 'tab t' 'member a reviewer=b')"
check "a member reviewing itself" "crew: F:2: a cannot review itself" "$(refused 'tab t' 'member a reviewer=a')"
check "a cache with no clone" "crew: F:2: cache= copies into a clone: add clone" "$(refused 'tab t' 'member a cache=.lake -- x')"
check "a budget that is not dollars" "crew: F:2: budget lots is not a number of dollars" "$(refused 'tab t' 'member a budget=lots')"
check "a kind crew does not know" "crew: F:2: kind vim is not one crew knows: claude codex agy other" "$(refused 'tab t' 'member a kind=vim')"
check "nothing after --" "crew: F:2: nothing after --" "$(refused 'tab t' 'member a --')"
check "a tab with a command" "crew: F:1: a tab runs no command" "$(refused 'tab t -- x')"
check "every error is said" "2" "$(refused 'tab t mute' 'member Ada' | wc -l | tr -d ' ')"
check "nothing is read from a refused file" "" "$(printf 'tab t\nmember a\nmember a\n' >"$tmp/bad"; crewfile_read "$tmp/bad" 2>/dev/null)"

# The terminal: the coordinator in tmux:%1; each spawn gets the next pane.
echo 1 >"$tmp/n"
term_self() { echo tmux:%1; }
term_spawn() {
    n=$(($(cat "$tmp/n") + 1))
    echo "$n" >"$tmp/n"
    echo "spawn $1 ${3:-} $2" >>"$tmp/calls"
    echo "tmux:%$n"
}
term_list() {
    i=1
    while [ "$i" -le "$(cat "$tmp/n")" ]; do
        grep -qx "tmux:%$i" "$tmp/closed" 2>/dev/null || printf 'tmux:%%%d\t/dev/ttys00%d\tsh\n' "$i" "$i" 2>/dev/null || break
        i=$((i + 1))
    done
}
: >"$tmp/closed"
: >"$tmp/exited"
term_running() { ! grep -qx "$1" "$tmp/exited" 2>/dev/null; }
term_poke() { echo "poke $1 $2" >>"$tmp/calls"; }
term_name() { :; }
term_color() { :; }
term_tab() { echo "tab $1 $2" >>"$tmp/calls"; }
term_move() { echo "move $1 $2 $3" >>"$tmp/calls"; }
term_even() { :; }
crew_invite() { echo "invite $1" >>"$tmp/invites"; }
clone_ready() { echo "$tmp/work/clone-$3"; }
calls() { cat "$tmp/calls" 2>/dev/null; rm -f "$tmp/calls"; }

# A dry run checks the file and says what it would do, and does nothing.
check "a dry run says what it would do" "name the tab of tmux:%1 main
open a pane beside tmux:%1 running: cd $(cd "$tmp/repo" && pwd -P) && $(shell_word "$CREW_HOME/bin/crew") watch --all
crew layout main --tab main
crew spawn claude --tab proof 'claude --model claude-opus-5-5 --effort high'
crew spawn claude2 --tab proof --clone --cache .lake 'cd sub && claude   # not a comment: after --'
crew layout table --tab proof
crew spawn agy --tab runtime agy
crew mute agy
crew spawn codex --tab runtime --kind codex codex
crew mute codex
crew layout grid --tab runtime
crew invite claude
crew invite claude2
crew invite agy" "$(crew_up --dry 2>&1 | grep -v -e '^open a pane beside $' -e 'board --live' -e 'by hand')"
check "a dry run touches nothing" "" "$(find "$dir/panes" "$dir/tabs" "$dir/layouts" -type f 2>/dev/null; calls)"

# The first crew up.
crew_up >/dev/null 2>"$tmp/up.err"
check "the coordinator's tab is named" "tab tmux:%1 main" "$(grep '^tab ' "$tmp/calls" | head -n 1)"
check "the watch and the board beside the coordinator" "spawn beside tmux:%1 cd $(cd "$tmp/repo" && pwd -P) && $(shell_word "$CREW_HOME/bin/crew") watch --all
spawn beside tmux:%2 cd $(cd "$tmp/repo" && pwd -P) && $(shell_word "$CREW_HOME/bin/crew") board --live" "$(grep -e 'watch --all' -e 'board --live' "$tmp/calls")"
check "the coordinator's tab, in order" "tmux:%1 tmux:%2 tmux:%3" "$(tab_members "$dir" main | tr '\n' ' ' | sed 's/ $//')"
check "a lane, in the Crewfile's order" "claude claude2" "$(tab_members "$dir" proof | tr '\n' ' ' | sed 's/ $//')"
check "the other lane" "agy codex" "$(tab_members "$dir" runtime | tr '\n' ' ' | sed 's/ $//')"
check "a member's line" "1" "$(grep -c "^spawn tab  cd $(cd "$tmp/repo" && pwd -P) && claude --model claude-opus-5-5 --effort high\$" "$tmp/calls")"
check "a clone's line" "1" "$(grep -c "^spawn beside tmux:%4 cd $tmp/work/clone-claude2 && export CREW_DIR=$dir && cd sub && claude   # not a comment: after --\$" "$tmp/calls")"
check "the layouts" "main table grid" "$(cat "$dir/layouts/main" "$dir/layouts/proof" "$dir/layouts/runtime" | tr '\n' ' ' | sed 's/ $//')"
check "the mutes" "agy codex" "$(ls "$dir/muted" | tr '\n' ' ' | sed 's/ $//')"
check "the kind given" "codex" "$(kind_member "$dir" codex)"
check "the invites, but noinvite" "invite agy
invite claude
invite claude2" "$(sort "$tmp/invites")"
check "a member started by hand is said" "1" "$(grep -c "tess is started and joined by hand" "$tmp/up.err")"

# Again: nothing is up again; a closed pane comes back alone.
rm -f "$tmp/invites" "$tmp/calls"
crew_up >/dev/null 2>&1
check "again: nothing spawned" "0" "$(grep -c '^spawn ' "$tmp/calls")"
check "again: nobody invited" "" "$(cat "$tmp/invites" 2>/dev/null)"
cat "$dir/panes/agy" >>"$tmp/closed"
rm -f "$tmp/invites" "$tmp/calls"
crew_up >/dev/null 2>&1
check "a closed pane comes back alone" "1" "$(grep -c '^spawn ' "$tmp/calls")"
check "in its tab, beside the one still there" "1" "$(grep -c "^spawn beside $(cat "$dir/panes/codex") .* agy\$" "$tmp/calls")"
check "and is invited" "invite agy" "$(cat "$tmp/invites")"
check "the lane keeps the Crewfile's order" "agy codex" "$(tab_members "$dir" runtime | tr '\n' ' ' | sed 's/ $//')"
echo tmux:%40 >"$dir/panes/stray"
echo 40 >"$tmp/n"
check "a member up but not in the Crewfile is said and left alone" "crew: stray is up but not in the Crewfile: left alone" "$(crew_up 2>/dev/null | grep stray)"
rm "$dir/panes/stray"
echo 8 >"$tmp/n"

# An exited member whose pane is still there is restarted in place, resuming
# its recorded conversation; --fresh starts a new one; a kind with no resume
# field starts its plain line.
mkdir -p "$dir/sessions" "$dir/threads"
echo sess-11 >"$dir/sessions/claude"
echo thr-22 >"$dir/threads/codex"
cost_agy_db() { [ "$1" = agy ] && echo "$tmp/conv-33.db"; }
term_tty "$(cat "$dir/panes/claude")" >"$tmp/exited"
term_tty "$(cat "$dir/panes/codex")" >>"$tmp/exited"
term_tty "$(cat "$dir/panes/agy")" >>"$tmp/exited"
check "a dry run pokes an exited member in its pane with its resume argument" "crew poke claude 'claude --model claude-opus-5-5 --effort high --resume sess-11'
crew poke agy 'agy --conversation conv-33'
crew poke codex 'codex resume thr-22'" "$(crew_up --dry 2>/dev/null | grep '^crew poke ')"
rm -f "$tmp/invites" "$tmp/calls"
crew_up >/dev/null 2>&1
check "an exited member is not spawned again" "0" "$(grep -c '^spawn ' "$tmp/calls")"
check "an exited claude member is restarted in place with --resume" "1" "$(grep -c "^poke $(cat "$dir/panes/claude") claude --model claude-opus-5-5 --effort high --resume sess-11\$" "$tmp/calls")"
check "an exited codex member is restarted in place with resume" "1" "$(grep -c "^poke $(cat "$dir/panes/codex") codex resume thr-22\$" "$tmp/calls")"
check "an exited agy member is restarted in place with --conversation" "1" "$(grep -c "^poke $(cat "$dir/panes/agy") agy --conversation conv-33\$" "$tmp/calls")"
check "restarted members are invited, except noinvite" "invite agy
invite claude" "$(sort "$tmp/invites")"
rm -f "$tmp/invites" "$tmp/calls"
crew_up --fresh >/dev/null 2>&1
check "--fresh restarts without the resume argument" "poke $(cat "$dir/panes/claude") claude --model claude-opus-5-5 --effort high
poke $(cat "$dir/panes/agy") agy
poke $(cat "$dir/panes/codex") codex" "$(grep '^poke ' "$tmp/calls")"
printf 'mycc claude CLAUDECODE ❯ enter #d97757 -\n' >"$dir/kinds"
echo mycc >"$dir/kind/claude"
rm -f "$tmp/invites" "$tmp/calls"
crew_up >/dev/null 2>&1
check "a kind with no resume field restarts with its plain line" "1" "$(grep -c "^poke $(cat "$dir/panes/claude") claude --model claude-opus-5-5 --effort high\$" "$tmp/calls")"
rm -f "$dir/kinds" "$dir/sessions/claude" "$dir/threads/codex"
echo claude >"$dir/kind/claude"
: >"$tmp/exited"

# Presets: one starts a Crewfile, never replaces it.
mkdir -p "$XDG_CONFIG_HOME/crew/presets"
cp "$dir/Crewfile" "$XDG_CONFIG_HOME/crew/presets/lean"
printf 'tab main\n' >"$XDG_CONFIG_HOME/crew/presets/small"
check "the same preset as the Crewfile" "$dir/Crewfile" "$(up_crewfile "$dir" lean)"
check "another preset is refused" "1" "$(up_crewfile "$dir" small >/dev/null 2>&1; echo $?)"
mv "$dir/Crewfile" "$tmp/Crewfile.kept"
check "a preset starts the Crewfile" "$dir/Crewfile" "$(up_crewfile "$dir" small)"
check "with its lines" "tab main" "$(cat "$dir/Crewfile")"
rm "$dir/Crewfile"
check "no Crewfile and no preset" "crew: no Crewfile in $dir: write one, or start from a preset with 'crew up <preset>'
crew: presets: lean pair ring small solo " "$(up_crewfile "$dir" "" 2>&1)"
check "a preset not there" "1" "$(up_crewfile "$dir" nowhere >/dev/null 2>&1; echo $?)"
for p in solo pair ring; do
    check "the preset $p is read" "0" "$(crewfile_read "$CREW_HOME/share/presets/$p" >/dev/null 2>&1; echo $?)"
done
check "a preset crew ships" "$CREW_HOME/share/presets/ring" "$(crewfile_preset ring)"
printf 'tab mine\n' >"$XDG_CONFIG_HOME/crew/presets/ring"
check "the owner's preset wins" "$XDG_CONFIG_HOME/crew/presets/ring" "$(crewfile_preset ring)"
rm "$XDG_CONFIG_HOME/crew/presets/ring"
rec() { printf 'member\tmain\t%s\t-\t0\t1\t0\t-\t-\t-\t%s' "$1" "$2"; }
check "a preset's agents are installed" "0" "$(up_agents "$(rec a 'sh -c true')" >/dev/null 2>&1; echo $?)"
check "an agent not installed is named" "crew: b runs no-such-agent, which is not installed" "$(up_agents "$(rec b 'no-such-agent --x')" 2>&1)"
check "a member joined by hand needs no agent" "0" "$(up_agents "$(rec c -)" >/dev/null 2>&1; echo $?)"
check "up wants one preset" "2" "$(crew_up a b >/dev/null 2>&1; echo $?)"
check "up knows only --dry" "2" "$(crew_up --fast >/dev/null 2>&1; echo $?)"

finish
