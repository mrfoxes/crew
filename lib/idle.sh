# Idle members: what a member's pane shows, in one word, from looks that
# never wait (lib/screen.sh's screen_of on one styled read, and a checksum
# of the last look), and whether a member idle at its prompt has nothing
# to do (idle_free). The board, the live board, and the watch read them.
# Its variables start with id_. Sourced by bin/crew.

# What <name>'s pane in the crew <dir> shows now, in one word: none (no
# pane), gone, unknown (a kind with no input mark), exited (no agent of its
# kind in the foreground), or what screen_of says of one look; an idle or
# shell screen that changed since the look whose checksum <file> keeps is
# working. The look's checksum goes to <file> for the next one.
idle_look() {
    id_pane=$(cat "$1/panes/$2" 2>/dev/null) || id_pane=""
    if [ -z "$id_pane" ]; then
        echo none
        return
    fi
    # A pane the terminal does not list, or cannot read, is gone.
    if ! term_tty "$id_pane" >/dev/null 2>&1 ||
        ! id_screen=$(term_read_styled "$id_pane" 2>/dev/null); then
        echo gone
        return
    fi
    id_kind=$(kind_member "$1" "$2")
    if [ -z "$(kind_field "$id_kind" idle)" ]; then
        echo unknown
        return
    fi
    if ! pane_agent "$1" "$2" "$id_pane"; then
        echo exited
        return
    fi
    mkdir -p "$(dirname "$3")"
    id_sum=$(printf '%s' "$id_screen" | cksum | cut -d' ' -f1)
    id_was=$(cat "$3" 2>/dev/null) || id_was=""
    echo "$id_sum" >"$3"
    id_word=$(printf '%s\n' "$id_screen" | screen_of "$id_kind")
    case "$id_word" in
    idle | shell)
        if [ -n "$id_was" ] && [ "$id_sum" != "$id_was" ]; then
            id_word=working
        fi
        ;;
    esac
    echo "$id_word"
}

# "<name> <word>" for each <name>... of the crew <dir>, from two looks: the
# second, screen_pause after the first, only at the panes the first found
# idle or shell, and only one pause for all of them, so that a board of
# many members waits two seconds, not two seconds each.
idle_states() {
    id_dir=$1
    shift
    id_tmp=$(mktemp -d "$id_dir/tmp/idle.XXXXXX") || return 1
    id_again=""
    for id_m in "$@"; do
        id_w=$(idle_look "$id_dir" "$id_m" "$id_tmp/$id_m")
        echo "$id_w" >"$id_tmp/$id_m.word"
        case "$id_w" in idle | shell) id_again="$id_again $id_m" ;; esac
    done
    if [ -n "$id_again" ]; then
        screen_pause
        for id_m in $id_again; do
            idle_look "$id_dir" "$id_m" "$id_tmp/$id_m" >"$id_tmp/$id_m.word"
        done
    fi
    for id_m in "$@"; do
        echo "$id_m $(cat "$id_tmp/$id_m.word")"
    done
    rm -rf "$id_tmp"
}

# What the stream says of <name> in the crew <dir>, from one pass over the
# headers: "<unread> <number of its last message, 0 for none> <the first
# word of that message's subject, - for none>".
idle_stream() {
    id_cur=$(cat "$1/cursors/$2" 2>/dev/null) || id_cur=0
    if [ -z "$(ls "$1/seq" 2>/dev/null)" ]; then
        echo "0 0 -"
        return
    fi
    (cd "$1/seq" && awk -v me="$2" -v cur="${id_cur:-0}" '
        FNR == 1 {
            # Not FILENAME + 0: macOS awk keeps the number of the first.
            n = substr(FILENAME, 1) + 0
            if ($1 != "#" || $4 != "to") next
            to = $5
            sub(/:$/, "", to)
            if ($3 == me) {
                if (n > last) { last = n; word = $6 }
            } else if (n > cur + 0 && (to == me || to == "all")) {
                unread++
            }
        }
        END { print unread + 0, last + 0, (last ? word : "-") }' *)
}

# Whether <name> of the crew <dir>, whose pane shows <word>, sits idle with
# nothing to do: idle at an empty prompt (not typed, not a background shell),
# not muted (a muted member is idle by design, woken only by its name), no
# message unread, its last message an Idle: or none at all, and no commit
# waiting for its review. A member whose last message is Done: has ended
# its work, and is not counted. The cheap checks come first.
idle_free() {
    [ "$3" = idle ] || return 1
    [ ! -e "$1/muted/$2" ] || return 1
    # shellcheck disable=SC2046 # three words, none with a space
    set -- "$1" "$2" $(idle_stream "$1" "$2")
    [ "$3" = 0 ] || return 1
    [ "$4" = 0 ] || [ "$5" = Idle: ] || return 1
    ! crew_reviews "$1" | cut -f3 | grep -qx -- "$2"
}

# The minutes <name> of the crew <dir> has had nothing to do, from its last
# message, or from its status when it sent none; nothing when it has
# neither.
idle_minutes() {
    # shellcheck disable=SC2046 # three words, none with a space
    set -- "$1" "$2" $(idle_stream "$1" "$2")
    if [ "$4" != 0 ]; then
        crew_age "$1/seq/$4"
    elif [ -f "$1/status/$2.md" ]; then
        crew_age "$1/status/$2.md"
    fi
}

# How the board says <name>'s <word>: the word, "idle (muted)" for a muted
# member at its prompt, and "idle, nothing to do for <n> min" for a free one.
idle_said() {
    if [ "$3" = idle ] && [ -e "$1/muted/$2" ]; then
        echo "idle (muted)"
    elif idle_free "$1" "$2" "$3"; then
        id_min=$(idle_minutes "$1" "$2")
        echo "idle, nothing to do${id_min:+ for $id_min min}"
    else
        echo "$3"
    fi
}
