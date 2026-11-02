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
#                       and prints the new pane; the focus stays where it
#                       was, its window's tab and pane alike
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
#   <t>_even <id>       shares the pane's row out evenly among its panes,
#                       where the terminal does not on its own
#   <t>_focus <id>      brings the pane to the front: its window, its tab,
#                       and itself; a zoom lasts until the next focus
#   <t>_zoom <id>       shows the pane alone in its tab, where the terminal
#                       lets a script; fails saying so where it does not
#   <t>_close <id>      closes the pane, whatever runs in it: a caller makes
#                       sure nothing does
#
# <t>_move exits 3 when the terminal leaves the pane where it was, which a
# layout takes for a pane in its place already.
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

# One line a pane, tab-separated: the pane, its tty, its title; with
# <terminal> (iterm or tmux), that terminal's alone. Inside tmux, iTerm2 is
# not asked: when it runs, it is the window tmux runs in, its sessions none
# of the crew's, and asking it costs an AppleScript call that a busy iTerm2
# holds for its timeout. A terminal term_hold listed answers from that list.
term_list() {
    case "${1:-}" in
    iterm | tmux)
        case "$term_held_terms" in
        *" $1 "*) printf '%s' "$term_held" | grep "^$1:" || : ;;
        *) "${1}_list" ;;
        esac
        ;;
    *)
        [ -n "${TMUX:-}" ] || term_list iterm
        term_list tmux
        ;;
    esac
}

# Lists, once, the terminals that <pane>... are in, for the term_list,
# term_tty, and term_gone calls that follow in this shell and its
# subshells, until term_free: a round over many members asks each terminal
# once, not once a member, and an iTerm2 that does not answer holds it
# once. iTerm2 is asked only for an iTerm2 pane. A round that opens or
# closes a pane does not hold: the list would not show it.
term_held=""
term_held_terms=""
term_hold() {
    term_free
    th_terms=" "
    for th_pane in "$@"; do
        case "$th_pane" in
        iterm:* | tmux:*) ;;
        *) continue ;;
        esac
        case "$th_terms" in
        *" ${th_pane%%:*} "*) ;;
        *) th_terms="$th_terms${th_pane%%:*} " ;;
        esac
    done
    th_list=""
    for th_term in $th_terms; do
        th_list="$th_list$(term_list "$th_term")
"
    done
    term_held=$th_list
    term_held_terms=$th_terms
}

# term_hold for the panes kept one a file in <dir>, as a crew's panes/.
term_hold_dir() {
    # shellcheck disable=SC2046 # a pane is one word
    term_hold $(cat "$1"/* 2>/dev/null)
}

# Lets go of what term_hold listed: the terminals are asked again.
term_free() {
    term_held=""
    term_held_terms=""
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
    term=$(term_of "$1") || return 1
    panes=$(term_list "$term" 2>/dev/null) || panes=""
    printf '%s\n' "$panes" | grep -q "^${1%%:*}:" &&
        ! printf '%s\n' "$panes" | grep -q "^$1	"
}

# The tty of a pane, from the list.
term_tty() {
    term=$(term_of "$1") || return 1
    tty=$(term_list "$term" | awk -F '\t' -v p="$1" '$1 == p { print $2; exit }')
    [ -n "$tty" ] || {
        echo "crew: no pane $1" >&2
        return 1
    }
    echo "$tty"
}

# Whether something other than a shell runs in the foreground on <tty> (or
# <process> without another foreground program, beyond a keepawake helper like
# caffeinate, when <process> is given): the agent started there is up, so a
# line typed there reaches it, not the shell or a child editor.
term_running() {
    ps -t "${1#/dev/}" -o stat=,comm= 2>/dev/null | awk -v n="$#" -v p="${2:-}" '
        $1 ~ /\+/ {
            sub(/.*\//, "", $2)
            sub(/^-/, "", $2)
            if (n > 1) {
                if (p != "" && $2 == p) up = 1
                else if ($2 != "caffeinate") other = 1
            } else if ($2 !~ /^(sh|bash|zsh|fish|dash|ksh|tcsh|login|caffeinate)$/) {
                up = 1
            }
        }
        END { exit !(up && !other) }'
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

# Shares out the row of <pane> evenly, where the terminal does not.
term_even() {
    backend=$(term_of "$1") || return
    "${backend}_even" "${1#*:}"
}

# Brings <pane> to the front: its window, its tab, and itself.
term_focus() {
    backend=$(term_of "$1") || return
    "${backend}_focus" "${1#*:}"
}

# Closes <pane>. Nothing here asks what runs in it: crew down looks first.
term_close() {
    backend=$(term_of "$1") || return
    "${backend}_close" "${1#*:}"
}

# Shows <pane> alone in its tab, until the next focus.
term_zoom() {
    backend=$(term_of "$1") || return
    "${backend}_zoom" "${1#*:}"
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
# CR and LF become spaces; other control bytes belong to crew key.
term_poke() {
    poke_line=$(printf '%s' "$2" | tr '\r\n' '  ')
    if printf '%s' "$poke_line" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        echo "crew: poke refuses control bytes; use 'crew key' to press keys" >&2
        return 2
    fi
    term_type "$1" "$poke_line" || return 1
    sleep 0.5
    term_key "$1" enter || return 3
}
