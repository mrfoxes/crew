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
# kept at home for this project (crew init --home).
crew_dir() {
    if [ -n "${CREW_DIR:-}" ]; then
        echo "$CREW_DIR"
        return
    fi
    d=$(pwd -P)
    while :; do
        if [ -d "$d/.crew" ]; then
            echo "$d/.crew"
            return
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    root=$(crew_root)
    for d in "$root/.crew" "$(crew_home_dir "$root")"; do
        if [ -d "$d" ]; then
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
    for d in messages seq cursors panes status reports tmp; do
        mkdir -p "$dir/$d"
    done
    echo "$root" >"$dir/project"
    echo "$dir"
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
    subject=$*
    crew_name "$from" && crew_name "$to" || return 2
    dir=$(crew_dir) || return 1
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
    # The relay, when one runs, wakes the recipients from outside the sandbox.
    [ "${CREW_WAKE:-1}" = 0 ] || crew_relay_alive "$dir" || crew_wake "$dir" "$n" "$from" "$to" "$subject"
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

# When <file> was last written, in seconds since the epoch: GNU stat takes
# -c, BSD stat -f (where -c is an error; on GNU, -f reports the file system).
crew_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
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
    age=$((($(date +%s) - $(crew_mtime "$dir/lock")) / 60))
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

# The crew at a glance: statuses, the lock, the latest messages, and the
# latest commits with their CI.
crew_board() {
    dir=$(crew_dir) || return 1
    for f in "$dir"/status/*.md; do
        [ -e "$f" ] || continue
        echo "== $(basename "$f" .md) ($(cat "$dir/panes/$(basename "$f" .md)" 2>/dev/null || echo "no pane"))"
        cat "$f"
        echo
    done
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
        git -C "$root" log --oneline -5 2>/dev/null
        (cd "$root" && gh run list --limit 5 2>/dev/null) || true
    fi
}
