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
# working directory, else the one at the main checkout's root, else the one
# kept at home for this project (crew init --home). A crew's directory holds
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
    echo "$dir"
}

# A count of lines or messages is digits, or the command prints <usage>.
crew_count() {
    case "$1" in
    "" | *[!0-9]*)
        echo "usage: $2" >&2
        return 2
        ;;
    esac
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
# not read yet, in order, and marks them read.
crew_unread() {
    if [ $# -ne 1 ]; then
        echo "usage: crew unread <name>" >&2
        return 2
    fi
    me=$1
    crew_name "$me" || return 2
    dir=$(crew_dir) || return 1
    cursor=$dir/cursors/$me
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
    echo "$last" >"$cursor"
    [ "$count" -gt 0 ] || echo "No new messages for $me."
}

# Prints the last <count> messages (5 when not given), whole, in order.
crew_log() {
    crew_count "${1:-5}" "crew log [count]" || return 2
    dir=$(crew_dir) || return 1
    for n in $(ls "$dir/seq" | sort -n | tail -n "${1:-5}"); do
        printf '\n'
        cat "$dir/seq/$n"
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
        n=$(printf '%s' "$n" | sed 's/^0*//')
        if [ ! -f "$dir/seq/${n:-0}" ]; then
            echo "crew: there is no message $n" >&2
            return 1
        fi
        printf '\n'
        cat "$dir/seq/$n"
    done
}

# Writes <name>'s <kind> (status or report) from stdin to status/<name>.md
# or reports/<name>.md and prints the path: a command, so an agent's sandbox
# needs no leave to write outside its tree.
crew_write() {
    kind=$1
    if [ $# -ne 2 ]; then
        echo "usage: crew $kind <name>, the text on stdin" >&2
        return 2
    fi
    crew_name "$2" || return 2
    dir=$(crew_dir) || return 1
    case "$kind" in
    status) file=$dir/status/$2.md ;;
    *) file=$dir/reports/$2.md ;;
    esac
    [ ! -t 0 ] || echo "crew: type the $kind, then press ctrl-d" >&2
    cat >"$file"
    echo "$file"
    if [ "$kind" = status ]; then
        claims_warn "$dir" "$2"
    fi
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
    crew_count "${1:-10}" "crew board [count]" || return 2
    dir=$(crew_dir) || return 1
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
        echo "== $who (${kind:+$kind, }${tab:+tab $tab, }$pane, $(crew_age "$f") min ago)"
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
    ls "$dir/messages" | tail -n "${1:-10}"
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
