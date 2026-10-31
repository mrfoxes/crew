# A clone for a member: its own checkout next to the project, so that its
# builds, index, and commits touch nobody else's, and it lands through
# origin. clones/<name> in the crew's directory holds the clone's path.
# Its variables start with c_: it runs inside commands whose own it must
# not touch. Sourced by bin/crew.

# Where <name>'s clone of the project at <root> lives: next to it, as
# <project dir name>-<name>.
clone_path() {
    echo "$(dirname "$1")/$(basename "$1")-$2"
}

# The branch a member works on in <clone>, a clone of the project at
# <root>: main, else the branch the project is on, as the clone last
# fetched origin.
clone_base() {
    if git -C "$1" rev-parse --verify -q refs/remotes/origin/main >/dev/null; then
        echo main
    else
        git -C "$2" symbolic-ref --short -q HEAD || echo main
    fi
}

# Copies the project's own user.* settings (name, email, signingkey, ...)
# into <clone>: a clone does not carry them, and its commits would go out
# under the owner's global identity.
clone_identity() {
    git -C "$1" config --local --get-regexp '^user\.' | while read -r c_key c_value; do
        git -C "$2" config --local "$c_key" "$c_value"
    done
}

# Copies each directory of <caches> (one a line, relative to <root>) that
# the project has into <clone> at the same place, unless it is there.
clone_caches() {
    printf '%s\n' "$3" | while IFS= read -r c_cache; do
        [ -n "$c_cache" ] || continue
        case "/$c_cache/" in
        /*//* | */../* | /./*)
            echo "crew: --cache $c_cache is not a path inside the project"
            continue
            ;;
        esac
        if [ ! -d "$1/$c_cache" ]; then
            echo "crew: the project has no $c_cache to copy"
        elif [ -e "$2/$c_cache" ]; then
            echo "crew: $c_cache is in the clone already"
        else
            mkdir -p "$(dirname "$2/$c_cache")"
            cp -R "$1/$c_cache" "$2/$c_cache"
            echo "crew: copied $c_cache into the clone"
        fi
    done
}

# Makes <name>'s clone of the project at <root> or reuses it, then copies
# the identity and <caches>, and records it; prints the clone's path. A
# clone with changes, or of another origin, is left as it is: the spawn
# stops there. Everything else it says goes to stderr.
clone_ready() {
    c_dir=$1
    c_root=$2
    c_name=$3
    c_path=$(clone_path "$c_root" "$c_name")
    c_url=$(git -C "$c_root" remote get-url origin 2>/dev/null) || {
        echo "crew: $c_root has no origin to clone for $c_name" >&2
        return 1
    }
    if [ -e "$c_path" ]; then
        clone_reuse "$c_root" "$c_path" "$c_url" || return 1
    else
        clone_make "$c_root" "$c_path" "$c_url" || return 1
    fi
    clone_identity "$c_root" "$c_path"
    clone_caches "$c_root" "$c_path" "$4" >&2
    mkdir -p "$c_dir/clones"
    echo "$c_path" >"$c_dir/clones/$c_name"
    echo "$c_path"
}

# Clones the project from its own checkout (no network for the objects),
# points origin at the project's origin, and puts the base branch at
# origin's.
clone_make() {
    git clone -q "$1" "$2" >&2 || return 1
    git -C "$2" remote set-url origin "$3"
    git -C "$2" fetch -q origin >&2 || {
        echo "crew: could not fetch origin ($3) in $2" >&2
        return 1
    }
    c_base=$(clone_base "$2" "$1")
    if [ "$c_base" != main ]; then
        echo "crew: origin has no main: the clone works on $c_base, the project's branch" >&2
    fi
    git -C "$2" checkout -q -B "$c_base" "origin/$c_base" >&2
}

# Brings a clone there already up to date, if it is the project's: it
# fetches, and fast-forwards its base branch when it is on it.
clone_reuse() {
    if ! git -C "$2" rev-parse --git-dir >/dev/null 2>&1 ||
        [ "$(git -C "$2" remote get-url origin 2>/dev/null)" != "$3" ]; then
        echo "crew: $2 is not a clone of $3; left as it is" >&2
        return 1
    fi
    if [ -n "$(git -C "$2" status --porcelain)" ]; then
        echo "crew: $2 has changes; left as it is: commit, push, or discard them, then spawn again" >&2
        return 1
    fi
    git -C "$2" fetch -q origin >&2 || echo "crew: could not fetch origin in $2; it stays as it is" >&2
    c_base=$(clone_base "$2" "$1")
    if [ "$(git -C "$2" symbolic-ref --short -q HEAD)" = "$c_base" ]; then
        git -C "$2" merge -q --ff-only "origin/$c_base" >&2 ||
            echo "crew: $2 could not fast-forward $c_base to origin; it stays as it is" >&2
    else
        echo "crew: $2 is not on $c_base; fetched, not moved" >&2
    fi
}

# The clone of <name> the crew <dir> records, or nothing.
clone_of() {
    cat "$1/clones/$2" 2>/dev/null || :
}

# One line under a member's header on the board: its clone, how far it is
# behind origin as last fetched (the board never fetches), and a flag when
# its commits go out under another email than the project's. Nothing for a
# member with no clone.
clone_board() {
    c_path=$(clone_of "$1" "$2")
    [ -n "$c_path" ] || return 0
    if [ ! -d "$c_path" ]; then
        echo "clone: $c_path (gone)"
        return 0
    fi
    c_base=$(clone_base "$c_path" "$3")
    c_behind=$(git -C "$c_path" rev-list --count "HEAD..origin/$c_base" 2>/dev/null) || c_behind='?'
    c_line="clone: $c_path, $c_behind behind origin/$c_base"
    c_mine=$(git -C "$c_path" config user.email 2>/dev/null) || c_mine=""
    c_theirs=$(git -C "$3" config user.email 2>/dev/null) || c_theirs=""
    if [ "$c_mine" != "$c_theirs" ]; then
        c_line="$c_line, IDENTITY ${c_mine:-unset} (the project: ${c_theirs:-unset})"
    fi
    echo "$c_line"
}

# What <clone> holds that origin does not: commits on no branch of origin,
# changed files, untracked files; nothing when it holds none.
clone_left() {
    git -C "$1" log --format='commit %h %s' HEAD --branches --not --remotes=origin
    git -C "$1" status --porcelain | sed 's/^/file /'
}

# Removes <name>'s clone when nothing is left in it; else lists what is
# and keeps it.
clone_leave() {
    c_path=$(clone_of "$1" "$2")
    if [ -z "$c_path" ]; then
        echo "crew: $2 has no clone"
        return 0
    fi
    if [ ! -d "$c_path/.git" ]; then
        rm -f "$1/clones/$2"
        echo "$2's clone $c_path is gone; forgotten"
        return 0
    fi
    c_left=$(clone_left "$c_path")
    if [ -n "$c_left" ]; then
        echo "crew: $c_path is kept; it still holds what origin does not:" >&2
        printf '%s\n' "$c_left" | sed 's/^/  /' >&2
        return 1
    fi
    rm -rf "$c_path"
    rm -f "$1/clones/$2"
    echo "$2's clone $c_path is removed: nothing was left in it"
}

# crew sync <name>: in <name>'s own clone only (refused in the shared tree,
# and with changes in the tree), fetches origin and rebases its branch onto
# origin/<branch>. On a conflict it aborts the rebase, says which files
# conflict, and leaves the clone as it was.
crew_sync() {
    if [ $# -ne 1 ]; then
        echo "usage: crew sync <name>" >&2
        return 2
    fi
    crew_name "$1" || return 2
    c_dir=$(crew_dir) || return 1
    c_path=$(clone_of "$c_dir" "$1")
    if [ -z "$c_path" ] || [ "$c_path" = "$(crew_project "$c_dir")" ]; then
        echo "crew: $1 has no clone: crew sync only runs in a member's own clone, never in the shared tree" >&2
        return 1
    fi
    if [ ! -d "$c_path/.git" ]; then
        echo "crew: $1's clone $c_path is gone" >&2
        return 1
    fi
    if [ -n "$(git -C "$c_path" status --porcelain)" ]; then
        echo "crew: $c_path has changes; left as it is" >&2
        return 1
    fi
    c_branch=$(git -C "$c_path" symbolic-ref --short -q HEAD) || {
        echo "crew: $c_path is not on a branch; left as it is" >&2
        return 1
    }
    if ! git -C "$c_path" fetch -q origin >&2; then
        echo "crew: could not fetch origin in $c_path" >&2
        return 1
    fi
    if ! git -C "$c_path" rebase -q "origin/$c_branch" >/dev/null 2>&1; then
        c_files=$(git -C "$c_path" diff --name-only --diff-filter=U | tr '\n' ' ' | sed 's/ $//')
        git -C "$c_path" rebase --abort >/dev/null 2>&1 || :
        echo "crew: rebasing $c_path onto origin/$c_branch conflicted${c_files:+ in $c_files}; aborted and left as it was" >&2
        return 1
    fi
    echo "$1 synced to origin/$c_branch ($(git -C "$c_path" rev-parse --short HEAD))"
}
