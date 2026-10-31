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
    for u_arg in "$@"; do
        case "$u_arg" in
        --dry) u_dry=1 ;;
        --fresh) u_fresh=1 ;;
        -*)
            echo "usage: crew up [<preset>] [--fresh] [--dry]" >&2
            return 2
            ;;
        *)
            if [ -n "$u_preset" ]; then
                echo "usage: crew up [<preset>] [--fresh] [--dry]" >&2
                return 2
            fi
            u_preset=$u_arg
            ;;
        esac
    done
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
    u_me=$(term_self) || {
        echo "crew: crew up runs in a pane of iTerm2 or tmux: the coordinator's" >&2
        return 1
    }
    u_crew="$(shell_word "$CREW_HOME/bin/crew")"
    u_root=$(crew_project "$dir")
    u_invites=""
    u_listed=" "
    u_first=1
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
                # The coordinator's own tab: its pane comes first, then the
                # watch and the board beside it.
                u_first=""
                u_entries=$u_me
                up_do term_tab "$u_me" "$u_tab" || echo "crew: could not name the tab $u_tab" >&2
                u_last=$u_me
                if [ "$u_c" = 1 ]; then
                    u_w=$(up_open_helper "$dir" watch "cd $(shell_word "$u_root") && $u_crew watch --all" "$u_last") || return 1
                    [ -z "$u_w" ] || { u_entries="$u_entries $u_w"; u_last=$u_w; }
                fi
                if [ "$u_d" = 1 ]; then
                    u_w=$(up_open_helper "$dir" board "cd $(shell_word "$u_root") && $u_crew board --live" "$u_last") || return 1
                    [ -z "$u_w" ] || u_entries="$u_entries $u_w"
                fi
                if [ -z "$u_dry" ]; then
                    for u_entry in $u_entries; do
                        tab_add "$dir" "$u_tab" "$u_entry"
                    done
                fi
            elif [ "$u_c" = 1 ] || [ "$u_d" = 1 ]; then
                echo "crew: $u_file: watch and board belong on the first tab, the coordinator's; $u_tab has them" >&2
            fi
            ;;
        member)
            u_name=$u_b
            u_listed="$u_listed$u_name "
            if up_alive "$dir" "$u_name"; then
                u_entries="$u_entries $u_name"
                [ -n "$u_dry" ] || [ "$(tab_of "$dir" "$u_name")" = "$u_tab" ] || tab_add "$dir" "$u_tab" "$u_name"
                if up_running "$dir" "$u_name" || [ "$u_line" = - ]; then
                    continue
                fi
                u_rline=$(up_resume "$dir" "$u_name" "$u_c" "$u_line")
                up_do crew_poke "$u_name" "$u_rline" </dev/null || {
                    echo "crew: could not restart $u_name; the others go on" >&2
                    continue
                }
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
}

# The end of a tab in crew up: its entries in the Crewfile's order, its
# layout recorded and made.
up_tab_done() {
    # shellcheck disable=SC2086 # the entries, one a word
    up_order "$dir" "$u_tab" $u_entries
    if [ -n "$u_dry" ]; then
        echo "crew layout $u_layout --tab $u_tab"
        return
    fi
    mkdir -p "$dir/layouts"
    echo "$u_layout" >"$dir/layouts/$u_tab"
    layout_apply "$dir" "$u_tab" || echo "crew: $u_tab is not laid out as it should be; see above" >&2
}
