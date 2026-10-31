# Placing panes: opening one beside, under, or over another, or in a tab,
# and moving one next to another while its agent runs on. The terminal
# places them (lib/term-*.sh); this file picks the terminal and checks what
# is asked first. Sourced by bin/crew.

# Opens a pane beside this one (split), in a new tab (tab), or right of,
# under, or over <pane> (beside, below, above), runs <line> there through
# the owner's shell, so the pane outlives it, and prints the new pane: in
# tmux when crew runs inside it, else in iTerm2.
term_spawn() {
    if [ -n "${TMUX:-}" ]; then
        tmux_spawn "$@"
    else
        iterm_spawn "$@"
    fi
}

# Moves <pane> right of, under, or over <anchor> (beside, below, above):
# the agent in it runs on, and the pane keeps its id and tty, so the one
# panes/<name> records stays true. The pane is never closed: one the
# terminal will not place, or places elsewhere, stays where it is, and the
# move fails saying so. The focus stays where it was.
term_move() {
    pane=$1
    where=$2
    anchor=$3
    case "$where" in
    beside | below | above) ;;
    *)
        echo "crew: a pane moves beside, below, or above another, not '$where'" >&2
        return 2
        ;;
    esac
    if [ "$pane" = "$anchor" ]; then
        echo "crew: $pane cannot move next to itself" >&2
        return 1
    fi
    backend=$(term_of "$pane") || return
    if [ "$(term_of "$anchor" 2>/dev/null)" != "$backend" ]; then
        echo "crew: $pane and $anchor are not panes of one terminal" >&2
        return 1
    fi
    "${backend}_move" "${pane#*:}" "$where" "${anchor#*:}"
}

# The crew's tabs, by name: tabs/<tab> lists its members, one a line, in
# the order they were placed there. A member sits in one tab at most.

# The tab <member> sits in, in the crew <dir>, or nothing.
tab_of() {
    for t_file in "$1"/tabs/*; do
        [ -f "$t_file" ] || continue
        if grep -qx -- "$2" "$t_file"; then
            basename "$t_file"
            return
        fi
    done
}

# The members of <tab>, in the order they were placed.
tab_members() {
    cat "$1/tabs/$2" 2>/dev/null
}

# Puts <member> last in <tab>, out of any tab it sat in before.
tab_add() {
    tab_drop "$1" "$3"
    mkdir -p "$1/tabs"
    echo "$3" >>"$1/tabs/$2"
}

# Takes <member> out of its tab; a tab left empty is forgotten.
tab_drop() {
    for t_file in "$1"/tabs/*; do
        [ -f "$t_file" ] || continue
        grep -vx -- "$2" "$t_file" >"$t_file.new" || :
        if [ -s "$t_file.new" ]; then
            mv "$t_file.new" "$t_file"
        else
            rm -f "$t_file" "$t_file.new"
        fi
    done
}

# The pane of the last member of <tab> whose pane is still there, which a
# new member of the tab is placed next to; nothing when the tab is gone.
tab_anchor() {
    t_anchor=""
    for t_member in $(tab_members "$1" "$2"); do
        t_pane=$(cat "$1/panes/$t_member" 2>/dev/null) || continue
        term_gone "$t_pane" || t_anchor=$t_pane
    done
    echo "$t_anchor"
}

# The tab of the member whose pane is <pane>, or nothing.
tab_of_pane() {
    for t_file in "$1"/panes/*; do
        [ -f "$t_file" ] || continue
        if [ "$(cat "$t_file")" = "$2" ]; then
            tab_of "$1" "$(basename "$t_file")"
            return
        fi
    done
}
