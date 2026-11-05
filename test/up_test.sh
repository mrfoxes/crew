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
check "a word crew does not know" "crew: F:2: a line is a tab, a member, or a pane, not lane" "$(refused 'tab t' 'lane x')"
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

# Pane lines: the coordinator's pane, the watch, and the board, each at its
# place in the first tab; a pane line opens the watch or the board.
printf 'tab main layout=2x2 board\nmember qa\npane coordinator\nmember dev1\npane watch\ntab lane\nmember dev2\n' >"$tmp/panes"
check "pane lines read in place" "tab	main	2x2	1	1
member	main	qa	-	0	1	0	-	-	-	-
pane	main	coordinator
member	main	dev1	-	0	1	0	-	-	-	-
pane	main	watch
tab	lane	grid	0	0
member	lane	dev2	-	0	1	0	-	-	-	-" "$(crewfile_read "$tmp/panes")"
check "a pane before a tab" "crew: F:1: a pane comes after a tab" "$(refused 'pane coordinator')"
check "a pane crew does not know" "crew: F:2: a pane is coordinator, watch, or board" "$(refused 'tab t' 'pane desk')"
check "a pane with no word" "crew: F:2: a pane is coordinator, watch, or board" "$(refused 'tab t' 'pane')"
check "a pane's option" "crew: F:2: a pane takes no option, not mute" "$(refused 'tab t' 'pane watch mute')"
check "a pane with a command" "crew: F:2: a pane runs no command" "$(refused 'tab t' 'pane coordinator -- x')"
check "a pane on a later tab" "crew: F:3: pane coordinator belongs on the first tab, the coordinator's" "$(refused 'tab t' 'tab u' 'pane coordinator')"
check "a pane twice" "crew: F:3: pane board is there twice" "$(refused 'tab t' 'pane board' 'pane board')"
check "a helper both on the tab line and on a line" "crew: F:2: watch is on the tab line and on a line of its own" "$(refused 'tab t watch' 'pane watch')"

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
the order of main: tmux:%1 watch board
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
check "with no pane line, the coordinator first, then the watch and the board" "tmux:%1 tmux:%2 tmux:%3" "$(tab_members "$dir" main | tr '\n' ' ' | sed 's/ $//')"
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

# A crew laid out around its coordinator, as the crew that wrote this was:
# qa over the coordinator on the left, dev1 over dev2 on the right.
git init -q "$tmp/two"
cd "$tmp/two" || exit 1
dir=$(crew_init)
echo 1 >"$tmp/n"
: >"$tmp/closed"
: >"$tmp/exited"
rm -f "$tmp/calls" "$tmp/invites"
printf 'tab main layout=2x2\nmember qa -- claude\nmember dev1 -- claude\npane coordinator\nmember dev2 -- claude\n' >"$dir/Crewfile"
check "a dry run says the first tab's order" "the order of main: qa dev1 tmux:%1 dev2" "$(crew_up --dry 2>/dev/null | grep '^the order of ')"
crew_up >/dev/null 2>&1
qa=$(cat "$dir/panes/qa")
d1=$(cat "$dir/panes/dev1")
d2=$(cat "$dir/panes/dev2")
check "a pane line puts the coordinator's pane in its place" "qa dev1 tmux:%1 dev2" "$(tab_members "$dir" main | tr '\n' ' ' | sed 's/ $//')"
check "2x2 puts the coordinator under qa, and dev2 beside it" "move tmux:%1 below $qa
move $d1 beside $qa
move $d2 beside tmux:%1" "$(grep '^move ' "$tmp/calls")"
rm -f "$tmp/calls"
check "crew layout keeps it" "move tmux:%1 below $qa" "$(crew_layout >/dev/null 2>&1; grep '^move ' "$tmp/calls" | sed -n 1p)"

# A restore drops the coordinator's old pane from the tab; crew up puts the
# one it runs in now back in its place.
crew_reset >/dev/null 2>&1
crew_restore >/dev/null
check "the restored tab has no pane" "qa dev1 dev2" "$(tab_members "$dir" main | tr '\n' ' ' | sed 's/ $//')"
echo 30 >"$tmp/n"
term_self() { echo tmux:%30; }
crew_up >/dev/null 2>&1
check "crew up puts the coordinator's pane back in its place" "qa dev1 tmux:%30 dev2" "$(tab_members "$dir" main | tr '\n' ' ' | sed 's/ $//')"

# The watch at its place on a line; the board, a word of the tab line, right
# after the coordinator's pane, which comes first with no line of its own.
git init -q "$tmp/three"
cd "$tmp/three" || exit 1
dir=$(crew_init)
echo 1 >"$tmp/n"
term_self() { echo tmux:%1; }
printf 'tab main layout=grid board\nmember qa -- claude\npane watch\n' >"$dir/Crewfile"
crew_up >/dev/null 2>&1
check "a watch on a line, a board on the tab line" "tmux:%1 $(cat "$dir/up/board") qa $(cat "$dir/up/watch")" "$(tab_members "$dir" main | tr '\n' ' ' | sed 's/ $//')"

# Restarting a live member on its Crewfile line. The fake agent leaves its
# pane on its kind's quit command and comes back on any other line; its
# screen says what $tmp/state.<name> holds, idle when there is none.
git init -q "$tmp/four"
cd "$tmp/four" || exit 1
dir=$(crew_init)
echo 1 >"$tmp/n"
: >"$tmp/exited"
rm -f "$tmp/calls" "$tmp/invites"
screen_pause() { :; }
screen_state() { cat "$tmp/state.$2" 2>/dev/null || echo idle; }
term_poke() {
    echo "poke $1 $2" >>"$tmp/calls"
    p_tty=$(term_tty "$1")
    case "$2" in
    /exit | /quit) [ -e "$tmp/stuck" ] || echo "$p_tty" >>"$tmp/exited" ;;
    *) grep -vx "$p_tty" "$tmp/exited" >"$tmp/exited.new" || :; mv "$tmp/exited.new" "$tmp/exited" ;;
    esac
}
printf 'tab main\nmember qa -- claude --model sonnet\nmember cx kind=codex noinvite -- codex\nmember hand\n' >"$dir/Crewfile"
crew_up >/dev/null 2>&1
qa=$(cat "$dir/panes/qa")
cx=$(cat "$dir/panes/cx")
check "crew up records the line each member started with" "claude --model sonnet|codex" "$(cat "$dir/lines/qa" "$dir/lines/cx" | tr '\n' '|' | sed 's/|$//')"
mkdir -p "$dir/sessions"
echo sess-1 >"$dir/sessions/qa"
echo thr-9 >"$dir/threads/cx"
printf 'tab main\nmember qa -- claude --model opus\nmember cx kind=codex noinvite -- codex -m gpt-x\nmember hand\n' >"$dir/Crewfile"
rm -f "$tmp/calls" "$tmp/invites"
check "crew up names the live members whose line changed, and restarts none" "crew: qa's Crewfile line changed since it started; 'crew up --restart qa' restarts it
crew: cx's Crewfile line changed since it started; 'crew up --restart cx' restarts it" "$(crew_up 2>/dev/null | grep 'line changed')"
check "nothing was typed" "" "$(grep '^poke ' "$tmp/calls" 2>/dev/null)"
check "a dry run says how it would restart" "restart qa in its pane: /exit, then claude --model opus --resume sess-1" "$(crew_up --dry --restart qa 2>/dev/null | grep '^restart ')"
rm -f "$tmp/calls" "$tmp/invites"
out=$(crew_up --restart qa cx 2>&1)
check "--restart quits each agent with its kind's command, then types its line, resumed" "poke $qa /exit
poke $qa claude --model opus --resume sess-1
poke $cx /quit
poke $cx codex -m gpt-x resume thr-9" "$(grep '^poke ' "$tmp/calls")"
check "and says so" "restarted qa on its Crewfile line|restarted cx on its Crewfile line" "$(printf '%s\n' "$out" | grep '^restarted ' | tr '\n' '|' | sed 's/|$//')"
check "a restarted member is invited, but noinvite" "invite qa" "$(cat "$tmp/invites")"
check "the new lines are recorded" "claude --model opus|codex -m gpt-x" "$(cat "$dir/lines/qa" "$dir/lines/cx" | tr '\n' '|' | sed 's/|$//')"
check "no hold is left" "" "$(ls "$dir/tmp/hold" 2>/dev/null)"
check "crew up names no change now" "" "$(crew_up 2>/dev/null | grep 'line changed')"
printf 'tab main\nmember qa -- claude --model opus\nmember cx kind=codex noinvite -- codex\nmember hand\n' >"$dir/Crewfile"
rm -f "$tmp/calls"
crew_up --fresh --restart qa cx >/dev/null 2>&1
check "--fresh restarts with no resume, a plain codex line too" "poke $qa /exit
poke $qa claude --model opus
poke $cx /quit
poke $cx codex" "$(grep '^poke ' "$tmp/calls")"

# What a restart refuses: before crew up does anything, a name the Crewfile
# lacks or gives no line; then, member by member, a screen that is not idle
# or runs a background shell, and with --fresh, work its Next: cannot place.
rm -f "$tmp/calls"
check "a name the Crewfile lacks" "crew: nobody is no member of $dir/Crewfile: nothing was restarted" "$(crew_up --restart nobody 2>&1)"
check "a member started by hand" "crew: hand is started and joined by hand ($dir/Crewfile gives it no line): crew up cannot restart it" "$(crew_up --restart hand 2>&1)"
check "--restart names someone" "2" "$(crew_up --restart >/dev/null 2>&1; echo $?)"
check "nothing was typed for them" "" "$(grep '^poke ' "$tmp/calls" 2>/dev/null)"
echo working >"$tmp/state.qa"
check "a member in a turn is refused" "crew: qa is not idle at an empty prompt: it is working, so nothing was typed" "$(crew_up --restart qa 2>&1 >/dev/null | grep -v "^crew: hand ")"
check "and crew up says it failed" "1" "$(crew_up --restart qa >/dev/null 2>&1; echo $?)"
echo shell >"$tmp/state.qa"
check "a background shell is refused" "1" "$(crew_up --restart qa >/dev/null 2>&1; echo $?)"
echo typed >"$tmp/state.qa"
check "typed text is refused" "1" "$(crew_up --restart qa >/dev/null 2>&1; echo $?)"
check "nothing was typed into qa's pane" "" "$(grep "^poke $qa" "$tmp/calls" 2>/dev/null)"
rm -f "$tmp/state.qa"
printf 'Agent: qa\nFiles: f.txt\nNext: f\n' | crew_write status qa >/dev/null
touch -t 202601010000 "$dir/status/qa.md"
echo f >f.txt
check "--fresh refuses work its Next: cannot place" "1" "$(crew_up --fresh --restart qa >/dev/null 2>&1; echo $?)"
check "a resume does not need it" "0" "$(crew_up --restart qa >/dev/null 2>&1; echo $?)"
rm -f f.txt
: >"$tmp/stuck"
rm -f "$tmp/calls"
check "an agent that does not leave is said" "crew: qa's agent did not leave within about half a minute of /exit: look with crew peek qa" "$(crew_up --restart qa 2>&1 >/dev/null | grep -v "^crew: hand ")"
check "its line is not typed" "poke $qa /exit" "$(grep '^poke ' "$tmp/calls")"
check "and the hold is released" "" "$(ls "$dir/tmp/hold" 2>/dev/null)"
rm -f "$tmp/stuck"

finish
