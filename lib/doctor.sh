# crew doctor: what a crew needs under it, checked before it starts. Each
# check is a line, ok, warn, or fail, and a warn or a fail says what to do;
# nothing is installed or changed, no terminal is launched, and no agent
# starts a session. Every call to the machine goes through a small function
# of its own (doctor_which, doctor_iterm_version, ...), which a test
# replaces. Its variables start with d_: it runs inside commands whose own
# it must not touch. Sourced by bin/crew.

# The oldest iTerm2 that opens a pane over another and moves one, and the
# oldest tmux that shares a row out evenly.
DOCTOR_ITERM_MIN=3.5
DOCTOR_TMUX_MIN=3.1

# Says one check: its level, what it found, and for a warn or a fail what
# to do about it.
doctor_say() {
    printf '%-5s %s\n' "$1" "$2"
    if [ -n "${3:-}" ]; then
        printf '      %s\n' "$3"
    fi
    case "$1" in
    warn) d_warned=$((d_warned + 1)) ;;
    fail) d_failed=$((d_failed + 1)) ;;
    esac
}

# Whether version <1> is older than <2>, compared number by number.
doctor_older() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        na = split(a, x, "."); nb = split(b, y, "."); n = na > nb ? na : nb
        for (i = 1; i <= n; i++) {
            if (x[i] + 0 < y[i] + 0) exit 0
            if (x[i] + 0 > y[i] + 0) exit 1
        }
        exit 1
    }'
}

# The path of <command> on PATH, or nothing.
doctor_which() {
    command -v "$1" 2>/dev/null || true
}

# iTerm2's version, read from its app bundle so that iTerm2 is not
# launched; nothing when it is not installed.
doctor_iterm_version() {
    for d_app in /Applications/iTerm.app "$HOME/Applications/iTerm.app"; do
        if [ -f "$d_app/Contents/Info.plist" ]; then
            defaults read "$d_app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true
            return
        fi
    done
}

# Whether iTerm2 runs: asking whether it does does not launch it.
doctor_iterm_running() {
    [ "$(osascript -e 'application "iTerm2" is running' 2>/dev/null)" = true ]
}

# tmux's version, as major.minor; nothing when it is not installed.
doctor_tmux_version() {
    [ -n "$(doctor_which tmux)" ] || return 0
    tmux -V 2>/dev/null | awk 'match($0, /[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH); exit }'
}

# The version <command> prints for --version, as x.y.z, with no terminal to
# read from: it only prints.
doctor_agent_version() {
    "$1" --version </dev/null 2>&1 | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH); exit }'
}

# Whether gh is logged in.
doctor_gh_authed() {
    gh auth status >/dev/null 2>&1
}

# The newest version of <kind> among the fixtures, or nothing.
doctor_fixture_version() {
    d_newest=""
    for d_v in $(awk -v k="$1" '!/^[[:space:]]*(#|$)/ && $2 == k && $3 != "-" { print $3 }' "$CREW_HOME/test/fixtures/VERSIONS" 2>/dev/null); do
        if [ -z "$d_newest" ] || doctor_older "$d_newest" "$d_v"; then
            d_newest=$d_v
        fi
    done
    echo "$d_newest"
}

# The terminal: iTerm2 and tmux, against the features that need them. One
# is enough, so one missing is no problem; neither is a fail.
doctor_terminal() {
    d_iterm=$(doctor_iterm_version)
    d_tmux=$(doctor_tmux_version)
    if [ -z "$d_iterm" ] && [ -z "$d_tmux" ]; then
        doctor_say fail "terminal: neither iTerm2 nor tmux found" \
            "install iTerm2 $DOCTOR_ITERM_MIN or later, or tmux $DOCTOR_TMUX_MIN or later: panes need one"
        return
    fi
    if [ -z "$d_iterm" ]; then
        doctor_say ok "iTerm2: not installed (tmux is enough)"
    elif doctor_older "$d_iterm" "$DOCTOR_ITERM_MIN"; then
        doctor_say warn "iTerm2: $d_iterm is older than $DOCTOR_ITERM_MIN" \
            "update iTerm2: spawn --above and move need $DOCTOR_ITERM_MIN or later"
    elif doctor_iterm_running; then
        doctor_say ok "iTerm2: $d_iterm, running"
    else
        doctor_say ok "iTerm2: $d_iterm, not running"
    fi
    if [ -z "$d_tmux" ]; then
        doctor_say ok "tmux: not installed (iTerm2 is enough)"
    elif doctor_older "$d_tmux" "$DOCTOR_TMUX_MIN"; then
        doctor_say warn "tmux: $d_tmux is older than $DOCTOR_TMUX_MIN" \
            "update tmux: a row stays in halves without select-layout -E, from $DOCTOR_TMUX_MIN"
    else
        doctor_say ok "tmux: $d_tmux"
    fi
}

# crew on PATH, and the checkout it resolves to, followed through
# symlinks the way bin/crew follows them.
doctor_path() {
    d_self=$(doctor_which crew)
    if [ -z "$d_self" ]; then
        doctor_say warn "crew: not on PATH" "ln -s \"$CREW_HOME/bin/crew\" ~/.local/bin/crew"
        return
    fi
    d_found=$d_self
    while [ -L "$d_self" ]; do
        d_link=$(readlink "$d_self")
        case "$d_link" in
        /*) d_self=$d_link ;;
        *) d_self=$(dirname "$d_self")/$d_link ;;
        esac
    done
    d_home=$(cd "$(dirname "$d_self")/.." && pwd)
    if [ "$d_home" = "$CREW_HOME" ]; then
        doctor_say ok "crew: $d_found, this checkout"
    else
        doctor_say warn "crew: $d_found resolves to $d_home, not this checkout ($CREW_HOME)" \
            "ln -sf \"$CREW_HOME/bin/crew\" \"$d_found\" to use this one"
    fi
}

# Each kind's agent: on PATH, its version, and the newest version its
# fixtures were captured from, which the gate's prompts were read in.
doctor_agents() {
    for d_kind in $(kinds_names); do
        d_cmd=$(kind_field "$d_kind" process)
        [ -n "$d_cmd" ] || continue
        if [ -z "$(doctor_which "$d_cmd")" ]; then
            doctor_say warn "$d_kind: $d_cmd is not on PATH" \
                "install it to run a $d_kind member; a crew can run without it"
            continue
        fi
        d_have=$(doctor_agent_version "$d_cmd")
        d_fixed=$(doctor_fixture_version "$d_kind")
        if [ -z "$d_have" ]; then
            doctor_say ok "$d_kind: $d_cmd, version unknown"
        elif [ -z "$d_fixed" ]; then
            doctor_say ok "$d_kind: $d_have, no fixtures to compare"
        elif doctor_older "$d_fixed" "$d_have"; then
            doctor_say warn "$d_kind: $d_have is newer than its fixtures ($d_fixed)" \
                "its prompts may have changed: capture them again with 'crew peek <name> 40', then record the version in test/fixtures/VERSIONS"
        else
            doctor_say ok "$d_kind: $d_have, fixtures from $d_fixed"
        fi
    done
}

# The caveman skill of each installed agent that has one to look for: the
# invite line asks for it, and an agent without it ignores the line.
doctor_caveman() {
    for d_kind in $(kinds_names); do
        [ -n "$(doctor_which "$(kind_field "$d_kind" process)")" ] || continue
        case "$d_kind" in
        codex) d_skill=$HOME/.codex/skills/caveman ;;
        agy) d_skill=$HOME/.gemini/skills/caveman ;;
        claude)
            d_conf=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
            if grep -q '"caveman@' "$d_conf/plugins/installed_plugins.json" 2>/dev/null || [ -d "$d_conf/skills/caveman" ]; then
                doctor_say ok "caveman: the plugin for claude"
            else
                doctor_say warn "caveman: no plugin for claude" \
                    "install the caveman plugin in Claude Code: its members would not work terse"
            fi
            continue
            ;;
        *) continue ;;
        esac
        if [ -d "$d_skill" ]; then
            doctor_say ok "caveman: $d_skill"
        else
            doctor_say warn "caveman: no skill for $d_kind at $d_skill" \
                "install it there: \$caveman in the invite line is ignored without it"
        fi
    done
}

# A notifier for messages to owner, and gh for the board's CI.
doctor_tools() {
    d_notify=""
    for d_cmd in osascript notify-send; do
        if [ -n "$(doctor_which "$d_cmd")" ]; then
            d_notify=$d_cmd
            break
        fi
    done
    if [ -n "$d_notify" ]; then
        doctor_say ok "notifier: $d_notify"
    else
        doctor_say warn "notifier: no osascript or notify-send" \
            "install notify-send (libnotify): a message to owner is posted but not shown"
    fi
    if [ -z "$(doctor_which gh)" ]; then
        doctor_say warn "gh: not installed" "install gh and run 'gh auth login': the board shows no CI without it"
    elif doctor_gh_authed; then
        doctor_say ok "gh: logged in"
    else
        doctor_say warn "gh: not logged in" "run 'gh auth login': the board shows no CI without it"
    fi
}

# The crew's Crewfile, when it has one, and each member with a budget=
# against the rates (the crew's rates, then the owner's) and the models its
# logs show.
doctor_crewfile() {
    d_cfile=$(crewfile_path "$1")
    [ -f "$d_cfile" ] || return 0
    if ! d_records=$(crewfile_read "$d_cfile" 2>/dev/null); then
        d_err=$(crewfile_read "$d_cfile" 2>&1 >/dev/null || true)
        while IFS= read -r d_line <&3; do
            [ -n "$d_line" ] || continue
            doctor_say fail "Crewfile: ${d_line#crew: }"
        done 3<<EOR
$d_err
EOR
        return
    fi
    d_counts=$(printf '%s\n' "$d_records" | awk '
        $1 == "tab" { t++ }
        $1 == "member" { m++ }
        END { printf "%d tabs, %d members\n", t + 0, m + 0 }')
    doctor_say ok "Crewfile: $d_counts"
    d_rates=$(cost_rates)
    d_rfiles="$1/rates or ${XDG_CONFIG_HOME:-$HOME/.config}/crew/rates"
    while IFS='	' read -r d_what _ d_name _ _ _ _ _ _ d_budget _ <&3; do
        if [ "$d_what" != member ] || [ "${d_budget:--}" = - ]; then
            continue
        fi
        if [ -z "$d_rates" ]; then
            doctor_say warn "budget $d_name: \$$d_budget, but no rates" \
                "write prices in $d_rfiles"
            continue
        fi
        d_models=$(cost_member "$1" "$d_name" | awk '$1 == "row" && !seen[$4]++ { m = m (m ? ", " : "") $4 } END { print m }')
        if [ -n "$d_models" ] && [ -z "$(cost_spent "$1" "$d_name")" ]; then
            doctor_say warn "budget $d_name: \$$d_budget, but no rate for $d_models" \
                "add a rate to $d_rfiles"
        fi
    done 3<<EOR
$d_records
EOR
}

# The crew the command runs in, if any: its directory, its Crewfile, its
# lock, its relay, and the members whose pane is gone.
doctor_crew() {
    if ! d_dir=$(crew_dir 2>/dev/null); then
        doctor_say ok "session: not inside a crew ('crew init' makes one)"
        return
    fi
    doctor_say ok "session: the crew at $d_dir"
    doctor_crewfile "$d_dir"
    if [ ! -d "$d_dir/lock" ]; then
        doctor_say ok "lock: free"
    else
        d_who=$(cat "$d_dir/lock/owner" 2>/dev/null || echo someone)
        d_age=$(crew_age "$d_dir/lock")
        if [ "$d_age" -ge 10 ]; then
            doctor_say warn "lock: held by $d_who for $d_age minutes" \
                "ask its owner, then 'crew unlock --force'"
        else
            doctor_say ok "lock: held by $d_who for $d_age minutes"
        fi
    fi
    if crew_relay_alive "$d_dir"; then
        doctor_say ok "relay: running"
    else
        doctor_say ok "relay: not running (a member in a sandbox needs one to wake anyone)"
    fi
    for d_f in "$d_dir"/panes/*; do
        [ -e "$d_f" ] || continue
        d_name=$(basename "$d_f")
        d_pane=$(cat "$d_f")
        if term_gone "$d_pane"; then
            doctor_say warn "member $d_name: pane $d_pane is gone" "crew leave $d_name"
        else
            doctor_say ok "member $d_name: pane $d_pane"
        fi
    done
}

crew_doctor() {
    if [ $# -ne 0 ]; then
        echo "usage: crew doctor" >&2
        return 2
    fi
    d_warned=0
    d_failed=0
    doctor_terminal
    doctor_path
    doctor_agents
    doctor_caveman
    doctor_tools
    doctor_crew
    echo
    echo "doctor: $d_warned warn, $d_failed fail"
    [ "$d_failed" -eq 0 ]
}
