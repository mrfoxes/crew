# tmux's half of the terminal contract (lib/term.sh): its panes listed,
# read, typed into, opened, and moved. <id> is tmux's pane id (%5).
# Sourced by lib/term.sh.

tmux_list() {
    tmux list-panes -a -F 'tmux:#{pane_id}	#{pane_tty}	#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}' 2>/dev/null || true
}

tmux_read() {
    tmux capture-pane -p -t "$1"
}

tmux_type() {
    tmux send-keys -t "$1" -l -- "$2"
}

# Presses <key> (crew's name for it) by tmux's name for it; a single
# character goes as itself.
tmux_key() {
    case "$2" in
    enter) tkey=Enter ;;
    esc) tkey=Escape ;;
    tab) tkey=Tab ;;
    shift-tab) tkey=BTab ;;
    up) tkey=Up ;;
    down) tkey=Down ;;
    right) tkey=Right ;;
    left) tkey=Left ;;
    home) tkey=Home ;;
    end) tkey=End ;;
    space) tkey=Space ;;
    backspace) tkey=BSpace ;;
    delete) tkey=DC ;;
    ctrl-[a-z]) tkey=C-${2#ctrl-} ;;
    alt-[a-z]) tkey=M-${2#alt-} ;;
    *) tkey="" ;;
    esac
    if [ -n "$tkey" ]; then
        tmux send-keys -t "$1" "$tkey"
    else
        tmux send-keys -t "$1" -l -- "$3"
    fi
}

# Opens a pane beside the current one (split), in a new window (tab), or
# right of, under, or over the tmux pane <anchor> (beside, below, above),
# and types <line> into it. -d leaves the focus where it was: the new
# window does not become the current one, nor the new pane the active one.
tmux_spawn() {
    where=$1
    line=$2
    anchor=${3:-}
    case "$where:$anchor" in
    tab:*) id=$(tmux new-window -d -P -F '#{pane_id}') ;;
    beside:tmux:*) id=$(tmux split-window -d -h -t "${anchor#tmux:}" -P -F '#{pane_id}') && tmux_even "$id" ;;
    below:tmux:*) id=$(tmux split-window -d -v -t "${anchor#tmux:}" -P -F '#{pane_id}') ;;
    above:tmux:*) id=$(tmux split-window -d -v -b -t "${anchor#tmux:}" -P -F '#{pane_id}') ;;
    beside:* | below:* | above:*)
        echo "crew: $anchor is not a tmux pane" >&2
        return 1
        ;;
    *) id=$(tmux split-window -d -P -F '#{pane_id}') && tmux select-layout tiled >/dev/null ;;
    esac || return
    tmux send-keys -t "$id" -l -- "$line" && tmux send-keys -t "$id" Enter
    echo "tmux:$id"
}

# Spreads tmux pane <id> and the panes beside it out evenly, as iTerm2 does
# with a pane split beside another: a row of a table, not halves of halves.
# tmux before 3.1 has no -E, and keeps the halves.
tmux_even() {
    tmux select-layout -E -t "$1" >/dev/null 2>&1 || :
}

# Moves pane <id> beside, below, or above <anchor id>. join-pane moves the
# pane itself (-d: the focus stays), and -b puts it before the target, over
# it here.
tmux_move() {
    case "$2" in
    beside) tmux join-pane -d -h -s "$1" -t "$3" && tmux_even "$1" ;;
    below) tmux join-pane -d -v -s "$1" -t "$3" ;;
    above) tmux join-pane -d -v -b -s "$1" -t "$3" ;;
    esac
}

# The label of every pane in a window crew names one in: its member's name,
# in its kind's color when it has one, then the title its agent sets. Both
# live in the pane's own options, which no agent's escape sequence reaches.
tmux_border=' #{?@crew_name,#{?@crew_color,#[fg=#{@crew_color}#,bold],#[bold]}#{@crew_name}#[default] · ,}#{pane_title} '

# Shows <label> on pane <id>, in the status line of its border, which crew
# turns on for the pane's window; an empty label takes it off.
tmux_name() {
    if [ -z "$2" ]; then
        tmux set-option -p -u -t "$1" @crew_name
        return
    fi
    tmux set-option -p -t "$1" @crew_name "$2" &&
        tmux set-option -w -t "$1" pane-border-status top &&
        tmux set-option -w -t "$1" pane-border-format "$tmux_border"
}

# Colors pane <id>'s label <color> (#rrggbb); no color takes it off.
tmux_color() {
    if [ -z "$2" ]; then
        tmux set-option -p -u -t "$1" @crew_color
    else
        tmux set-option -p -t "$1" @crew_color "$2"
    fi
}

# Names the window of pane <id> <name>, and keeps the name: neither tmux
# nor a program in it renames the window after.
tmux_tab() {
    tmux rename-window -t "$1" "$2" &&
        tmux set-option -w -t "$1" automatic-rename off &&
        tmux set-option -w -t "$1" allow-rename off
}

# Brings pane <id> to the front: its session, when it is another one, its
# window, and itself. A window zoomed is let go: a zoom lasts until the
# next focus.
tmux_focus() {
    tmux switch-client -t "$1" 2>/dev/null || :
    tmux select-window -t "$1" && tmux select-pane -t "$1" || return
    [ "$(tmux display-message -p -t "$1" '#{window_zoomed_flag}')" != 1 ] || tmux resize-pane -Z -t "$1"
}

# Closes pane <id>.
tmux_close() {
    tmux kill-pane -t "$1"
}

# Shows pane <id> alone in its window, until the next focus.
tmux_zoom() {
    [ "$(tmux display-message -p -t "$1" '#{window_zoomed_flag}')" = 1 ] || tmux resize-pane -Z -t "$1"
}
