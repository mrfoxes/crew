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
    tm_pane=$1
    tm_where=$2
    tm_anchor=$3
    case "$tm_where" in
    beside | below | above) ;;
    *)
        echo "crew: a pane moves beside, below, or above another, not '$tm_where'" >&2
        return 2
        ;;
    esac
    if [ "$tm_pane" = "$tm_anchor" ]; then
        echo "crew: $tm_pane cannot move next to itself" >&2
        return 1
    fi
    tm_backend=$(term_of "$tm_pane") || return
    if [ "$(term_of "$tm_anchor" 2>/dev/null)" != "$tm_backend" ]; then
        echo "crew: $tm_pane and $tm_anchor are not panes of one terminal" >&2
        return 1
    fi
    "${tm_backend}_move" "${tm_pane#*:}" "$tm_where" "${tm_anchor#*:}"
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

# The members of <tab>, in the order they were placed; nothing for a tab
# crew does not know.
tab_members() {
    cat "$1/tabs/$2" 2>/dev/null || :
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
        t_pane=$(tab_pane "$1" "$t_member")
        [ -n "$t_pane" ] || continue
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

# Layouts: the panes of a tab arranged as rows, by one command, their
# agents running on. A layout is one of these, recorded for its tab in
# layouts/<tab> so that a member spawned there later, or a pane closed,
# is placed again by it:
#
#   table             a row for each kind, in the order the kinds first
#                     sit in the tab, a row's panes in the tab's order
#   grid              as square as the count allows: five panes are three
#                     over two
#   <columns>x<rows>  rows of <columns> panes, filled in the tab's order
#   main              the tab's first pane whole on the left, the others
#                     one over another beside it, as tmux's main-vertical
#   a,b,c / d,e       the members named, a row between slashes
#
# A tab's entries are member names, or panes (iterm:<id>, tmux:<id>) for a
# pane no member sits in, such as the coordinator's.

# The pane of <entry> in the crew <dir>: a member's, or the entry itself
# when it is a pane; nothing for a member with no pane.
tab_pane() {
    case "$2" in
    iterm:* | tmux:*) echo "$2" ;;
    *) cat "$1/panes/$2" 2>/dev/null || : ;;
    esac
}

# Whether <layout> is one crew knows: table, grid, main, <columns>x<rows>
# (digits, an x, digits), or names in rows, a comma or a slash among them.
layout_known() {
    case "$1" in
    table | grid | main | *,* | */*) return 0 ;;
    *[!0-9x]* | x* | *x | *x*x*) return 1 ;;
    *x*) return 0 ;;
    esac
    return 1
}

# The rows of <layout> for the crew <dir>'s entries given after it, one row
# a line, its entries apart by spaces; main's first line is "main <entry>".
layout_rows() {
    l_dir=$1
    l_layout=$2
    shift 2
    case "$l_layout" in
    *,* | */*)
        printf '%s\n' "$l_layout" | tr '/' '\n' | tr ',' ' ' | awk 'NF { $1 = $1; print }'
        return
        ;;
    table)
        for l_entry in "$@"; do
            case "$l_entry" in
            iterm:* | tmux:*) l_kind=other ;;
            *) l_kind=$(kind_member "$l_dir" "$l_entry") ;;
            esac
            printf '%s %s\n' "${l_kind:-other}" "$l_entry"
        done | awk '
            !($1 in row) { order[++n] = $1 }
            { row[$1] = row[$1] (row[$1] == "" ? "" : " ") $2 }
            END { for (i = 1; i <= n; i++) print row[order[i]] }'
        return
        ;;
    main)
        [ $# -gt 0 ] || return 0
        echo "main $1"
        shift
        l_layout=1x$#
        ;;
    esac
    [ $# -gt 0 ] || return 0
    case "$l_layout" in
    grid) l_columns=$(awk -v n=$# 'BEGIN { c = int(sqrt(n)); if (c * c < n) c++; print c }') ;;
    *) l_columns=${l_layout%%x*} ;;
    esac
    printf '%s\n' "$@" | awk -v c="$l_columns" '
        { line = line (line == "" ? "" : " ") $0; if (NR % c == 0) { print line; line = "" } }
        END { if (line != "") print line }'
}

# The moves that lay out the rows on stdin, each "<entry> <where>
# <anchor>": with main, the first row's first entry beside the main one;
# then the first entry of every next row under the first of the row
# before, so that each spans the width; then each row filled rightward.
layout_moves() {
    awk '
        $1 == "main" { main = $2; next }
        { rows[++n] = $0 }
        END {
            for (i = 1; i <= n; i++) first[i] = substr(rows[i], 1, index(rows[i] " ", " ") - 1)
            if (main != "" && n > 0) print first[1], "beside", main
            for (i = 2; i <= n; i++) print first[i], "below", first[i - 1]
            for (i = 1; i <= n; i++) {
                m = split(rows[i], e, " ")
                for (j = 2; j <= m; j++) print e[j], "beside", e[j - 1]
            }
        }'
}

# Lays out <tab> of the crew <dir> by <layout>, or by the one recorded for
# it, with the entries whose pane is still there: a closed pane leaves no
# hole. A move the terminal refuses is said and the next ones still made;
# fails when one was refused.
layout_apply() {
    l_dir=$1
    l_tab=$2
    l_layout=${3:-}
    [ -n "$l_layout" ] || l_layout=$(cat "$l_dir/layouts/$l_tab" 2>/dev/null) || l_layout=""
    [ -n "$l_layout" ] || return 0
    l_entries=""
    for l_entry in $(tab_members "$l_dir" "$l_tab"); do
        l_pane=$(tab_pane "$l_dir" "$l_entry")
        [ -n "$l_pane" ] && ! term_gone "$l_pane" && l_entries="$l_entries $l_entry"
    done
    # shellcheck disable=SC2086 # the entries are names and panes, one a word
    l_rows=$(layout_rows "$l_dir" "$l_layout" $l_entries)
    l_status=0
    l_moves=$(printf '%s\n' "$l_rows" | layout_moves)
    while read -r l_entry l_where l_anchor; do
        [ -n "$l_entry" ] || continue
        l_pane=$(tab_pane "$l_dir" "$l_entry")
        l_to=$(tab_pane "$l_dir" "$l_anchor")
        if [ -z "$l_pane" ] || [ -z "$l_to" ]; then
            echo "crew: $l_entry or $l_anchor has no pane; the layout of $l_tab goes on without it" >&2
            l_status=1
            continue
        fi
        # A pane already in its place is left there: iTerm2 says so with 3.
        term_move "$l_pane" "$l_where" "$l_to" 2>"$l_dir/tmp/layout.err"
        case $? in
        0 | 3) ;;
        *)
            cat "$l_dir/tmp/layout.err" >&2
            l_status=1
            ;;
        esac
    done <<EOM
$l_moves
EOM
    rm -f "$l_dir/tmp/layout.err"
    for l_row in $(printf '%s\n' "$l_rows" | awk '$1 != "main" { print $1 }'); do
        term_even "$(tab_pane "$l_dir" "$l_row")" 2>/dev/null || :
    done
    return "$l_status"
}

# crew layout [<layout>] [--tab <tab>]: lays out a tab, or every tab with a
# layout recorded; with a layout, records it for the tab. The panes of a
# list of names go to the tab of the first one named.
crew_layout() {
    dir=$(crew_dir) || return 1
    l_tab=""
    l_layout=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --tab)
            shift
            l_tab=${1:-}
            crew_name "$l_tab" || return 2
            ;;
        *) l_layout="$l_layout${l_layout:+ }$1" ;;
        esac
        shift
    done
    if [ -n "$l_layout" ] && ! layout_known "$l_layout"; then
        echo "usage: crew layout [table | grid | main | <columns>x<rows> | <a>,<b> / <c>,<d>] [--tab <tab>]" >&2
        return 2
    fi
    case "$l_layout" in
    *,* | */*)
        # The members named sit in the tab of the first one, in this order.
        # shellcheck disable=SC2046 # the names, one a word
        set -- $(printf '%s\n' "$l_layout" | tr '/,' '  ')
        for l_member in "$@"; do
            crew_member "$l_member" || return 2
            [ -n "$(tab_pane "$dir" "$l_member")" ] || {
                echo "crew: $l_member has no pane" >&2
                return 1
            }
        done
        [ -n "$l_tab" ] || l_tab=$(tab_of "$dir" "$1")
        l_tab=${l_tab:-main}
        for l_member in "$@"; do
            tab_add "$dir" "$l_tab" "$l_member"
        done
        ;;
    esac
    if [ -n "$l_layout" ]; then
        if [ -z "$l_tab" ]; then
            echo "crew: which tab? 'crew layout $l_layout --tab <tab>'" >&2
            return 2
        fi
        [ -f "$dir/tabs/$l_tab" ] || {
            echo "crew: no tab $l_tab: see 'crew panes'" >&2
            return 1
        }
        mkdir -p "$dir/layouts"
        echo "$l_layout" >"$dir/layouts/$l_tab"
        layout_apply "$dir" "$l_tab" && echo "$l_tab: $l_layout"
        return
    fi
    l_failed=0
    for l_file in "$dir"/layouts/*; do
        [ -f "$l_file" ] || continue
        l_t=$(basename "$l_file")
        [ -z "$l_tab" ] || [ "$l_t" = "$l_tab" ] || continue
        if layout_apply "$dir" "$l_t"; then
            echo "$l_t: $(cat "$l_file")"
        else
            l_failed=1
        fi
    done
    return "$l_failed"
}
