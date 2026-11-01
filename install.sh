#!/bin/sh
# Installs crew from a GitHub release, in one line:
#
#   curl -fsSL https://github.com/mrfoxes/crew/releases/latest/download/install.sh | sh
#
# It downloads the latest release (or the one of --version vX.Y.Z), checks
# the tarball against the release's SHA256SUMS and stops on a mismatch,
# unpacks it to ${XDG_DATA_HOME:-~/.local/share}/crew/<version>/, points
# crew/current at it, and links ~/.local/bin/crew (or <dir>/crew with
# --prefix <dir>) to current/bin/crew. Run again, it upgrades in place:
# every version keeps its directory, and current is the one link that
# moves. --uninstall removes the link and crew/, nothing else. It never
# asks for sudo. CREW_RELEASES names another place to download from.
#
# Everything runs from main, called on the last line: a download cut short
# defines functions and does nothing.
set -eu

usage() {
    echo "usage: sh install.sh [--version vX.Y.Z] [--prefix <dir>] [--uninstall]"
}

fail() {
    echo "install: $1" >&2
    exit 1
}

# Downloads <url> to <file>, with curl or wget.
fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$2" "$1" || fail "could not download $1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1" || fail "could not download $1"
    else
        fail "neither curl nor wget is here"
    fi
}

# The SHA-256 of <file>, with sha256sum (Linux) or shasum (macOS).
sha256() {
    if sha256sum </dev/null >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif shasum -a 256 </dev/null >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        fail "neither sha256sum nor shasum is here"
    fi
}

# A version is a tag, vX.Y.Z and the like: it names a directory and a URL,
# so nothing else gets through.
checked_version() {
    printf '%s\n' "$1" | grep -Eq '^v[0-9][0-9A-Za-z.+_-]*$' || fail "'$1' is not a version like v1.0.0: nothing installed"
}

# Points the link <link> at <target>. Not one rename: mv onto a link to a
# directory moves into the directory, and -T is GNU's alone, so the link is
# gone for the microseconds between the two calls.
relink() {
    rm -f "$1"
    ln -s "$2" "$1"
}

uninstall() {
    link=$(cat "$data/link" 2>/dev/null || echo "$prefix/crew")
    for l in "$link" "$prefix/crew"; do
        [ -L "$l" ] || continue
        case "$(readlink "$l")" in
        "$data"/*)
            rm -f "$l"
            echo "removed $l"
            ;;
        esac
    done
    if [ -d "$data" ]; then
        rm -rf "$data"
        echo "removed $data"
    fi
}

install() {
    # A crew of someone else at the prefix (another tool of that name, a link
    # to a checkout) is left alone: only a missing one, or a link into $data,
    # is replaced. This comes before any download.
    if [ -e "$prefix/crew" ] || [ -L "$prefix/crew" ]; then
        case "$(readlink "$prefix/crew" 2>/dev/null || echo "a file")" in
        "$data"/*) ;;
        *) fail "$prefix/crew is there already and is not this install's link (it is $(readlink "$prefix/crew" 2>/dev/null || echo "a file")): --prefix <dir> links elsewhere; nothing installed" ;;
        esac
    fi
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    if [ -z "$version" ]; then
        fetch "$releases/latest/download/SHA256SUMS" "$tmp/SHA256SUMS"
        version=$(sed -n 's/^[0-9a-f]*  *crew-\(v[0-9][^ ]*\)\.tar\.gz$/\1/p' "$tmp/SHA256SUMS" | head -n 1)
        [ -n "$version" ] || fail "no crew-<version>.tar.gz in the latest release's SHA256SUMS"
        checked_version "$version"
    else
        fetch "$releases/download/$version/SHA256SUMS" "$tmp/SHA256SUMS"
    fi
    tarball=crew-$version.tar.gz
    fetch "$releases/download/$version/$tarball" "$tmp/$tarball"
    want=$(awk -v f="$tarball" '$2 == f { print $1; exit }' "$tmp/SHA256SUMS")
    [ -n "$want" ] || fail "no checksum for $tarball in SHA256SUMS: nothing installed"
    have=$(sha256 "$tmp/$tarball")
    [ "$have" = "$want" ] || fail "checksum mismatch for $tarball ($have, SHA256SUMS says $want): nothing installed"

    mkdir "$tmp/unpack"
    tar -xzf "$tmp/$tarball" -C "$tmp/unpack"
    [ -x "$tmp/unpack/crew-$version/bin/crew" ] || fail "$tarball holds no crew-$version/bin/crew: nothing installed"
    mkdir -p "$data" "$prefix"
    rm -rf "${data:?}/$version"
    mv "$tmp/unpack/crew-$version" "$data/$version"
    relink "$data/current" "$version"
    relink "$prefix/crew" "$data/current/bin/crew"
    echo "$prefix/crew" >"$data/link"
    echo "crew $version installed at $data/$version, current, and linked from $prefix/crew"

    case ":$PATH:" in
    *":$prefix:"*) ;;
    *) echo "add $prefix to PATH, in your shell's rc file: export PATH=\"$prefix:\$PATH\"" ;;
    esac
    completions=$data/current/share/completions
    case "$(basename "${SHELL:-sh}")" in
    fish) echo "completion: ln -s $completions/crew.fish ~/.config/fish/completions/crew.fish" ;;
    zsh) echo "completion, in ~/.zshrc: fpath=($completions \$fpath); autoload -Uz compinit; compinit" ;;
    bash) echo "completion, in ~/.bashrc: source $completions/crew.bash" ;;
    esac
    "$prefix/crew" doctor || :
}

main() {
    releases=${CREW_RELEASES:-https://github.com/mrfoxes/crew/releases}
    data=${XDG_DATA_HOME:-$HOME/.local/share}/crew
    prefix=$HOME/.local/bin
    version=""
    uninstall=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --version | --prefix)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            if [ "$1" = --version ]; then
                checked_version "$2"
                version=$2
            else
                prefix=$2
            fi
            shift
            ;;
        --uninstall) uninstall=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
        esac
        shift
    done
    if [ -n "$uninstall" ]; then
        uninstall
    else
        install
    fi
}

main "$@"
