# Landing in one command: crew land runs the member's check, takes the push
# lock, commits the member's own paths and nothing else, pushes, releases the
# lock whatever happened, and tells the reviewer. A responsibility of its own,
# built on the lock and the stream (lib/store.sh), the claims (lib/claims.sh),
# the member's clone (lib/clones.sh), and the Crewfile (lib/crewfile.sh). Its
# variables start with ld_: it runs inside commands whose own it must not
# touch. Sourced by bin/crew.

# The time, in seconds since the epoch, and the wait between two tries for
# the lock; functions so that a test can fake both and never sleep.
land_now() {
    date +%s
}

land_wait() {
    sleep 10
}

# The longest the lock is waited for, in seconds.
land_patience=300

# crew land <you> -F <message file> [--check <command>] [--to <member>]
# -- <path>...: the whole landing; the reasons it stops are said on stderr.
crew_land() {
    ld_usage="usage: crew land <you> -F <message file> [--check <command>] [--to <member>] -- <path>..."
    ld_who=${1:-}
    [ $# -eq 0 ] || shift
    ld_msg=
    ld_check=
    ld_to=
    while [ $# -gt 0 ]; do
        case "$1" in
        -F | --check | --to)
            [ $# -ge 2 ] || {
                echo "$ld_usage" >&2
                return 2
            }
            case "$1" in
            -F) ld_msg=$2 ;;
            --check) ld_check=$2 ;;
            --to) ld_to=$2 ;;
            esac
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "$ld_usage" >&2
            return 2
            ;;
        esac
    done
    if [ -z "$ld_who" ] || [ -z "$ld_msg" ] || [ $# -eq 0 ]; then
        echo "$ld_usage" >&2
        return 2
    fi
    crew_name "$ld_who" || return 2
    ld_dir=$(crew_dir) || return 1
    land_ready || return $?
    land_changed "$@" || return 1
    land_claims "$@" || return 1
    land_check "$ld_tree" "$ld_check" || return 1
    land_lock "$ld_who" || return 1
    # A signal while the lock is held must release it too.
    trap 'crew_unlock "$ld_who" >/dev/null 2>&1; exit 130' INT TERM HUP
    if land_locked "$@"; then
        ld_rc=0
    else
        ld_rc=$?
    fi
    crew_unlock "$ld_who" >/dev/null 2>&1 || :
    trap - INT TERM HUP
    [ "$ld_rc" -eq 0 ] || return "$ld_rc"
    land_tell
}

# What must hold before anything runs: the reviewer, the message file, and
# the tree to land from (the member's clone, else the project's). Sets
# ld_reviewer, ld_msg (made absolute), and ld_tree.
land_ready() {
    ld_reviewer=$ld_to
    [ -n "$ld_reviewer" ] || ld_reviewer=$(crewfile_get "$ld_dir" "$ld_who" reviewer)
    if [ -z "$ld_reviewer" ]; then
        echo "crew: $ld_who has no reviewer: give one with --to <member>, or reviewer=<member> on its line of the Crewfile" >&2
        return 1
    fi
    crew_name "$ld_reviewer" || return 2
    if [ ! -f "$ld_msg" ]; then
        echo "crew: the message file $ld_msg does not exist" >&2
        return 1
    fi
    case "$ld_msg" in
    /*) ;;
    *) ld_msg=$PWD/$ld_msg ;;
    esac
    ld_tree=$(clone_of "$ld_dir" "$ld_who")
    [ -n "$ld_tree" ] || ld_tree=$(crew_project "$ld_dir")
    if ! git -C "$ld_tree" rev-parse --git-dir >/dev/null 2>&1; then
        echo "crew: $ld_tree is not a git repository" >&2
        return 1
    fi
}

# The changed and untracked files under the literal paths <path>..., one a
# line, renames by their new path.
land_files() {
    git --literal-pathspecs -C "$ld_tree" status --porcelain -z --untracked-files=all -- "$@" 2>/dev/null |
        tr '\0' '\n' | awk '
            skip { skip = 0; next }
            { print substr($0, 4) }
            /^[RC]/ { skip = 1 }'
}

# Stops a landing on a path outside the project, or when the literal paths
# have no change, before the check and the lock.
land_changed() {
    for ld_p in "$@"; do
        case "${ld_p#./}" in
        /* | .. | ../* | */../* | */..)
            echo "crew: $ld_p is not a path inside the project" >&2
            return 1
            ;;
        esac
    done
    [ -z "$(land_files "$@")" ] || return 0
    echo "crew: none of the paths has a change, so nothing was checked, locked, or committed" >&2
    return 1
}

# Checks the paths to land against every member's claims, expanding a
# directory to the changed and untracked files under it.
land_claims() {
    claims_root "$ld_tree"
    for ld_p in "$@"; do
        ld_path=${ld_p#./}
        if claims_is_dir "$ld_path"; then
            ld_sub=$(land_files "$ld_path")
            if [ -z "$ld_sub" ]; then
                land_claimed "$ld_dir" "$ld_who" "$ld_p" || return 1
            else
                while IFS= read -r ld_f; do
                    [ -z "$ld_f" ] || land_claimed "$ld_dir" "$ld_who" "$ld_f" || return 1
                done <<EOF
$ld_sub
EOF
            fi
            ld_others=$(claims_all "$ld_dir" "$ld_who" | while read -r ld_w ld_q; do
                ! claims_overlap "$ld_q" "$ld_path" || echo "$ld_w"
            done | sort -u | tr '\n' ' ' | sed 's/ $//; s/ /, /g')
            if [ -n "$ld_others" ]; then
                echo "crew: $ld_path is also claimed by $ld_others: send a Heads-up: and wait, nothing was committed" >&2
                return 1
            fi
        else
            land_claimed "$ld_dir" "$ld_who" "$ld_p" || return 1
        fi
    done
}

# Runs the check <command> in the tree <tree>, if there is one; on a failure
# it says so with the last lines of what the check printed.
land_check() {
    [ -n "$2" ] || return 0
    if ld_out=$(cd "$1" && sh -c "$2" 2>&1 </dev/null); then
        return 0
    fi
    echo "crew: the check failed, so nothing was locked or committed: $2" >&2
    printf '%s\n' "$ld_out" | tail -n 20 | sed 's/^/  /' >&2
    return 1
}

# Takes the lock for <name>, trying again every 10 seconds for 5 minutes and
# saying who holds it; gives up after that.
land_lock() {
    ld_start=$(land_now)
    while ! crew_lock "$1" >/dev/null 2>&1; do
        ld_held=$(cut -d' ' -f1 "$ld_dir/lock/owner" 2>/dev/null) || ld_held=someone
        if [ $(($(land_now) - ld_start)) -ge "$land_patience" ]; then
            echo "crew: the lock is still ${ld_held:-someone}'s after $((land_patience / 60)) minutes: nothing was committed; ask its owner" >&2
            return 1
        fi
        echo "crew: the lock is held by ${ld_held:-someone}; trying again in 10 seconds" >&2
        land_wait
    done
}

# What is done under the lock: the paths checked against the claims, the
# commit, the push. The paths are the arguments.
land_locked() {
    land_claims "$@" || return 1
    land_commit "$@" || return 1
    land_push
}

# Whether <path> may be landed by <name>: on its Files: line (a directory
# claim covers what is under it) and on nobody else's.
land_claimed() {
    claims_root "${ld_tree:-$(crew_project "$1")}"
    ld_path=${3#./}
    case "$ld_path" in
    /* | .. | ../* | */../* | */..)
        echo "crew: $3 is not a path inside the project" >&2
        return 1
        ;;
    esac
    ld_mine=
    while IFS= read -r ld_c; do
        [ -z "$ld_c" ] || ! claims_covers "$ld_c" "$ld_path" || ld_mine=1
    done <<EOF
$(claims_paths "$1/status/$2.md" 2>/dev/null)
EOF
    if [ -z "$ld_mine" ]; then
        echo "crew: $ld_path is not on $2's Files: line: claim it with crew status, then land" >&2
        return 1
    fi
    ld_others=$(claims_all "$1" "$2" | while read -r ld_w ld_q; do
        ! claims_overlap "$ld_q" "$ld_path" || echo "$ld_w"
    done | sort -u | tr '\n' ' ' | sed 's/ $//; s/ /, /g')
    if [ -n "$ld_others" ]; then
        echo "crew: $ld_path is also claimed by $ld_others: send a Heads-up: and wait, nothing was committed" >&2
        return 1
    fi
}

# Adds the given paths that git does not track yet, then commits those paths
# only, with the message file: a file changed beside them stays uncommitted.
land_commit() {
    for ld_p in "$@"; do
        if [ -n "$(git --literal-pathspecs -C "$ld_tree" ls-files --others --exclude-standard -- "${ld_p#./}")" ]; then
            git --literal-pathspecs -C "$ld_tree" add -- "${ld_p#./}" >&2 || return 1
        fi
        # Each path moves from the front to the back without its ./
        set -- "$@" "${ld_p#./}"
        shift
    done
    git --literal-pathspecs -C "$ld_tree" commit -q -F "$ld_msg" -- "$@" >&2 || return 1
    ld_hash=$(git -C "$ld_tree" rev-parse --short HEAD)
    ld_subject=$(git -C "$ld_tree" log -1 --format=%s)
}

# Pushes the commit: a clone fetches first and, when origin/<branch> has
# moved, rebases onto it and runs the check again before pushing to its own
# branch of origin; a member of the shared tree pushes to the branch's
# upstream and never rebases. A push that fails is told to the owner.
land_push() {
    if [ -n "$(clone_of "$ld_dir" "$ld_who")" ]; then
        ld_branch=$(git -C "$ld_tree" symbolic-ref --short HEAD)
        git -C "$ld_tree" fetch -q origin >/dev/null 2>&1 || :
        if git -C "$ld_tree" rev-parse --verify -q "origin/$ld_branch" >/dev/null &&
            ! git -C "$ld_tree" merge-base --is-ancestor "origin/$ld_branch" HEAD; then
            land_rebase || return 1
        fi
        ld_pushed=$(git -C "$ld_tree" push origin "$ld_branch" 2>&1) && return 0
    else
        ld_pushed=$(git -C "$ld_tree" push 2>&1) && return 0
    fi
    echo "crew: the push of $ld_hash failed, so the owner is told; nothing was pulled or rebased:" >&2
    printf '%s\n' "$ld_pushed" | sed 's/^/  /' >&2
    {
        echo "I committed $ld_hash \"$ld_subject\" in $ld_tree and the push failed. I did not pull or rebase, and the lock is released."
        echo "The commit is still there, unpushed. Tell me what to do."
        echo
        printf '%s\n' "$ld_pushed" | tail -n 20
    } | crew_send "$ld_who" owner "Question: push of $ld_hash rejected" >/dev/null
    return 1
}

# In a clone whose origin/<branch> has moved: rebases the new commit onto it
# and runs the check again on the rebased tree. On a conflict it aborts the
# rebase (restoring the commit as it was) and tells owner with the files; on
# a failed check after the rebase it leaves the rebased commit as HEAD and
# tells owner with both hashes (ORIG_HEAD and HEAD) and the check's output.
land_rebase() {
    if ! git -C "$ld_tree" rebase -q "origin/$ld_branch" >/dev/null 2>&1; then
        ld_files=$(git -C "$ld_tree" diff --name-only --diff-filter=U | tr '\n' ' ' | sed 's/ $//')
        git -C "$ld_tree" rebase --abort >/dev/null 2>&1 || :
        echo "crew: rebasing $ld_hash onto origin/$ld_branch conflicted${ld_files:+ in $ld_files}; aborted, the owner is told, and the commit stays as it was" >&2
        {
            echo "I committed $ld_hash \"$ld_subject\" in $ld_tree, and rebasing onto origin/$ld_branch conflicted${ld_files:+ in: $ld_files}."
            echo "I ran git rebase --abort, so the commit is still there as $ld_hash, unpushed, and the lock is released."
            echo "Tell me what to do."
        } | crew_send "$ld_who" owner "Question: rebase of $ld_hash conflicted" >/dev/null
        return 1
    fi
    ld_before=$(git -C "$ld_tree" rev-parse --short ORIG_HEAD 2>/dev/null) || ld_before=$ld_hash
    ld_hash=$(git -C "$ld_tree" rev-parse --short HEAD)
    [ -n "$ld_check" ] || return 0
    if ld_out=$(cd "$ld_tree" && sh -c "$ld_check" 2>&1 </dev/null); then
        return 0
    fi
    echo "crew: the check failed after rebasing $ld_before to $ld_hash, so nothing was pushed: $ld_check" >&2
    printf '%s\n' "$ld_out" | tail -n 20 | sed 's/^/  /' >&2
    {
        echo "I committed $ld_before \"$ld_subject\" in $ld_tree and rebased it onto origin/$ld_branch as $ld_hash, and the check failed on the rebased tree: $ld_check"
        echo "Nothing was pushed; the rebased commit $ld_hash stays as HEAD (before the rebase: $ld_before), and the lock is released."
        echo
        printf '%s\n' "$ld_out" | tail -n 20
    } | crew_send "$ld_who" owner "Question: check failed after rebasing $ld_before to $ld_hash" >/dev/null
    return 1
}

# Tells the reviewer what was pushed: the hash and the subject, then the
# commit's stat, trimmed.
land_tell() {
    {
        echo "Landed from $ld_tree:"
        echo
        git -C "$ld_tree" show --stat --format= HEAD | head -n 30
    } | crew_send "$ld_who" "$ld_reviewer" "Pushed: $ld_hash $ld_subject" >/dev/null
    echo "landed $ld_hash $ld_subject"
    echo "told $ld_reviewer"
}
