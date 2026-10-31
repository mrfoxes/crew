# Terminal panes, in iTerm2 or in tmux: the contract both keep, and what
# is the same in both. A pane is "iterm:<session id>" or "tmux:<pane id>",
# and every pane is one the owner can see. Sourced by bin/crew.
#
# Each terminal keeps the contract in a file of its own, lib/term-iterm.sh
# and lib/term-tmux.sh, its functions named after it; the term_* functions
# here and in lib/layout.sh pick the one a pane's prefix names. For <t> in
# iterm and tmux, with <id> a pane without its prefix:
#
#   <t>_list            one line a pane, tab-separated: the pane, its tty,
#                       its title; nothing when the terminal is not running
#   <t>_read <id>       what the pane shows now
#   <t>_type <id> <text>
#                       types <text> into the pane, without Return
#   <t>_key <id> <key> <bytes>
#                       presses <key>, a name term_key knows, whose bytes
#                       are <bytes>
#   <t>_spawn <where> <line> [<anchor>]
#                       opens a pane beside the current one (split), in a
#                       new tab (tab), or right of, under, or over the pane
#                       <anchor> (beside, below, above), runs <line> there
#                       through the owner's shell, so the pane outlives it,
#                       and prints the new pane
#   <t>_move <id> <where> <anchor id>
#                       moves the pane right of, under, or over the other
#                       (beside, below, above), its agent running on; the
#                       pane keeps its id, and is never closed
#   <t>_name <id> <label>
#                       shows <label> on the pane where no agent's title
#                       reaches it; an empty label takes it off
#   <t>_color <id> [<color>]
#                       marks the pane with <color> (#rrggbb); none takes
#                       the mark off
#   <t>_tab <id> <name> names the tab the pane sits in, where the terminal
#                       keeps such a name; does nothing where it does not
#
# Each fails with a reason on stderr. Nothing outside lib/term*.sh drives
# iTerm2 or tmux.

. "$CREW_HOME/lib/term-iterm.sh"
. "$CREW_HOME/lib/term-tmux.sh"

# The terminal of <pane>, iterm or tmux, from its prefix.
term_of() {
    case "$1" in
    iterm:* | tmux:*) echo "${1%%:*}" ;;
    *)
        echo "crew: '$1' is not a pane" >&2
        return 1
        ;;
    esac
}

# One line a pane, tab-separated: the pane, its tty, its title.
term_list() {
    iterm_list
    tmux_list
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
    backend=$(term_of "$1") || return
    "${backend}_read" "${1#*:}"
}

# Types <text> into the pane, without Return.
term_type() {
    backend=$(term_of "$1") || return
    "${backend}_type" "${1#*:}" "$2"
}

# Shows <label> on the pane, out of its agent's reach; empty takes it off.
term_name() {
    backend=$(term_of "$1") || return
    "${backend}_name" "${1#*:}" "$2"
}

# Marks the pane with <color> (#rrggbb); no color takes the mark off.
term_color() {
    backend=$(term_of "$1") || return
    "${backend}_color" "${1#*:}" "${2:-}"
}

# Names the tab <pane> sits in, where the terminal can.
term_tab() {
    backend=$(term_of "$1") || return
    "${backend}_tab" "${1#*:}" "$2"
}

# Presses one key in the pane: enter, esc, tab, shift-tab, up, down, left,
# right, home, end, space, backspace, delete, ctrl-<letter>, alt-<letter>,
# or a single character.
term_key() {
    pane=$1
    case "$2" in
    enter) bytes=$(printf '\r') ;;
    esc) bytes=$(printf '\033') ;;
    tab) bytes=$(printf '\t') ;;
    shift-tab) bytes=$(printf '\033[Z') ;;
    up) bytes=$(printf '\033[A') ;;
    down) bytes=$(printf '\033[B') ;;
    right) bytes=$(printf '\033[C') ;;
    left) bytes=$(printf '\033[D') ;;
    home) bytes=$(printf '\033[H') ;;
    end) bytes=$(printf '\033[F') ;;
    space) bytes=' ' ;;
    backspace) bytes=$(printf '\177') ;;
    delete) bytes=$(printf '\033[3~') ;;
    ctrl-[a-z])
        letter=${2#ctrl-}
        bytes=$(printf "\\$(printf '%03o' $(($(printf '%d' "'$letter") - 96)))")
        ;;
    alt-[a-z]) bytes=$(printf '\033%s' "${2#alt-}") ;;
    ?) bytes=$2 ;;
    *)
        echo "crew: unknown key '$2'" >&2
        return 2
        ;;
    esac
    backend=$(term_of "$pane") || return
    "${backend}_key" "${pane#*:}" "$2" "$bytes"
}

# Types a line and presses Return, as the owner would. The two go apart: a
# TUI that gets both in one burst takes them for a paste and keeps the Return
# as a newline. A newline inside the line would submit it halfway.
term_poke() {
    term_type "$1" "$(printf '%s' "$2" | tr '\n' ' ')" || return
    sleep 0.5
    term_key "$1" enter
}
