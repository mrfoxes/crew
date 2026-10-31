# Placing panes: opening one beside, under, or over another, or in a tab,
# and moving one next to another while its agent runs on, in iTerm2 or in
# tmux. Built on lib/term.sh. Sourced by bin/crew.

# Opens a pane beside this one (split), in a new tab (tab), or right of,
# under, or over <pane> (beside, below, above), runs <line> there through
# the owner's shell, so the pane outlives it, and prints the new pane.
term_spawn() {
    where=$1
    line=$2
    anchor=${3:-}
    if [ -n "${TMUX:-}" ]; then
        case "$where:$anchor" in
        tab:*) id=$(tmux new-window -P -F '#{pane_id}') ;;
        beside:tmux:*) id=$(tmux split-window -h -t "${anchor#tmux:}" -P -F '#{pane_id}') && tmux_even "$id" ;;
        below:tmux:*) id=$(tmux split-window -v -t "${anchor#tmux:}" -P -F '#{pane_id}') ;;
        above:tmux:*) id=$(tmux split-window -v -b -t "${anchor#tmux:}" -P -F '#{pane_id}') ;;
        beside:* | below:* | above:*)
            echo "crew: $anchor is not a tmux pane" >&2
            return 1
            ;;
        *) id=$(tmux split-window -P -F '#{pane_id}') && tmux select-layout tiled >/dev/null ;;
        esac || return
        tmux send-keys -t "$id" -l -- "$line" && tmux send-keys -t "$id" Enter
        echo "tmux:$id"
        return
    fi
    case "$where:$anchor" in
    beside:iterm:* | below:iterm:* | above:iterm:*) me=$anchor ;;
    beside:* | below:* | above:*)
        echo "crew: $anchor is not an iTerm2 pane" >&2
        return 1
        ;;
    *)
        me=$(term_self) || {
            echo "crew: spawn needs iTerm2 or tmux" >&2
            return 1
        }
        ;;
    esac
    if [ "$where" = tab ]; then
        open='tell w to set n to current session of (create tab with default profile)'
    elif [ "$where" = beside ]; then
        open='tell s to set n to (split vertically with default profile)'
    elif [ "$where" = below ]; then
        open='tell s to set n to (split horizontally with default profile)'
    elif [ "$where" = above ]; then
        # AppleScript splits only below: the new pane is split off <pane>,
        # then moved over it with iTerm2's own move_session (3.5 and later).
        # Its docs read before: true as over, its code as under: both are
        # tried, and the one kept lists the new pane first, as a tab lists
        # its panes from the top. A pane left under is closed. Each check
        # walks every tab again: the loop's references count windows from
        # the front, which a move may reorder, and AppleScript cannot take
        # the contents of such a reference.
        open='set f to current session of t
                        tell s to set n to (split horizontally with default profile)
                        set nid to unique id of n
                        try
                            repeat with i from 1 to 2
                                set b to item i of {"false", "true"}
                                invoke API expression "iterm2.move_session(session: \"" & nid & "\", destination: \"" & (item 1 of argv) & "\", vertical: false, before: " & b & ")"
                                set placed to false
                                repeat with w2 in windows
                                    repeat with t2 in tabs of w2
                                        repeat with x in sessions of t2
                                            set u to unique id of x
                                            if u is nid then set placed to true
                                            if u is nid or u is (item 1 of argv) then exit repeat
                                        end repeat
                                    end repeat
                                end repeat
                                if placed then exit repeat
                            end repeat
                            if not placed then error "the new pane stayed under it"
                        on error e
                            tell n to close
                            error "no pane over " & (item 1 of argv) & ": " & e & " (iTerm2 3.5 or later moves one there)"
                        end try
                        tell f to select'
    else
        # Beside this pane while the tab holds an odd number, below it while
        # even: three or four panes make a grid, not a row of slivers.
        open='if (count of sessions of t) mod 2 = 1 then
                            tell s to set n to (split vertically with default profile)
                        else
                            tell s to set n to (split horizontally with default profile)
                        end if'
    fi
    id=$(iterm_with "${me#iterm:}" "$open
                        tell n to write text (item 2 of argv)
                        return unique id of n" "$line") || return
    echo "iterm:$id"
}

# Spreads tmux pane <id> and the panes beside it out evenly, as iTerm2 does
# with a pane split beside another: a row of a table, not halves of halves.
# tmux before 3.1 has no -E, and keeps the halves.
tmux_even() {
    tmux select-layout -E -t "$1" >/dev/null 2>&1 || :
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
    case "${pane%%:*}:${anchor%%:*}" in
    tmux:tmux)
        # join-pane moves the pane itself (-d: the focus stays), and -b
        # puts it before the target, over it here.
        case "$where" in
        beside) tmux join-pane -d -h -s "${pane#tmux:}" -t "${anchor#tmux:}" && tmux_even "${pane#tmux:}" ;;
        below) tmux join-pane -d -v -s "${pane#tmux:}" -t "${anchor#tmux:}" ;;
        above) tmux join-pane -d -v -b -s "${pane#tmux:}" -t "${anchor#tmux:}" ;;
        esac
        return
        ;;
    iterm:iterm) ;;
    *)
        echo "crew: $pane and $anchor are not panes of one terminal" >&2
        return 1
        ;;
    esac
    # iTerm2's move_session (3.5 and later) moves a session into a split of
    # another: vertical: true beside it, false over or under it. Its docs
    # read before: true as left or over, its code (3.5 to 3.7.5) as left or
    # under, so the code's value goes first and the other only when the
    # pane lands on the wrong side. Arguments: vertical, the side of the
    # anchor the pane must end on in the order a tab lists its panes (from
    # the top left, as iTerm2 walks its splits), the two values of before:.
    case "$where" in
    beside) set -- true after false true ;;
    above) set -- false before false true ;;
    below) set -- false after true false ;;
    esac
    verdict=$(iterm_move "${pane#iterm:}" "${anchor#iterm:}" "$@") || {
        echo "crew: iTerm2 could not move $pane $where $anchor; it stays where iTerm2 left it (iTerm2 3.5 or later moves panes)" >&2
        return 1
    }
    case "$verdict" in
    placed) ;;
    unchanged)
        echo "crew: iTerm2 left $pane where it was: a locked layout, no room to split, or $where $anchor already" >&2
        return 1
        ;;
    *)
        echo "crew: iTerm2 moved $pane, but not $where $anchor; it stays where iTerm2 put it" >&2
        return 1
        ;;
    esac
}

# Moves the iTerm2 session <session> next to <anchor>: argv <session>
# <anchor> <vertical> <side> <before> <before>, as term_move says. Prints
# placed, unchanged, or elsewhere.
iterm_move() {
    osascript - "$@" <<'EOF'
-- AppleScript shows no pane's position, only the order of a tab's panes
-- and their sizes. A move counts once the anchor's tab has changed and the
-- pane sits next to the anchor on the side asked: a refused move changes
-- nothing, and a pane that sat there in the order already (under the
-- anchor, or atop the next column) would pass for one moved. Windows,
-- tabs, and sessions are walked by index and matched by unique id: a
-- loop's references cannot be read back in iTerm2's dictionary, where
-- contents names a session's screen, and a move renumbers tabs.
on run argv
    set src to item 1 of argv
    set dst to item 2 of argv
    -- A pane opened a moment ago may still be taking its size.
    set r to my look(src, dst)
    repeat 10 times
        delay 0.2
        set r2 to my look(src, dst)
        if item 1 of r2 is item 1 of r then exit repeat
        set r to r2
    end repeat
    set cur to item 3 of r
    set focused to ""
    tell application "iTerm2"
        try
            set focused to unique id of current session of current window
        end try
    end tell
    set verdict to "unchanged"
    set failed to false
    set why to ""
    try
        repeat with i from 1 to 2
            set was to item 1 of r
            tell application "iTerm2" to invoke API expression "iterm2.move_session(session: \"" & src & "\", destination: \"" & dst & "\", vertical: " & (item 3 of argv) & ", before: " & (item (4 + i) of argv) & ")"
            -- The splits change at once, the sizes a moment later.
            repeat 10 times
                delay 0.2
                set r to my look(src, dst)
                if item 1 of r is not was then exit repeat
            end repeat
            if item 1 of r is was then exit repeat
            if item 2 of r is item 4 of argv then
                set verdict to "placed"
                exit repeat
            end if
            set verdict to "elsewhere"
        end repeat
    on error e
        set failed to true
        set why to e
    end try
    -- The move hands the focus to the moved pane: give it back.
    my pick(cur)
    if focused is not "" then my pick(focused)
    if failed then error why
    return verdict
end run

-- The tab that holds <dst>: each of its panes with its size, one a line;
-- the side of <dst> that <src> sits on in the order the tab lists them
-- (before, after, or apart); and the tab's current pane.
on look(src, dst)
    tell application "iTerm2"
        repeat with i from 1 to count of windows
            repeat with j from 1 to count of tabs of window i
                set out to ""
                set dk to 0
                set sk to 0
                repeat with k from 1 to count of sessions of tab j of window i
                    set x to session k of tab j of window i
                    set u to unique id of x
                    if u is dst then set dk to k
                    if u is src then set sk to k
                    set out to out & u & " " & (columns of x) & "x" & (rows of x) & linefeed
                end repeat
                if dk > 0 then
                    set side to "apart"
                    if sk > 0 and sk = dk - 1 then set side to "before"
                    if sk > 0 and sk = dk + 1 then set side to "after"
                    return {out, side, unique id of current session of tab j of window i}
                end if
            end repeat
        end repeat
    end tell
    error "no iTerm2 session " & dst
end look

-- Makes the session <u> the current one of its tab again, wherever it is.
on pick(u)
    tell application "iTerm2"
        repeat with i from 1 to count of windows
            repeat with j from 1 to count of tabs of window i
                repeat with k from 1 to count of sessions of tab j of window i
                    if unique id of session k of tab j of window i is u then
                        tell session k of tab j of window i to select
                        return
                    end if
                end repeat
            end repeat
        end repeat
    end tell
end pick
EOF
}
