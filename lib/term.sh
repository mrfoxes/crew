# Terminal panes: list them, find our own, read them, and type into them, in
# iTerm2 or in tmux. A pane is "iterm:<session id>" or "tmux:<pane id>", and
# every pane is one the owner can see. Sourced by bin/crew.

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

# One line a pane, tab-separated: the pane, its tty, its title.
term_list() {
    # Asking AppleScript does not launch iTerm2; pgrep does not always see it.
    if [ "$(osascript -e 'application "iTerm2" is running' 2>/dev/null)" = true ]; then
        osascript <<'EOF' | grep -v '^$'
-- Inside the tell, "tab" is iTerm2's tab: name the character before it.
set sep to ASCII character 9
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
EOF
    fi
    tmux list-panes -a -F 'tmux:#{pane_id}	#{pane_tty}	#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}' 2>/dev/null || true
}

# The pane this command runs in: tmux's and iTerm2's variables first, then,
# when an agent's sandbox dropped them, the tty of the nearest ancestor that
# belongs to a pane.
term_self() {
    # Codex runs commands through its app-server daemon: the variables name
    # the pane the daemon was started from, not this one.
    if [ -z "${CODEX_THREAD_ID:-}" ]; then
        if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
            echo "tmux:$TMUX_PANE"
            return
        fi
        if [ -n "${ITERM_SESSION_ID:-}" ]; then
            echo "iterm:${ITERM_SESSION_ID#*:}"
            return
        fi
    fi
    panes=$(term_list)
    pid=$$
    while [ "${pid:-1}" -gt 1 ]; do
        tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
        case "$tty" in
        "" | "??") ;;
        *)
            pane=$(printf '%s\n' "$panes" | awk -F '\t' -v t="/dev/$tty" '$2 == t { print $1; exit }')
            if [ -n "$pane" ]; then
                echo "$pane"
                return
            fi
            ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    return 1
}

# Whether <pane> is gone: its terminal lists its panes and it is not among
# them. A terminal that cannot be asked, from a sandbox, says nothing.
term_gone() {
    panes=$(term_list 2>/dev/null) || panes=""
    printf '%s\n' "$panes" | grep -q "^${1%%:*}:" &&
        ! printf '%s\n' "$panes" | grep -q "^$1	"
}

# The tty of a pane, from the list.
term_tty() {
    tty=$(term_list | awk -F '\t' -v p="$1" '$1 == p { print $2; exit }')
    [ -n "$tty" ] || {
        echo "crew: no pane $1" >&2
        return 1
    }
    echo "$tty"
}

# Whether something other than a shell runs in the foreground on <tty>: the
# agent started there is up, so a line typed there reaches it, not the
# shell.
term_running() {
    ps -t "${1#/dev/}" -o stat=,comm= 2>/dev/null | awk '
        $1 ~ /\+/ {
            sub(/.*\//, "", $2)
            sub(/^-/, "", $2)
            if ($2 !~ /^(sh|bash|zsh|fish|dash|ksh|tcsh|login)$/) up = 1
        }
        END { exit !up }'
}

# What the pane shows now.
term_read() {
    case "$1" in
    # iTerm2 fails a read now and then while a tab closes ("Invalid index"):
    # once more before giving up.
    iterm:*) iterm_with "${1#iterm:}" 'return contents of s' 2>/dev/null || { sleep 0.3; iterm_with "${1#iterm:}" 'return contents of s'; } ;;
    tmux:*) tmux capture-pane -p -t "${1#tmux:}" ;;
    *)
        echo "crew: '$1' is not a pane" >&2
        return 1
        ;;
    esac
}

# Types <text> into the pane, without Return.
term_type() {
    case "$1" in
    iterm:*) iterm_with "${1#iterm:}" 'tell s to write text (item 2 of argv) newline no
                        return' "$2" >/dev/null ;;
    tmux:*) tmux send-keys -t "${1#tmux:}" -l -- "$2" ;;
    *)
        echo "crew: '$1' is not a pane" >&2
        return 1
        ;;
    esac
}

# Presses one key in the pane: enter, esc, tab, shift-tab, up, down, left,
# right, home, end, space, backspace, delete, ctrl-<letter>, alt-<letter>,
# or a single character.
term_key() {
    pane=$1
    case "$2" in
    enter) bytes=$(printf '\r') tkey=Enter ;;
    esc) bytes=$(printf '\033') tkey=Escape ;;
    tab) bytes=$(printf '\t') tkey=Tab ;;
    shift-tab) bytes=$(printf '\033[Z') tkey=BTab ;;
    up) bytes=$(printf '\033[A') tkey=Up ;;
    down) bytes=$(printf '\033[B') tkey=Down ;;
    right) bytes=$(printf '\033[C') tkey=Right ;;
    left) bytes=$(printf '\033[D') tkey=Left ;;
    home) bytes=$(printf '\033[H') tkey=Home ;;
    end) bytes=$(printf '\033[F') tkey=End ;;
    space) bytes=' ' tkey=Space ;;
    backspace) bytes=$(printf '\177') tkey=BSpace ;;
    delete) bytes=$(printf '\033[3~') tkey=DC ;;
    ctrl-[a-z])
        letter=${2#ctrl-}
        bytes=$(printf "\\$(printf '%03o' $(($(printf '%d' "'$letter") - 96)))")
        tkey=C-$letter
        ;;
    alt-[a-z])
        letter=${2#alt-}
        bytes=$(printf '\033%s' "$letter")
        tkey=M-$letter
        ;;
    ?) bytes=$2 tkey="" ;;
    *)
        echo "crew: unknown key '$2'" >&2
        return 2
        ;;
    esac
    case "$pane" in
    tmux:*)
        if [ -n "$tkey" ]; then
            tmux send-keys -t "${pane#tmux:}" "$tkey"
        else
            tmux send-keys -t "${pane#tmux:}" -l -- "$bytes"
        fi
        ;;
    *) term_type "$pane" "$bytes" ;;
    esac
}

# Types a line and presses Return, as the owner would. The two go apart: a
# TUI that gets both in one burst takes them for a paste and keeps the Return
# as a newline. A newline inside the line would submit it halfway.
term_poke() {
    term_type "$1" "$(printf '%s' "$2" | tr '\n' ' ')" || return
    sleep 0.5
    term_key "$1" enter
}

# Opens a pane beside this one (split), in a new tab (tab), or under or over
# <pane> (below, above), runs <line> there through the owner's shell, so the
# pane outlives it, and prints the new pane.
term_spawn() {
    where=$1
    line=$2
    anchor=${3:-}
    if [ -n "${TMUX:-}" ]; then
        case "$where:$anchor" in
        tab:*) id=$(tmux new-window -P -F '#{pane_id}') ;;
        below:tmux:*) id=$(tmux split-window -v -t "${anchor#tmux:}" -P -F '#{pane_id}') ;;
        above:tmux:*) id=$(tmux split-window -v -b -t "${anchor#tmux:}" -P -F '#{pane_id}') ;;
        below:* | above:*)
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
    below:iterm:* | above:iterm:*) me=$anchor ;;
    below:* | above:*)
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
