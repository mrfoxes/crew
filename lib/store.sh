# The .crew directory: where a project keeps it, and the numbered stream of
# messages inside it. Sourced by bin/crew.

# The root of the main checkout inside git, so that every linked worktree of a
# project shares one crew; the working directory outside git.
crew_root() {
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
        pwd
        return
    }
    case "$common" in
    */.git) dirname "$common" ;;
    *) git rev-parse --show-toplevel ;;
    esac
}

# The project's .crew: $CREW_DIR, else the nearest .crew at or above the
# working directory, else the clone's local crew.dir setting, else the one
# at the main checkout's root, else the one kept at home for this project
# (crew init --home). A crew's directory holds
# the stream's numbers in seq/: ~/.crew itself, which holds the crews kept at
# home, is not one.
crew_dir() {
    if [ -n "${CREW_DIR:-}" ]; then
        echo "$CREW_DIR"
        return
    fi
    d=$(pwd -P)
    while :; do
        if [ -d "$d/.crew/seq" ]; then
            echo "$d/.crew"
            return
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    if d=$(git config --local --get crew.dir 2>/dev/null); then
        if [ -d "$d/seq" ]; then
            printf '%s\n' "$d"
            return
        fi
        printf 'crew: git config crew.dir points to no initialized crew at %s\n' "$d" >&2
        return 1
    fi
    root=$(crew_root)
    for d in "$root/.crew" "$(crew_home_dir "$root")"; do
        if [ -d "$d/seq" ]; then
            echo "$d"
            return
        fi
    done
    echo "crew: no crew here or above; run 'crew init' or 'crew init --home' in the project first" >&2
    return 1
}

# The crew kept at home for the project at <root>: ~/.crew/<root, with every
# character but a letter or digit as ->, the way Claude Code names the
# directories of its projects.
crew_home_dir() {
    echo "$HOME/.crew/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
}

# The project a crew directory belongs to: named in its project file, else
# the directory .crew/ sits in.
crew_project() {
    cat "$1/project" 2>/dev/null || dirname "$1"
}

# Makes the crew's directory for the project and prints it: .crew/ at the
# main checkout's root, kept out of commits; with --home the one under
# ~/.crew, which leaves the tree untouched.
crew_init() {
    root=$(crew_root)
    if [ "${1:-}" = --home ]; then
        dir=$(crew_home_dir "$root")
    else
        dir=$root/.crew
        # Keep the crew out of commits without touching a tracked .gitignore.
        if common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
            mkdir -p "$common/info"
            grep -qx '/.crew/' "$common/info/exclude" 2>/dev/null ||
                echo '/.crew/' >>"$common/info/exclude"
        fi
    fi
    for d in messages seq cursors panes threads muted kind status reports tmp; do
        mkdir -p "$dir/$d"
    done
    echo "$root" >"$dir/project"
    [ -e "$dir/README.md" ] || cp "$CREW_HOME/share/plan.md" "$dir/README.md"
    echo "$dir"
}

# A count of lines, messages, seconds, or minutes is digits, or the command
# prints <usage>. It is read as decimal into $count_n (leading zeros dropped);
# a third argument, positive, refuses 0, for an interval that would loop.
crew_count() {
    case "$1" in
    "" | *[!0-9]*)
        echo "usage: $2" >&2
        return 2
        ;;
    esac
    # Read as decimal: leading zeros dropped, so 08 and 010 are 8 and 10, and
    # a number too long for shell arithmetic is refused.
    count_n=$(printf '%s' "$1" | sed 's/^0*//')
    count_n=${count_n:-0}
    case "$count_n" in
    ??????????*)
        echo "usage: $2" >&2
        return 2
        ;;
    esac
    if [ "${3:-}" = positive ] && [ "$count_n" = 0 ]; then
        echo "usage: $2 (at least 1)" >&2
        return 2
    fi
}

# A name is lower-case letters, digits, and dashes: it goes into file names.
crew_name() {
    case "$1" in
    "" | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
        echo "crew: '$1' is not a name: use lower-case letters, digits, and dashes" >&2
        return 1
        ;;
    esac
}

# Posts a message: <from> <to> <subject>, the body on stdin. Prints the path.
crew_send() {
    if [ $# -lt 3 ]; then
        echo "usage: crew send <from> <to> <subject>, the body on stdin" >&2
        return 2
    fi
    from=$1
    to=$2
    shift 2
    # The subject is the first line of the message: a newline in it would
    # break the header the stream is read by.
    subject=$(printf '%s' "$*" | tr '\n' ' ')
    crew_name "$from" && crew_name "$to" || return 2
    dir=$(crew_dir) || return 1
    [ ! -t 0 ] || echo "crew: type the body, then press ctrl-d" >&2
    body=$(cat)
    slug=$(printf '%s' "$subject" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//' | cut -c1-48)
    tmp=$(mktemp "$dir/tmp/message.XXXXXX")

    # A number is taken by hard-linking the finished message to seq/<n>, which
    # fails when another sender took it first: no number is seen half-written.
    n=$(ls "$dir/seq" | sort -n | tail -n 1)
    n=${n:-0}
    while :; do
        n=$((n + 1))
        {
            printf '# %04d. %s to %s: %s\n\n' "$n" "$from" "$to" "$subject"
            printf 'From: %s\nTo: %s\nTime: %s\n\n' "$from" "$to" "$(date '+%Y-%m-%d %H:%M:%S')"
            printf '%s\n' "$body"
        } >"$tmp"
        ln "$tmp" "$dir/seq/$n" 2>/dev/null && break
    done
    file=$(printf '%s/messages/%04d-%s-to-%s-%s.md' "$dir" "$n" "$from" "$to" "$slug")
    ln "$tmp" "$file"
    rm "$tmp"
    echo "$file"
    # One wake a message: by the relay, when one runs, from outside the
    # sender's sandbox, else by the sender. Whoever makes tmp/wake.<n> first
    # wakes; with CREW_WAKE=0 the sender makes it and wakes nobody.
    if [ "${CREW_WAKE:-1}" = 0 ]; then
        mkdir "$dir/tmp/wake.$n" 2>/dev/null || true
    elif ! crew_relay_alive "$dir" && mkdir "$dir/tmp/wake.$n" 2>/dev/null; then
        crew_wake "$dir" "$n" "$from" "$to" "$subject"
    fi
}

# The <field> (From, To, Time) of the message <file>, read from its header:
# a line in the body that looks like one routes nothing.
crew_field() {
    sed -n "3,5s/^$2: //p" "$1"
}

# Prints the messages to <name> or to all, from someone else, that <name> has
# not read yet, in order, and marks them read; with --peek, marks nothing.
crew_unread() {
    peek=0
    wait=""
    if [ $# -lt 1 ]; then
        echo "usage: crew unread <name> [--peek] [--wait [seconds]]" >&2
        return 2
    fi
    me=$1
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
        --peek) peek=1 ;;
        --wait)
            wait=600
            if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then
                wait=$2
                shift
            fi
            crew_count "$wait" "crew unread <name> [--peek] [--wait [seconds]]" || return 2
            ;;
        *)
            echo "usage: crew unread <name> [--peek] [--wait [seconds]]" >&2
            return 2
            ;;
        esac
        shift
    done
    crew_name "$me" || return 2
    dir=$(crew_dir) || return 1
    cursor=$dir/cursors/$me
    # --wait: the stream read every two seconds until something is there for
    # <name>, 600 seconds at most; a wait inside one command costs an agent no
    # turn. On a timeout, nothing is printed, the cursor stays, and the
    # status is 1.
    if [ -n "$wait" ]; then
        waited=0
        until crew_waiting "$dir" "$me"; do
            [ "$waited" -lt "$wait" ] || return 1
            sleep 2
            waited=$((waited + 2))
        done
    fi
    last=$(cat "$cursor" 2>/dev/null || echo 0)
    count=0
    for n in $(ls "$dir/seq" | sort -n); do
        [ "$n" -gt "$last" ] || continue
        to=$(crew_field "$dir/seq/$n" To)
        if { [ "$to" = "$me" ] || [ "$to" = all ]; } &&
            [ "$(crew_field "$dir/seq/$n" From)" != "$me" ]; then
            printf '\n'
            cat "$dir/seq/$n"
            count=$((count + 1))
        fi
        last=$n
    done
    if [ "$peek" = 0 ]; then
        cu_tmp=$(mktemp "$dir/tmp/cursor.XXXXXX")
        echo "$last" >"$cu_tmp" && mv "$cu_tmp" "$cursor"
    fi
    [ "$count" -gt 0 ] || echo "No new messages for $me."
}

# Whether a message to <name> or to all, from someone else, waits past
# <name>'s cursor in the crew <dir>.
crew_waiting() {
    last=$(cat "$1/cursors/$2" 2>/dev/null || echo 0)
    for n in $(ls "$1/seq" | sort -n); do
        [ "$n" -gt "$last" ] || continue
        to=$(crew_field "$1/seq/$n" To)
        { [ "$to" = "$2" ] || [ "$to" = all ]; } &&
            [ "$(crew_field "$1/seq/$n" From)" != "$2" ] && return 0
    done
    return 1
}

# Prints the last <count> messages (5 when not given), whole, in order. The
# filters keep the messages --from or --to a name, or whose text matches
# --grep <pattern>; they combine, and the count applies after them.
# --oneline prints a header a message.
crew_log() {
    usage="crew log [count] [--from <name>] [--to <name>] [--grep <pattern>] [--oneline]"
    count=5 from='' to='' pattern='' oneline=0
    while [ $# -gt 0 ]; do
        case "$1" in
        --from | --to | --grep)
            if [ $# -lt 2 ]; then
                echo "usage: $usage" >&2
                return 2
            fi
            case "$1" in
            --from) from=$2 ;;
            --to) to=$2 ;;
            *) pattern=$2 ;;
            esac
            shift 2
            ;;
        --oneline)
            oneline=1
            shift
            ;;
        *)
            crew_count "$1" "$usage" || return 2
            count=$count_n
            shift
            ;;
        esac
    done
    dir=$(crew_dir) || return 1
    for n in $(ls "$dir/seq" | sort -n); do
        [ -z "$from" ] || [ "$(crew_field "$dir/seq/$n" From)" = "$from" ] || continue
        [ -z "$to" ] || [ "$(crew_field "$dir/seq/$n" To)" = "$to" ] || continue
        [ -z "$pattern" ] || grep -q -e "$pattern" "$dir/seq/$n" || continue
        echo "$n"
    done | tail -n "$count" | while read -r n; do
        if [ "$oneline" = 1 ]; then
            sed -n '1s/^# \([0-9]*\)\. /\1 /p' "$dir/seq/$n"
        else
            printf '\n'
            cat "$dir/seq/$n"
        fi
    done
}

# Prints the messages numbered <number>..., whole, as they were sent.
crew_show() {
    if [ $# -lt 1 ]; then
        echo "usage: crew show <number>..." >&2
        return 2
    fi
    dir=$(crew_dir) || return 1
    for n in "$@"; do
        crew_count "$n" "crew show <number>..." || return 2
        n=$count_n
        if [ ! -f "$dir/seq/$n" ]; then
            echo "crew: there is no message $n" >&2
            return 1
        fi
        printf '\n'
        cat "$dir/seq/$n"
    done
}

# Whether stdin is a terminal; a function so tests can stand in for one.
crew_tty() { [ -t 0 ]; }

# Reads, writes, or updates <name>'s status in status/<name>.md: prints it
# when stdin is a terminal and no field is given, rewrites the "Field: value"
# lines given in place (adding any the status lacks) when fields are given,
# else reads the whole status from stdin. Prints the path when it writes.
crew_status() {
    if [ $# -lt 1 ]; then
        echo 'usage: crew status <name> ["Field: value"...], or the status on stdin' >&2
        return 2
    fi
    st_who=$1
    shift
    crew_name "$st_who" || return 2
    st_nl='
'
    for st_arg in "$@"; do
        case "$st_arg" in
        *:*) st_key=${st_arg%%:*} ;;
        *) st_key= ;;
        esac
        case "$st_arg" in
        *"$st_nl"*) st_key= ;;
        esac
        case "$st_key" in
        [A-Za-z]*)
            case "$st_key" in
            *[![:alnum:]\ _-]*) st_key= ;;
            esac
            ;;
        *) st_key= ;;
        esac
        if [ -z "$st_key" ]; then
            echo 'usage: crew status <name> ["Field: value"...], or the status on stdin' >&2
            return 2
        fi
    done
    dir=$(crew_dir) || return 1
    file=$dir/status/$st_who.md
    if [ $# -eq 0 ]; then
        if crew_tty; then
            [ ! -f "$file" ] || cat "$file"
            return 0
        fi
        st_tmp=$(mktemp "$dir/tmp/status.XXXXXX")
        cat >"$st_tmp" && mv "$st_tmp" "$file" || {
            rm -f "$st_tmp"
            return 1
        }
    else
        st_in=/dev/null
        [ ! -f "$file" ] || st_in=$file
        st_tmp=$(mktemp "$dir/tmp/status.XXXXXX")
        awk '
            BEGIN {
                for (i = 2; i < ARGC; i++) {
                    line = ARGV[i]
                    sep = index(line, ":")
                    key = substr(line, 1, sep - 1)
                    rest = substr(line, sep + 1)
                    if (rest != "" && substr(rest, 1, 1) != " ")
                        line = key ": " rest
                    if (!(key in val)) order[++n] = key
                    val[key] = line
                }
                ARGC = 2
            }
            {
                sep = index($0, ":")
                key = sep ? substr($0, 1, sep - 1) : ""
                if (key in val) {
                    if (!done[key]++) print val[key]
                } else {
                    print $0
                }
            }
            END {
                for (i = 1; i <= n; i++) {
                    key = order[i]
                    if (!done[key]) print val[key]
                }
            }
        ' "$st_in" "$@" >"$st_tmp"
        mv "$st_tmp" "$file"
    fi
    echo "$file"
    claims_warn "$dir" "$st_who"
}

# Writes <name>'s <kind> (status or report) to status/<name>.md or
# reports/<name>.md and prints the path: a command, so an agent's sandbox
# needs no leave to write outside its tree.
crew_write() {
    kind=$1
    shift
    if [ "$kind" = status ]; then
        crew_status "$@"
        return
    fi
    if [ $# -ne 1 ]; then
        echo "usage: crew $kind <name>, the text on stdin" >&2
        return 2
    fi
    crew_name "$1" || return 2
    dir=$(crew_dir) || return 1
    file=$dir/reports/$1.md
    ! crew_tty || echo "crew: type the $kind, then press ctrl-d" >&2
    wr_tmp=$(mktemp "$dir/tmp/report.XXXXXX")
    cat >"$wr_tmp" && mv "$wr_tmp" "$file" || {
        rm -f "$wr_tmp"
        return 1
    }
    echo "$file"
}

# Puts the session's stream, cursors, statuses, reports, and wake claims
# under archive/<date and time>/ and starts the stream over, keeping the
# plan, the rules, the project, the lock, the panes, the threads, and the
# mutes. Not under a relay, whose count would go on from the old stream.
crew_archive() {
    dir=$(crew_dir) || return 1
    if crew_relay_alive "$dir"; then
        echo "crew: a relay runs; stop it before the archive" >&2
        return 1
    fi
    if [ -z "$(find "$dir/messages" "$dir/status" "$dir/reports" -type f | head -n 1)" ]; then
        echo "crew: nothing to archive"
        return
    fi
    to=$dir/archive/$(date '+%Y-%m-%d-%H%M%S')
    mkdir -p "$to"
    for d in messages seq cursors status reports; do
        mv "$dir/$d" "$to/"
        mkdir "$dir/$d"
    done
    rm -rf "$dir"/tmp/wake.* "$dir/relay.last"
    echo "$to"
}

# The time, for a line of a log the owner reads.
crew_stamp() {
    date '+%H:%M:%S'
}

# When <file> was last written, in seconds since the epoch: GNU stat takes
# -c, BSD stat -f (where -c is an error; on GNU, -f reports the file system).
crew_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

# How long ago <file> was last written, in whole minutes.
crew_age() {
    echo $((($(date +%s) - $(crew_mtime "$1")) / 60))
}

# The push lock: one of the crew lands at a time.
crew_lock() {
    if [ $# -ne 1 ]; then
        echo "usage: crew lock <name>" >&2
        return 2
    fi
    crew_name "$1" || return 2
    dir=$(crew_dir) || return 1
    if mkdir "$dir/lock" 2>/dev/null; then
        printf '%s %s\n' "$1" "$(date '+%H:%M')" >"$dir/lock/owner"
        echo "lock taken by $1"
        return
    fi
    held=$(cat "$dir/lock/owner" 2>/dev/null || echo "someone")
    age=$(crew_age "$dir/lock")
    echo "crew: the lock is held by $held, for $age minutes; keep working and retry" >&2
    [ "$age" -lt 10 ] || echo "crew: past 10 minutes it is stale: ask its owner, then 'crew unlock --force'" >&2
    return 1
}

crew_unlock() {
    if [ $# -ne 1 ]; then
        echo "usage: crew unlock <name> | --force" >&2
        return 2
    fi
    dir=$(crew_dir) || return 1
    [ -d "$dir/lock" ] || {
        echo "crew: the lock is free"
        return
    }
    held=$(cut -d' ' -f1 "$dir/lock/owner" 2>/dev/null || true)
    if [ "$1" != --force ] && [ "$1" != "$held" ]; then
        echo "crew: the lock is $held's, not $1's" >&2
        return 1
    fi
    rm -r "$dir/lock"
    echo "lock released"
}

# The crew at a glance: statuses, files claimed twice or by nobody, the
# lock, the latest messages, the latest commits with their CI, and what the
# members spent.
crew_board() {
    if [ "${1:-}" = --live ]; then
        shift
        crew_board_live "$@"
        return
    fi
    crew_count "${1:-10}" "crew board [count] | --live [seconds]" || return 2
    dir=$(crew_dir) || return 1
    # A crew with no member and no status looks broken: say what to do.
    if [ -z "$(ls "$dir/status" 2>/dev/null)$(ls "$dir/panes" 2>/dev/null)" ]; then
        echo "no members yet: run 'crew up <preset>' or 'crew spawn <name> --join <command>'"
    fi
    for f in "$dir"/status/*.md; do
        [ -e "$f" ] || continue
        who=$(basename "$f" .md)
        if pane=$(cat "$dir/panes/$who" 2>/dev/null); then
            ! term_gone "$pane" || pane="$pane gone"
        else
            pane="no pane"
        fi
        [ ! -e "$dir/muted/$who" ] || pane="$pane, muted"
        kind=$(kind_member "$dir" "$who")
        tab=$(tab_of "$dir" "$who")
        reviewer=$(crewfile_get "$dir" "$who" reviewer)
        echo "== $who (${kind:+$kind, }${tab:+tab $tab, }$pane, ${reviewer:+reviewed by $reviewer, }$(crew_age "$f") min ago)"
        clone_board "$dir" "$who" "$(crew_project "$dir")"
        cat "$f"
        echo
    done
    claims_board_conflicts "$dir"
    claims_board_unclaimed "$dir"
    if [ -d "$dir/lock" ]; then
        echo "== lock: $(cat "$dir/lock/owner" 2>/dev/null || echo held)"
    else
        echo "== lock: free"
    fi
    echo
    echo "== messages"
    crew_log "$count_n" --oneline
    root=$(crew_project "$dir")
    if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        echo
        echo "== git"
        # A repository with no commit yet has no log: nothing to show.
        git -C "$root" log --oneline -5 2>/dev/null || :
        (cd "$root" && gh run list --limit 5 2>/dev/null) || true
    fi
    cost_board "$dir"
}
