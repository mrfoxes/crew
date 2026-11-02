# iTerm2's half of the terminal contract (lib/term.sh): its sessions
# listed, read, typed into, opened, and moved, through osascript. <id> is a
# session's unique id. Sourced by lib/term.sh.

# Runs <body> on the iTerm2 session <id>, bound to `s` in the window `w`. The
# body ends with `return`; arguments after it are items 2... of argv.
iterm_with() {
    id=$1
    body=$2
    shift 2
    osascript - "$id" "$@" <<EOF
on run argv
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if unique id of s is item 1 of argv then
                        $body
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    error "no iTerm2 session " & item 1 of argv
end run
EOF
}

# One line a session: the pane, its tty, its title. Asking AppleScript does
# not launch iTerm2; pgrep does not always see it. An iTerm2 that does not
# answer within ITERM_TIMEOUT seconds (a modal dialog, a stuck window) lists
# nothing and says so, instead of holding the caller for AppleScript's own
# two minutes.
ITERM_TIMEOUT=5
iterm_list() {
    [ "$(osascript -e 'application "iTerm2" is running' 2>/dev/null)" = true ] || return 0
    il_out=$(iterm_sessions 2>/dev/null) || {
        echo "crew: iTerm2 did not list its sessions within $ITERM_TIMEOUT seconds" >&2
        return 0
    }
    printf '%s\n' "$il_out" | grep -v '^$' || :
}

# Every session of iTerm2, a line each, failing when iTerm2 does not answer
# within ITERM_TIMEOUT seconds.
iterm_sessions() {
    osascript - "$ITERM_TIMEOUT" <<'EOS'
on run argv
    -- Inside the tell, "tab" is iTerm2's tab: name the character before it.
    set sep to ASCII character 9
    with timeout of (item 1 of argv as integer) seconds
        tell application "iTerm2"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set out to out & "iterm:" & (unique id of s) & sep & (tty of s) & sep & (name of s) & linefeed
                    end repeat
                end repeat
            end repeat
            return out
        end tell
    end timeout
end run
EOS
}

# iTerm2 fails a read now and then while a tab closes ("Invalid index"):
# once more before giving up.
iterm_read() {
    iterm_with "$1" 'return contents of s' 2>/dev/null || {
        sleep 0.3
        iterm_with "$1" 'return contents of s'
    }
}

iterm_type() {
    iterm_with "$1" 'tell s to write text (item 2 of argv) newline no
                        return' "$2" >/dev/null
}

# Presses a key by typing the bytes the terminal would send for it.
iterm_key() {
    iterm_type "$1" "$3"
}

# Shows <label> on session <id> as its badge, which no agent's title
# reaches: the escape sequence that sets it, written to the session's tty
# as output, never as a line typed in. An empty label clears it.
iterm_name() {
    tty=$(term_tty "iterm:$1") || return
    printf '\033]1337;SetBadgeFormat=%s\007' "$(printf '%s' "$2" | base64 | tr -d '\n')" >"$tty"
}

# Tints session <id>'s background an eighth of the way toward <color>
# (#rrggbb), from the background it had before crew first tinted it, which
# the session keeps in its variable user.crew_background; no color puts
# that one back. The red, green, and blue go as items 2 to 4 of argv, and
# no color as none at all: osascript passes an empty argument on, which
# AppleScript would read as 0, a tint toward black.
iterm_color() {
    ic_id=$1
    if [ -n "${2:-}" ]; then
        set -- "$(printf '%d' "0x$(printf '%s' "$2" | cut -c2-3)")" \
            "$(printf '%d' "0x$(printf '%s' "$2" | cut -c4-5)")" \
            "$(printf '%d' "0x$(printf '%s' "$2" | cut -c6-7)")"
    else
        set --
    fi
    iterm_with "$ic_id" 'set saved to ""
                        try
                            set saved to (variable named "user.crew_background") of s
                        end try
                        if saved is missing value then set saved to ""
                        if saved is "" then
                            if (count of argv) < 4 then return
                            set bg to background color of s
                            tell s to set variable named "user.crew_background" to ((item 1 of bg) as text) & "," & ((item 2 of bg) as text) & "," & ((item 3 of bg) as text)
                        else
                            set AppleScript'"'"'s text item delimiters to ","
                            set parts to text items of saved
                            set AppleScript'"'"'s text item delimiters to ""
                            set bg to {(item 1 of parts) as integer, (item 2 of parts) as integer, (item 3 of parts) as integer}
                        end if
                        if (count of argv) < 4 then
                            set background color of s to bg
                            tell s to set variable named "user.crew_background" to ""
                            return
                        end if
                        set tint to {}
                        repeat with i from 1 to 3
                            set b to item i of bg
                            set k to ((item (i + 1) of argv) as integer) * 257
                            set end of tint to (b + ((k - b) / 8)) as integer
                        end repeat
                        set background color of s to tint
                        return' "$@" >/dev/null
}

# Names the tab of session <id>: iTerm2's AppleScript sets no tab's title
# an agent's titles would not overwrite, so the tab's name goes in the
# badges of its sessions, with each member's name, and here nothing is done.
iterm_tab() {
    :
}

# iTerm2 shares a row out evenly on its own.
iterm_even() {
    :
}

# Brings session <id> to the front: its window, its tab, and itself
# selected, and iTerm2 made the active application.
iterm_focus() {
    iterm_with "$1" 'tell w to select
                        tell t to select
                        tell s to select
                        activate
                        return' >/dev/null
}

# Closes session <id>.
iterm_close() {
    iterm_with "$1" 'tell s to close
                        return' >/dev/null
}

# iTerm2's AppleScript has no zoom: Maximize Active Pane is a menu item.
iterm_zoom() {
    echo "crew: iTerm2 zooms a pane only by hand: View > Maximize Active Pane (shift-cmd-return)" >&2
    return 1
}

# Opens a session beside the current one (split), in a new tab (tab), or
# right of, under, or over the iTerm2 pane <anchor> (beside, below,
# above), and types <line> into it.
iterm_spawn() {
    where=$1
    line=$2
    anchor=${3:-}
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
        open='tell s to set n to (split horizontally with default profile)
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
                        end try'
    else
        # Beside this pane while the tab holds an odd number, below it while
        # even: three or four panes make a grid, not a row of slivers.
        open='if (count of sessions of t) mod 2 = 1 then
                            tell s to set n to (split vertically with default profile)
                        else
                            tell s to set n to (split horizontally with default profile)
                        end if'
    fi
    # A new tab, or a split, takes the focus: it is given back, by unique
    # id, to the pane that held it in the anchor's tab, then to the tab
    # and the pane that held it in the window, even when the open fails.
    id=$(iterm_with "${me#iterm:}" "set fid to unique id of current session of t
                        set wid to unique id of current session of current tab of w
                        set failure to \"\"
                        try
                            $open
                            tell n to write text (item 2 of argv)
                        on error e
                            set failure to e
                        end try
                        repeat with w2 in windows
                            repeat with t2 in tabs of w2
                                repeat with x in sessions of t2
                                    if unique id of x is fid then tell x to select
                                end repeat
                            end repeat
                        end repeat
                        repeat with w2 in windows
                            repeat with t2 in tabs of w2
                                repeat with x in sessions of t2
                                    if unique id of x is wid then
                                        tell t2 to select
                                        tell x to select
                                    end if
                                end repeat
                            end repeat
                        end repeat
                        if failure is not \"\" then error failure
                        return unique id of n" "$line") || return
    echo "iterm:$id"
}

# Moves session <id> right of, under, or over session <anchor id> (beside,
# below, above), as term_move asks. iTerm2's move_session (3.5 and later)
# moves a session into a split of another: vertical: true beside it, false
# over or under it. Its docs read before: true as left or over, its code
# (3.5 to 3.7.5) as left or under, so the code's value goes first and the
# other only when the pane lands on the wrong side. Arguments to
# iterm_move_session: vertical, the side of the anchor the pane must end
# on in the order a tab lists its panes (from the top left, as iTerm2
# walks its splits), the two values of before:.
iterm_move() {
    im_pane=iterm:$1
    im_where=$2
    im_anchor=iterm:$3
    case "$im_where" in
    beside) set -- "$1" "$3" true after false true ;;
    above) set -- "$1" "$3" false before false true ;;
    below) set -- "$1" "$3" false after true false ;;
    esac
    im_verdict=$(iterm_move_session "$@") || {
        echo "crew: iTerm2 could not move $im_pane $im_where $im_anchor; it stays where iTerm2 left it (iTerm2 3.5 or later moves panes)" >&2
        return 1
    }
    case "$im_verdict" in
    placed) ;;
    unchanged)
        echo "crew: iTerm2 left $im_pane where it was: a locked layout, no room to split, or $im_where $im_anchor already" >&2
        return 3
        ;;
    *)
        echo "crew: iTerm2 moved $im_pane, but not $im_where $im_anchor; it stays where iTerm2 put it" >&2
        return 1
        ;;
    esac
}

# Moves the iTerm2 session <session> next to <anchor>: argv <session>
# <anchor> <vertical> <side> <before> <before>, as term_move says. Prints
# placed, unchanged, or elsewhere.
iterm_move_session() {
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
    set focused to item 4 of r
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
    -- The move hands the focus to the moved pane: give it back, to the
    -- pane that held it in the anchor's tab, then to the tab and the pane
    -- that held it in the anchor's window.
    my pick(cur)
    my show(focused)
    if failed then error why
    return verdict
end run

-- The tab that holds <dst>: each of its panes with its size, one a line;
-- the side of <dst> that <src> sits on in the order the tab lists them
-- (before, after, or apart); the tab's current pane; and the current pane
-- of its window's current tab.
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
                    return {out, side, unique id of current session of tab j of window i, unique id of current session of current tab of window i}
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

-- Makes the session <u> the current one of its window: its tab, then it.
on show(u)
    tell application "iTerm2"
        repeat with i from 1 to count of windows
            repeat with j from 1 to count of tabs of window i
                repeat with k from 1 to count of sessions of tab j of window i
                    if unique id of session k of tab j of window i is u then
                        tell tab j of window i to select
                        tell session k of tab j of window i to select
                        return
                    end if
                end repeat
            end repeat
        end repeat
    end tell
end show
EOF
}
