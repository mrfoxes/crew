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
