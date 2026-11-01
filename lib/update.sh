# The installed crew: which version runs, the latest release, and updating
# to it. Sourced by bin/crew.

# Where the releases are: GitHub's, or what CREW_RELEASES names (a test's).
update_releases() {
    echo "${CREW_RELEASES:-https://github.com/mrfoxes/crew/releases}"
}

# Which crew this is: a checkout (.git under CREW_HOME, a directory or a
# worktree's file) by its tag, as git describe writes it past it, else its
# commit; a release install by VERSION, which install.sh's tarball holds;
# else the path.
crew_version() {
    if [ -e "$CREW_HOME/.git" ]; then
        if v=$(git -C "$CREW_HOME" describe --tags --match "v*" 2>/dev/null); then
            echo "crew $v ($(git -C "$CREW_HOME" log -1 --format=%cs))"
            return
        fi
        git -C "$CREW_HOME" log -1 --format='crew %h (%cs)' 2>/dev/null && return
    fi
    if [ -s "$CREW_HOME/VERSION" ]; then
        echo "crew $(cat "$CREW_HOME/VERSION")"
        return
    fi
    echo "crew at $CREW_HOME"
}

# Downloads <url> to <file>, with curl or wget.
update_fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        echo "crew: neither curl nor wget is here" >&2
        return 1
    fi
}

# The SHA-256 of <file>, with sha256sum (Linux) or shasum (macOS); nothing
# when neither is here.
update_sha256() {
    if sha256sum </dev/null >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif shasum -a 256 </dev/null >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        echo "crew: neither sha256sum nor shasum is here" >&2
        return 1
    fi
}

# Whether <version> is a tag like v1.0.0: it names a URL and a directory.
update_version_ok() {
    printf '%s\n' "$1" | grep -Eq '^v[0-9][0-9A-Za-z.+_-]*$'
}

# The latest release's version, read from its SHA256SUMS, or nothing; a
# name that is not a version is nothing too.
update_latest() {
    u_sums=$(mktemp)
    if update_fetch "$(update_releases)/latest/download/SHA256SUMS" "$u_sums" 2>/dev/null; then
        u_v=$(sed -n 's/^[0-9a-f]*  *crew-\(v[0-9][^ ]*\)\.tar\.gz$/\1/p' "$u_sums" | head -n 1)
        ! update_version_ok "$u_v" || echo "$u_v"
    fi
    rm -f "$u_sums"
}

# crew update [--check]: says which version runs and which is the latest
# release; then, without --check, runs that release's install.sh, linking
# where the install is linked from. A checkout is never replaced.
crew_update() {
    if [ $# -gt 1 ] || { [ $# -eq 1 ] && [ "$1" != --check ]; }; then
        echo "usage: crew update [--check]" >&2
        return 2
    fi
    u_running=$(crew_version)
    u_latest=$(update_latest)
    if [ -z "$u_latest" ]; then
        echo "crew: could not read the latest release at $(update_releases)" >&2
        return 1
    fi
    echo "$u_running; the latest release is $u_latest"
    case "$u_running" in
    "crew $u_latest" | "crew $u_latest ("*)
        echo "up to date"
        return 0
        ;;
    esac
    [ "${1:-}" != --check ] || return 0
    if [ -e "$CREW_HOME/.git" ] || [ ! -s "$CREW_HOME/VERSION" ]; then
        echo "crew: $CREW_HOME is a checkout, not an install: update it with git pull" >&2
        return 1
    fi
    u_data=$(dirname "$CREW_HOME")
    u_prefix=$(dirname "$(cat "$u_data/link" 2>/dev/null || echo "$HOME/.local/bin/crew")")
    u_script=$(mktemp)
    if ! update_fetch "$(update_releases)/download/$u_latest/install.sh" "$u_script"; then
        rm -f "$u_script"
        echo "crew: could not download $u_latest's install.sh" >&2
        return 1
    fi
    # The script is the release's own: its SHA256SUMS names install.sh, and a
    # download cut short, or another script, is not run.
    u_sums=$(mktemp)
    if ! update_fetch "$(update_releases)/download/$u_latest/SHA256SUMS" "$u_sums"; then
        rm -f "$u_script" "$u_sums"
        echo "crew: could not download $u_latest's SHA256SUMS" >&2
        return 1
    fi
    u_want=$(awk '$2 == "install.sh" { print $1; exit }' "$u_sums")
    if ! u_have=$(update_sha256 "$u_script"); then
        rm -f "$u_script" "$u_sums"
        return 1
    fi
    rm -f "$u_sums"
    if [ -z "$u_want" ] || [ "$u_have" != "$u_want" ]; then
        rm -f "$u_script"
        echo "crew: $u_latest's install.sh does not match its SHA256SUMS: not run" >&2
        return 1
    fi
    sh "$u_script" --version "$u_latest" --prefix "$u_prefix"
    u_status=$?
    rm -f "$u_script"
    return "$u_status"
}
