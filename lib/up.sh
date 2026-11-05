# Bringing a crew up from its Crewfile (lib/crewfile.sh): the coordinator's
# tab, a tab per lane, each member spawned, named, invited, and laid out,
# and run again, only what is missing brought back. Its variables start
# with u_. Sourced by bin/crew.

# Runs <command>..., or with --dry prints it as the owner would type it:
# crew_spawn as crew spawn, term_tab as the tab it names.
up_do() {
    if [ -n "$u_dry" ]; then
        case "$1" in
        term_tab)
            echo "name the tab of $2 $3"
            return 0
            ;;
        esac
        u_words="crew ${1#crew_}"
        shift
        for u_word in "$@"; do
            u_words="$u_words $(shell_word "$u_word")"
        done
        echo "$u_words"
        return 0
    fi
    "$@"
}

# The Crewfile crew up reads for the crew <dir>, and the preset <preset> it
# starts from when the crew has none: the crew's own file is the truth, so
# a preset never replaces it. Prints the path to read.
up_crewfile() {
    u_file=$(crewfile_path "$1")
    if [ -z "$2" ]; then
        if [ ! -f "$u_file" ]; then
            echo "crew: no Crewfile in $1: write one, or start from a preset with 'crew up <preset>'" >&2
            up_presets >&2
            return 1
        fi
        echo "$u_file"
        return
    fi
    u_preset=$(crewfile_preset "$2")
    if [ ! -f "$u_preset" ]; then
        echo "crew: no preset $2 at $u_preset" >&2
        up_presets >&2
        return 1
    fi
    if [ -f "$u_file" ]; then
        if cmp -s "$u_preset" "$u_file"; then
            echo "$u_file"
            return
        fi
        echo "crew: this crew has its Crewfile ($u_file): edit it, or remove it to start from $2" >&2
        return 1
    fi
    if [ -n "$u_dry" ]; then
        echo "$u_preset"
        return
    fi
    cp "$u_preset" "$u_file" && echo "$u_file"
}

# The presets there are: the owner's and the ones crew ships.
up_presets() {
    u_list=$(crewfile_preset_names | tr '\n' ' ')
    [ -z "$u_list" ] || echo "crew: presets: $u_list"
}

# Stops, before anything opens, when a member of the records <records> runs
# an agent that is not installed: its first word is no command. Says which.
up_agents() {
    u_missing=""
    while IFS='	' read -r u_what _ u_name _ _ _ _ _ _ _ u_line; do
        [ "$u_what" = member ] && [ "$u_line" != - ] || continue
        # shellcheck disable=SC2086 # the first word of the line
        set -- $u_line
        command -v "$1" >/dev/null 2>&1 || u_missing="$u_missing
crew: $u_name runs $1, which is not installed"
    done <<EOR
$1
EOR
    [ -z "$u_missing" ] && return 0
    printf '%s\n' "${u_missing#
}" >&2
    return 1
}

# Whether <member> of the crew <dir> has a pane still there.
up_alive() {
    u_pane=$(cat "$1/panes/$2" 2>/dev/null) || return 1
    [ -n "$u_pane" ] && ! term_gone "$u_pane"
}

# Whether <member> of the crew <dir> has an agent running in its pane, not
# only a shell. A terminal that cannot be asked, from a sandbox, is taken
# as running so that nothing is typed into it.
up_running() {
    u_pane=$(cat "$1/panes/$2" 2>/dev/null) || return 1
    u_tty=$(term_tty "$u_pane" 2>/dev/null) || return 0
    term_running "$u_tty"
}

# The conversation recorded for <member> of <kind> in the crew <dir>: a
# Claude Code session, a Codex thread, or the Antigravity conversation that
# began with 'crew join <member>'.
up_conversation() {
    case "$3" in
    claude) cat "$1/sessions/$2" 2>/dev/null || : ;;
    codex) cat "$1/threads/$2" 2>/dev/null || : ;;
    agy)
        u_db=$(cost_agy_db "$2" 2>/dev/null) || u_db=""
        [ -z "$u_db" ] || basename "$u_db" .db
        ;;
    *) cat "$1/sessions/$2" "$1/threads/$2" 2>/dev/null | head -n 1 || : ;;
    esac
}

# <line> for <member> in the crew <dir>, with its kind's resume argument
# when the kind has one, crew knows the conversation, and --fresh was not
# given. <kind> is the Crewfile's kind= or -.
up_resume() {
    if [ -n "$u_fresh" ]; then
        printf '%s\n' "$4"
        return
    fi
    u_kind=$3
    [ "$u_kind" != - ] || u_kind=$(kind_member "$1" "$2")
    [ -n "$u_kind" ] || u_kind=$(kind_of_line "$4")
    u_fmt=$(kind_field "$u_kind" resume)
    u_conv=""
    [ -z "$u_fmt" ] || u_conv=$(up_conversation "$1" "$2" "$u_kind")
    if [ -z "$u_fmt" ] || [ -z "$u_conv" ]; then
        printf '%s\n' "$4"
        return
    fi
    # shellcheck disable=SC2059 # the kind's resume template holds %s
    u_flag=$(printf -- "$u_fmt" "$(shell_word "$u_conv")")
    printf '%s %s\n' "$4" "$u_flag"
}

# The most looks, each about 2 seconds, that a restart waits for the agent
# to leave after its quit command, and then for the agent started on its
# line to be idle at its prompt: about half a minute, and a minute.
up_quit_looks=15
up_start_looks=30

# Refuses, before crew up does anything, a --restart name that is no member
# of the Crewfile <file>'s <records>, or a member started and joined by hand.
up_restartable() {
    for u_rn in $u_restart; do
        u_rl=$(printf '%s\n' "$2" | awk -F '\t' -v m="$u_rn" '
            $1 == "member" && $3 == m { found = 1; print $11; exit }
            END { if (!found) print "?" }')
        case "$u_rl" in
        "?")
            echo "crew: $u_rn is no member of $1: nothing was restarted" >&2
            return 1
            ;;
        -)
            echo "crew: $u_rn is started and joined by hand ($1 gives it no line): crew up cannot restart it" >&2
            return 1
            ;;
        esac
    done
}

# Records <line> as the Crewfile line <member> was started with, in
# lines/<member>, for crew up to say when it changes. Not in a dry run.
up_started() {
    [ -z "$u_dry" ] || return 0
    mkdir -p "$dir/lines"
    printf '%s\n' "$2" >"$dir/lines/$1"
}

# Says, touching nothing, when the live <member>'s Crewfile <line> is not
# the one it was started with.
up_changed() {
    [ -f "$dir/lines/$1" ] || return 0
    [ "$(cat "$dir/lines/$1")" != "$2" ] || return 0
    echo "crew: $1's Crewfile line changed since it started; 'crew up --restart $1' restarts it"
}

# Restarts the live agent of <member>, of the Crewfile's <kind> (or -), on
# its Crewfile <line>, in its own pane: only at its idle prompt with no
# background shell, as lib/context.sh's context_start says, and with --fresh
# only when its Next: can say where its work is (context_landed). Wakes to
# it are held meanwhile. It types the kind's quit command, waits for the
# shell, types the line with the kind's resume argument (up_resume), and
# waits for the agent's prompt. A subshell keeps the hold's traps and the
# cx_ variables in it.
# shellcheck disable=SC2154 # the cx_ variables are set by context_start, in lib/context.sh
up_restart() (
    if [ -n "$u_dry" ]; then
        u_k=$2
        [ "$u_k" != - ] || u_k=$(kind_member "$dir" "$1")
        [ -n "$u_k" ] || u_k=$(kind_of_line "$3")
        u_q=$(context_command "$u_k" restart) || u_q="its quit command"
        echo "restart $1 in its pane: $u_q, then $(up_resume "$dir" "$1" "$2" "$3")"
        exit 0
    fi
    # context_start takes the hold, and every path after it ends with
    # context_end, which releases it.
    context_start restart "$1" || exit 1
    if [ -n "$u_fresh" ] && ! context_landed; then
        context_end
        exit 1
    fi
    u_rline=$(up_resume "$dir" "$1" "$2" "$3")
    u_q=$(context_command "$cx_kind" restart)
    if ! term_poke "$cx_pane" "$u_q" 2>/dev/null; then
        context_end "could not type $u_q into $1's pane"
        exit 1
    fi
    if ! context_wait "$up_quit_looks" up_quit_done; then
        context_end "$1's agent did not leave within about half a minute of $u_q: look with crew peek $1"
        exit 1
    fi
    if ! term_poke "$cx_pane" "$u_rline" 2>/dev/null; then
        context_end "$1's agent left, but its line could not be typed: crew up brings it back"
        exit 1
    fi
    up_started "$1" "$3"
    if ! context_wait "$up_start_looks" up_start_done; then
        context_end "$1's line was typed, but its agent is not idle at its prompt within about a minute: its pane shows $cx_state; look with crew peek $1"
        exit 1
    fi
    context_end
    echo "restarted $1 on its Crewfile line"
)

# Whether the agent being restarted left its pane: a shell alone runs there.
# shellcheck disable=SC2154 # the cx_ variables are set by context_start, in lib/context.sh
up_quit_done() {
    ! up_running "$cx_dir" "$cx_who"
}

# Whether the agent started on its line is idle at its prompt.
# shellcheck disable=SC2154 # the cx_ variables are set by context_start, in lib/context.sh
up_start_done() {
    cx_state=$(screen_state "$cx_dir" "$cx_who")
    [ "$cx_state" = idle ] || [ "$cx_state" = shell ]
}

# The pane crew up keeps for <what> (watch, board) in the crew <dir>, when
# it is still there.
up_helper() {
    u_pane=$(cat "$1/up/$2" 2>/dev/null) || return 0
    term_gone "$u_pane" || echo "$u_pane"
}

# Opens the pane of <what> (watch or board) in the tab whose last pane is
# <anchor>, running <line>, unless the one opened before is there; prints
# its pane.
up_open_helper() {
    u_have=$(up_helper "$1" "$2")
    if [ -n "$u_have" ]; then
        echo "$u_have"
        return
    fi
    if [ -n "$u_dry" ]; then
        echo "open a pane beside $4 running: $3" >&2
        return
    fi
    u_new=$(term_spawn beside "$3" "$4") || return 1
    mkdir -p "$1/up"
    echo "$u_new" >"$1/up/$2"
    echo "$u_new"
}

# Writes <tab>'s entries again in the order the Crewfile gives, <entry>...,
# then the ones it does not list, as they were: the layout follows the file.
up_order() {
    u_dir=$1
    u_tab=$2
    shift 2
    u_old=$(tab_members "$u_dir" "$u_tab")
    [ -z "$u_dry" ] || return 0
    mkdir -p "$u_dir/tabs"
    {
        for u_entry in "$@"; do
            echo "$u_entry"
        done
        printf '%s\n' "$u_old" | while read -r u_entry; do
            [ -n "$u_entry" ] || continue
            for u_listed in "$@"; do
                [ "$u_listed" != "$u_entry" ] || continue 2
            done
            echo "$u_entry"
        done
    } | awk 'NF && !seen[$0]++' >"$u_dir/tabs/$u_tab.new"
    if [ -s "$u_dir/tabs/$u_tab.new" ]; then
        mv "$u_dir/tabs/$u_tab.new" "$u_dir/tabs/$u_tab"
    else
        rm -f "$u_dir/tabs/$u_tab.new"
    fi
}

# crew up [<preset>] [--fresh] [--dry]: brings the crew its Crewfile describes
# up, or back: every member without a live pane is spawned in its tab, named,
# colored, given its clone, invited, and muted as its line says, an exited
# member with a pane still there is restarted in place, resuming its recorded
# conversation unless --fresh is given, and each tab is laid out. A live agent
# is never restarted; a member with a pane the Crewfile does not list is named
# and left alone. --dry checks the Crewfile and prints what it would do,
# touching nothing.
crew_up() {
    u_dry=""
    u_fresh=""
    u_preset=""
    u_restart=""
    u_naming=""
    u_usage="usage: crew up [<preset>] [--fresh] [--dry] [--restart <name>...]"
    for u_arg in "$@"; do
        case "$u_arg" in
        --dry) u_dry=1 ;;
        --fresh) u_fresh=1 ;;
        --restart) u_naming=1 ;;
        -*)
            echo "$u_usage" >&2
            return 2
            ;;
        *)
            if [ -n "$u_naming" ]; then
                crew_name "$u_arg" || return 2
                u_restart="$u_restart $u_arg"
            elif [ -n "$u_preset" ]; then
                echo "$u_usage" >&2
                return 2
            else
                u_preset=$u_arg
            fi
            ;;
        esac
    done
    if [ -n "$u_naming" ] && [ -z "$u_restart" ]; then
        echo "$u_usage" >&2
        return 2
    fi
    if ! dir=$(crew_dir 2>/dev/null); then
        if [ -n "$u_dry" ]; then
            echo "crew init"
            dir=$(crew_root)/.crew
        else
            dir=$(crew_init) || return 1
        fi
    fi
    u_file=$(up_crewfile "$dir" "$u_preset") || return 1
    u_records=$(crewfile_read "$u_file") || return 1
    [ -z "$u_preset" ] || up_agents "$u_records" || return 1
    up_restartable "$u_file" "$u_records" || return 1
    u_me=$(term_self) || {
        echo "crew: crew up runs in a pane of iTerm2 or tmux: the coordinator's" >&2
        return 1
    }
    u_crew="$(shell_word "$CREW_HOME/bin/crew")"
    u_root=$(crew_project "$dir")
    u_invites=""
    u_status=0
    u_listed=" "
    u_first=1
    u_ctab=""
    u_tab=""
    # Each tab, then its members; a tab's layout once its members are in.
    # A member's reviewer and budget (the 9th and 10th fields) are read
    # where they are used, by crewfile_get.
    while IFS='	' read -r u_what u_a u_b u_c u_d u_e u_f u_g _ _ u_line <&3; do
        case "$u_what" in
        tab)
            [ -z "$u_tab" ] || up_tab_done
            u_tab=$u_a
            u_layout=$u_b
            u_entries=""
            if [ -n "$u_first" ]; then
                # The coordinator's own tab, with the watch and the board
                # opened beside its pane. Their place in the tab's order is
                # given by up_first_entries once its lines are read.
                u_first=""
                u_ctab=$u_tab
                u_watch=$u_c
                u_board=$u_d
                u_wpane=""
                u_bpane=""
                up_do term_tab "$u_me" "$u_tab" || echo "crew: could not name the tab $u_tab" >&2
                u_last=$u_me
                if [ "$u_c" = 1 ]; then
                    u_wpane=$(up_open_helper "$dir" watch "cd $(shell_word "$u_root") && $u_crew watch --all" "$u_last") || return 1
                    [ -z "$u_wpane" ] || u_last=$u_wpane
                fi
                if [ "$u_d" = 1 ]; then
                    u_bpane=$(up_open_helper "$dir" board "cd $(shell_word "$u_root") && $u_crew board --live" "$u_last") || return 1
                fi
                # In the tab now, so that crew spawn --tab finds it.
                if [ -z "$u_dry" ]; then
                    for u_entry in $u_me $u_wpane $u_bpane; do
                        tab_add "$dir" "$u_tab" "$u_entry"
                    done
                fi
            elif [ "$u_c" = 1 ] || [ "$u_d" = 1 ]; then
                echo "crew: $u_file: watch and board belong on the first tab, the coordinator's; $u_tab has them" >&2
            fi
            ;;
        pane)
            # The coordinator's pane, the watch, or the board, at its place.
            u_entries="$u_entries @$u_b"
            ;;
        member)
            u_name=$u_b
            u_listed="$u_listed$u_name "
            if up_alive "$dir" "$u_name"; then
                u_entries="$u_entries $u_name"
                [ -n "$u_dry" ] || [ "$(tab_of "$dir" "$u_name")" = "$u_tab" ] || tab_add "$dir" "$u_tab" "$u_name"
                if [ "$u_line" = - ]; then
                    continue
                fi
                if up_running "$dir" "$u_name"; then
                    case "$u_restart " in
                    *" $u_name "*)
                        if up_restart "$u_name" "$u_c" "$u_line"; then
                            [ "$u_e" != 1 ] || u_invites="$u_invites $u_name"
                        else
                            u_status=1
                        fi
                        ;;
                    *) up_changed "$u_name" "$u_line" ;;
                    esac
                    continue
                fi
                u_rline=$(up_resume "$dir" "$u_name" "$u_c" "$u_line")
                up_do crew_poke "$u_name" "$u_rline" </dev/null || {
                    echo "crew: could not restart $u_name; the others go on" >&2
                    continue
                }
                up_started "$u_name" "$u_line"
                [ "$u_e" != 1 ] || u_invites="$u_invites $u_name"
                continue
            fi
            if [ "$u_line" = - ]; then
                echo "crew: $u_name is started and joined by hand: 'crew join $u_name' in its pane" >&2
                continue
            fi
            u_rline=$(up_resume "$dir" "$u_name" "$u_c" "$u_line")
            set -- "$u_name" --tab "$u_tab"
            [ "$u_c" = - ] || set -- "$@" --kind "$u_c"
            if [ "$u_f" = 1 ]; then
                set -- "$@" --clone
                for u_cache in $(printf '%s' "$u_g" | tr ',' ' '); do
                    [ "$u_cache" = - ] || set -- "$@" --cache "$u_cache"
                done
            fi
            up_do crew_spawn "$@" "$u_rline" </dev/null || {
                echo "crew: could not spawn $u_name; the others go on" >&2
                continue
            }
            up_started "$u_name" "$u_line"
            u_entries="$u_entries $u_name"
            if [ "$u_d" = 1 ]; then
                if [ -n "$u_dry" ]; then
                    up_do crew_mute "$u_name"
                else
                    crew_mute "$u_name" >/dev/null
                fi
            fi
            [ "$u_e" != 1 ] || u_invites="$u_invites $u_name"
            ;;
        esac
    done 3<<EOR
$u_records
EOR
    [ -z "$u_tab" ] || up_tab_done
    # The members up but in no line of the Crewfile.
    for u_pf in "$dir"/panes/*; do
        [ -s "$u_pf" ] || continue
        u_name=$(basename "$u_pf")
        case "$u_listed" in *" $u_name "*) continue ;; esac
        up_alive "$dir" "$u_name" || continue
        echo "crew: $u_name is up but not in the Crewfile: left alone"
    done
    # The invites wait for each agent at once, not one after another.
    for u_name in $u_invites; do
        if [ -n "$u_dry" ]; then
            up_do crew_invite "$u_name"
        else
            crew_invite "$u_name" >"$dir/tmp/up.invite.$u_name" 2>&1 &
        fi
    done
    [ -n "$u_dry" ] || wait
    for u_name in $u_invites; do
        [ -n "$u_dry" ] || { cat "$dir/tmp/up.invite.$u_name"; rm -f "$dir/tmp/up.invite.$u_name"; }
    done
    return "$u_status"
}

# The first tab's <entry>... with the panes put in: @coordinator, @watch,
# and @board, from its pane lines, become the panes crew up runs in and
# opened. With no pane line the coordinator's pane comes first, and a watch
# or a board the tab line asks for comes right after it, as before pane
# lines were. A dry run opens no pane: the word watch or board stands in.
up_first_entries() {
    case " $* " in
    *" @coordinator "*) ;;
    *) set -- @coordinator "$@" ;;
    esac
    for u_fe in "$@"; do
        case "$u_fe" in
        @coordinator)
            echo "$u_me"
            case " $* " in *" @watch "*) ;; *) [ "$u_watch" != 1 ] || echo "${u_wpane:-${u_dry:+watch}}" ;; esac
            case " $* " in *" @board "*) ;; *) [ "$u_board" != 1 ] || echo "${u_bpane:-${u_dry:+board}}" ;; esac
            ;;
        @watch) echo "${u_wpane:-${u_dry:+watch}}" ;;
        @board) echo "${u_bpane:-${u_dry:+board}}" ;;
        *) echo "$u_fe" ;;
        esac
    done | awk 'NF'
}

# The end of a tab in crew up: its entries in the Crewfile's order, its
# layout recorded and made.
up_tab_done() {
    # shellcheck disable=SC2086 # the entries, one a word
    [ "$u_tab" != "$u_ctab" ] || u_entries=$(up_first_entries $u_entries)
    # shellcheck disable=SC2086 # the entries, one a word
    up_order "$dir" "$u_tab" $u_entries
    if [ -n "$u_dry" ]; then
        # shellcheck disable=SC2086 # the entries, one a word
        [ "$u_tab" != "$u_ctab" ] || echo "the order of $u_tab:" $u_entries
        echo "crew layout $u_layout --tab $u_tab"
        return
    fi
    mkdir -p "$dir/layouts"
    echo "$u_layout" >"$dir/layouts/$u_tab"
    layout_apply "$dir" "$u_tab" || echo "crew: $u_tab is not laid out as it should be; see above" >&2
}
