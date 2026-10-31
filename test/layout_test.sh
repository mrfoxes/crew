#!/bin/sh
# Placing the crew's panes: tabs by name, a member's place in its tab, and
# what crew panes and crew board say of them, with the terminal faked.
#
#   sh test/run.sh layout

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
kind_of_self() { :; }

# The terminal: each spawn says where it was asked to open the pane, and
# gets the next pane, %1, %2, ...; the panes listed are those spawned and
# not closed in $tmp/closed.
echo 0 >"$tmp/n"
term_spawn() {
    n=$(($(cat "$tmp/n") + 1))
    echo "$n" >"$tmp/n"
    echo "spawn $1 ${3:-}" >>"$tmp/calls"
    echo "tmux:%$n"
}
term_list() {
    i=1
    while [ "$i" -le "$(cat "$tmp/n")" ]; do
        grep -qx "tmux:%$i" "$tmp/closed" 2>/dev/null || printf 'tmux:%%%d\t/dev/ttys00%d\tsh\n' "$i" "$i"
        i=$((i + 1))
    done
}
: >"$tmp/closed"
term_name() { echo "name $1 $2" >>"$tmp/calls"; }
term_color() { :; }
term_tab() { echo "tab $1 $2" >>"$tmp/calls"; }
calls() { cat "$tmp/calls"; rm -f "$tmp/calls"; }

crew_spawn claude --tab proof claude >/dev/null
check "the first member of a tab opens it and names it" "spawn tab 
tab tmux:%1 proof
name tmux:%1 claude · proof" "$(calls)"
check "the tab lists its member" "claude" "$(tab_members "$dir" proof)"
crew_spawn claude2 --tab proof claude >/dev/null
check "the next member of a tab is placed beside the last" "spawn beside tmux:%1
name tmux:%2 claude2 · proof" "$(calls)"
crew_spawn claude3 --tab proof claude >/dev/null
check "and the next beside it" "spawn beside tmux:%2" "$(calls | sed -n 1p)"
check "a tab's members, in order" "claude claude2 claude3" "$(tab_members "$dir" proof | tr '\n' ' ' | sed 's/ $//')"
crew_spawn agy --tab runtime agy >/dev/null
check "another tab opens" "spawn tab " "$(calls | sed -n 1p)"
check "the tab of a member" "runtime" "$(tab_of "$dir" agy)"
crew_spawn codex --below agy codex >/dev/null
check "a member placed next to another sits in its tab" "runtime" "$(tab_of "$dir" codex)"
check "and its label says so" "name tmux:%5 codex · runtime" "$(calls | sed -n 2p)"
crew_spawn tess tess >/dev/null
check "a member placed in no tab sits in none" "" "$(tab_of "$dir" tess)"
check "and its label is its name" "name tmux:%6 tess" "$(calls | sed -n 2p)"

# The last member still there anchors the tab; with none left, the tab opens
# again.
echo tmux:%3 >>"$tmp/closed"
crew_spawn claude4 --tab proof claude >/dev/null
check "a gone pane anchors nothing" "spawn beside tmux:%2" "$(calls | sed -n 1p)"
printf 'tmux:%%1\ntmux:%%2\ntmux:%%7\n' >>"$tmp/closed"
crew_spawn claude5 --tab proof claude >/dev/null
check "a tab whose panes are all gone opens again" "spawn tab 
tab tmux:%8 proof" "$(calls | sed -n 1,2p)"

# Leaving takes a member out of its tab, and a tab left empty is forgotten.
crew_leave agy >/dev/null
check "leave takes the member out of its tab" "codex" "$(tab_members "$dir" runtime)"
crew_leave codex >/dev/null
check "a tab left empty is forgotten" "no" "$([ -e "$dir/tabs/runtime" ] && echo yes || echo no)"
check "a tab must be a name" "2" "$(crew_spawn x --tab 'Proof Lane' true >/dev/null 2>&1; echo $?)"

# crew panes lists the members of a tab together, in their order, and the
# board names each member's tab.
crew_spawn tess2 tess >/dev/null
crew_spawn claude6 --tab proof claude >/dev/null
check "panes group a tab's members, in their order" "tess     other   -        tmux:%6
tess2    other   -        tmux:%9
claude5  claude  proof    tmux:%8
claude6  claude  proof    tmux:%10" "$(crew_panes | awk '$1 != "-"' | cut -c1-37 | sed 's/ *$//')"
printf 'Agent: claude5\n' >"$dir/status/claude5.md"
check "the board names the tab" "1" "$(crew_board 1 | grep -c '^== claude5 (claude, tab proof, tmux:%8, 0 min ago)$')"

# Layouts: the rows each makes of a tab's entries, and the moves that lay
# the rows out.
rows() { layout_rows "$dir" "$@" | tr '\n' '/' | sed 's/\/$//'; }
check "a grid of five is three over two" "a b c/d e" "$(rows grid a b c d e)"
check "a grid of four" "a b/c d" "$(rows grid a b c d)"
check "a grid of one" "a" "$(rows grid a)"
check "a grid of none" "" "$(rows grid)"
check "a fixed grid" "a b c/d e f/g" "$(rows 3x2 a b c d e f g)"
check "main and a grid beside it" "main a/b c/d" "$(rows main a b c d)"
check "rows of names" "a b c/d e" "$(rows 'a,b,c / d,e')"
kind_record "$dir" t1 claude
kind_record "$dir" t2 codex
kind_record "$dir" t3 claude
kind_record "$dir" t4 agy
check "a table: a row a kind, in the order they come" "t1 t3/t2/t4/tmux:%99" "$(rows table t1 t2 t3 t4 tmux:%99)"
for want in table grid main 3x2 'a,b / c' 'a/b'; do
    check "a layout crew knows: $want" "0" "$(layout_known "$want"; echo $?)"
done
for bad in 2x x2 3x2x1 Proof box abc ''; do
    check "a layout crew does not know: $bad" "1" "$(layout_known "$bad"; echo $?)"
done
check "the moves of rows: the first of each under the one before, then each row rightward" "b below a
c beside a
d beside b" "$(printf 'a c\nb d\n' | layout_moves)"
check "the moves of main" "b beside m
c below b
d beside c" "$(printf 'main m\nb\nc d\n' | layout_moves)"

# Laying out a tab: its entries whose pane is there, moved by the layout,
# which the tab keeps.
term_move() { echo "move $1 $2 $3" >>"$tmp/calls"; }
term_even() { echo "even $1" >>"$tmp/calls"; }
for m in l1 l2 l3 l4 l5; do
    crew_spawn "$m" --tab lane claude >/dev/null
done
rm -f "$tmp/calls"
check "layout a tab" "lane: grid" "$(crew_layout grid --tab lane)"
check "the tab keeps its layout" "grid" "$(cat "$dir/layouts/lane")"
l1=$(cat "$dir/panes/l1") l2=$(cat "$dir/panes/l2") l3=$(cat "$dir/panes/l3") l4=$(cat "$dir/panes/l4") l5=$(cat "$dir/panes/l5")
check "the moves of a grid of five" "move $l4 below $l1
move $l2 beside $l1
move $l3 beside $l2
move $l5 beside $l4
even $l1
even $l4" "$(calls)"
echo "$l2" >>"$tmp/closed"
check "a closed pane leaves no hole" "lane: grid" "$(crew_layout)"
check "the moves without it" "move $l4 below $l1
move $l3 beside $l1
move $l5 beside $l4
even $l1
even $l4" "$(calls)"
crew_spawn l6 --tab lane claude >/dev/null
check "a new member of a tab with a layout is laid out with it" "4" "$(grep -c '^move ' "$tmp/calls")"
rm -f "$tmp/calls"
term_move() { [ "$1" != "$l3" ] || return 3; echo "move $1 $2 $3" >>"$tmp/calls"; }
check "a pane in its place already is no failure" "0" "$(crew_layout >/dev/null; echo $?)"
term_move() { echo "crew: refused" >&2; return 1; }
check "a refused move fails the layout, and is said" "crew: refused" "$(crew_layout 2>&1 >/dev/null | sort -u)"
check "a layout crew does not know" "2" "$(crew_layout zigzag --tab lane >/dev/null 2>&1; echo $?)"
check "a layout needs its tab" "2" "$(crew_layout grid >/dev/null 2>&1; echo $?)"
check "a tab crew does not know" "1" "$(crew_layout grid --tab nowhere >/dev/null 2>&1; echo $?)"
term_move() { echo "move $1 $2 $3" >>"$tmp/calls"; }
rm -f "$tmp/calls"
check "rows of names go to the tab of the first" "lane: l1,l3 / l4" "$(crew_layout l1,l3 / l4)"
check "and are moved so" "move $l4 below $l1
move $l3 beside $l1" "$(calls | grep '^move ')"

finish
