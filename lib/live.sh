# The live board: crew board --live [seconds], the crew at a glance in a
# pane that stays up, redrawn every <seconds> (5). One line a member: its
# name, kind, tab, what its pane shows now, the Issue: line of its status,
# the status's age, and what it spent; then the lock, the relay, the last
# messages, and the last commit with its CI. Its variables start with v_.
# Sourced by bin/crew.

# What <name>'s pane shows now, in the crew <dir>: none (no pane), gone,
# exited (back to a shell), prompt (a prompt waits for an answer), working
# (the agent says esc interrupts it, or its screen changed since the last
# look), or idle. The screen's checksum is kept in tmp/live/<name> for the
# next look.
live_state() {
    v_pane=$(cat "$1/panes/$2" 2>/dev/null) || v_pane=""
    if [ -z "$v_pane" ]; then
        echo none
        return
    fi
    if ! v_tty=$(term_tty "$v_pane" 2>/dev/null); then
        echo gone
        return
    fi
    if ! term_running "$v_tty"; then
        echo exited
        return
    fi
    if ! v_screen=$(term_read "$v_pane" 2>/dev/null); then
        echo gone
        return
    fi
    mkdir -p "$1/tmp/live"
    v_sum=$(printf '%s' "$v_screen" | cksum | cut -d' ' -f1)
    v_was=$(cat "$1/tmp/live/$2" 2>/dev/null) || v_was=""
    echo "$v_sum" >"$1/tmp/live/$2"
    if [ -n "$(printf '%s\n' "$v_screen" | gate_prompt)" ]; then
        echo prompt
    elif printf '%s\n' "$v_screen" | grep -q 'esc to interrupt' || { [ -n "$v_was" ] && [ "$v_sum" != "$v_was" ]; }; then
        echo working
    else
        echo idle
    fi
}

# The members of the crew <dir> in the board's order: each tab's members as
# the tab lists them, then those in no tab, by name.
live_members() {
    {
        for v_file in "$1"/tabs/*; do
            [ -f "$v_file" ] || continue
            cat "$v_file"
        done
        for v_file in "$1"/panes/* "$1"/status/*.md; do
            [ -e "$v_file" ] || continue
            basename "$v_file" .md
        done | sort
    } | awk '!/:/ && NF && !seen[$0]++'
}

# What each member spent, "<name> <amount>" a line, dollars where the rates
# price its model, else tokens: worked out once a minute at most, since it
# reads every agent's logs, and kept in tmp/live.cost.
live_costs() {
    v_cache=$1/tmp/live.cost
    if [ ! -f "$v_cache" ] || [ "$(($(date +%s) - $(crew_mtime "$v_cache")))" -ge 60 ]; then
        # shellcheck disable=SC2046 # member names hold no space
        set -- "$1" $(cost_members "$1")
        if [ $# -gt 1 ]; then
            v_dir=$1
            shift
            cost_sum board "$v_dir" "$@" | awk '$3 == "tokens" { print $1, ($4 ~ /^\$/ ? $4 : $2) }' >"$v_cache.new" 2>/dev/null || :
            mv "$v_cache.new" "$v_cache"
        else
            : >"$v_cache"
        fi
    fi
    cat "$v_cache"
}

# The last commit and its CI, worked out once a minute at most: gh asks
# the network. Kept in tmp/live.git.
live_git() {
    v_cache=$1/tmp/live.git
    if [ ! -f "$v_cache" ] || [ "$(($(date +%s) - $(crew_mtime "$v_cache")))" -ge 60 ]; then
        v_root=$(crew_project "$1")
        {
            git -C "$v_root" log --oneline -1 2>/dev/null || :
            (cd "$v_root" && gh run list --limit 1 2>/dev/null | head -n 1 | cut -f1,2 | tr '\t' ' ') || :
        } >"$v_cache"
    fi
    cat "$v_cache"
}

# One frame of the live board of the crew <dir>, each line cut to <width>.
live_frame() {
    v_dir=$1
    v_costs=$(live_costs "$v_dir")
    printf '%-9s %-7s %-8s %-8s %-28s %4s %s\n' member kind tab state issue age spent
    for v_name in $(live_members "$v_dir"); do
        v_kind=$(kind_member "$v_dir" "$v_name")
        v_tab=$(tab_of "$v_dir" "$v_name")
        v_state=$(live_state "$v_dir" "$v_name")
        v_status=$v_dir/status/$v_name.md
        v_issue=-
        v_age=-
        if [ -f "$v_status" ]; then
            v_issue=$(sed -n 's/^Issue:[[:space:]]*//p' "$v_status" | head -n 1)
            v_age="$(crew_age "$v_status")m"
        fi
        [ -e "$v_dir/muted/$v_name" ] && v_state="$v_state*"
        v_spent=$(printf '%s\n' "$v_costs" | awk -v n="$v_name" '$1 == n { print $2; exit }')
        v_budget=$(crewfile_get "$v_dir" "$v_name" budget)
        [ -z "$v_budget" ] || v_spent="${v_spent:--}/$v_budget"
        printf '%-9s %-7s %-8s %-8s %-28.28s %4s %s\n' "$v_name" "${v_kind:--}" "${v_tab:--}" "$v_state" "${v_issue:--}" "$v_age" "${v_spent:--}"
    done
    echo
    if [ -d "$v_dir/lock" ]; then
        echo "lock: held by $(cat "$v_dir/lock/owner" 2>/dev/null || echo someone), $(crew_age "$v_dir/lock") min"
    else
        echo "lock: free"
    fi
    if crew_relay_alive "$v_dir"; then echo "relay: running"; else echo "relay: off"; fi
    for v_n in $(ls "$v_dir/seq" 2>/dev/null | sort -n | tail -n 3); do
        sed -n '1s/^# //p' "$v_dir/seq/$v_n"
    done
    live_git "$v_dir"
}

# crew board --live [seconds]: draws a frame, then again every <seconds>,
# until ctrl-c. A frame is worked out before the screen is cleared, so the
# pane never shows half of one. A narrow pane cuts each line at its right.
crew_board_live() {
    crew_count "${1:-5}" "crew board --live [seconds]" positive || return 2
    v_every=$count_n
    dir=$(crew_dir) || return 1
    trap 'echo; exit' INT TERM
    while :; do
        v_width=$(tput cols 2>/dev/null) || v_width=80
        v_frame=$(live_frame "$dir" | cut -c "1-${v_width:-80}")
        printf '\033[H\033[2J%s\n' "$v_frame"
        sleep "$v_every"
    done
}
