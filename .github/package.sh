#!/bin/sh
# Packages a release of crew into <dir>, from the repository this runs in:
# crew-<tag>.tar.gz from git archive (the files as they are, plus VERSION
# holding the tag: packaging, not a build), install.sh beside it,
# SHA256SUMS for both, and notes.md, the tag's entry of CHANGELOG.md. Run
# by .github/workflows/release.yml on a pushed tag; --dry says what it
# would make and makes nothing.
#
#   sh .github/package.sh <tag> <dir> [--dry]
set -eu

if [ $# -lt 2 ] || [ $# -gt 3 ] || { [ $# -eq 3 ] && [ "$3" != --dry ]; }; then
    echo "usage: sh .github/package.sh <tag> <dir> [--dry]" >&2
    exit 2
fi
tag=$1
dir=$2
case "$tag" in
v[0-9]*) ;;
*)
    echo "package: '$tag' is not a tag vX.Y.Z" >&2
    exit 2
    ;;
esac
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || {
    echo "package: no tag $tag here" >&2
    exit 1
}
if [ "${3:-}" = --dry ]; then
    echo "would make $dir/crew-$tag.tar.gz (git archive $tag, plus VERSION), $dir/install.sh, $dir/SHA256SUMS, and $dir/notes.md from CHANGELOG.md's ${tag#v}"
    exit 0
fi

sha256() {
    if sha256sum </dev/null >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

mkdir -p "$dir"
printf '%s\n' "$tag" >"$dir/VERSION"
git archive --format=tar.gz --prefix="crew-$tag/" --add-file="$dir/VERSION" -o "$dir/crew-$tag.tar.gz" "$tag"
rm "$dir/VERSION"
cp install.sh "$dir/install.sh"
(cd "$dir" && sha256 "crew-$tag.tar.gz" install.sh >SHA256SUMS)
awk -v v="${tag#v}" '$0 == "## " v { on = 1; next } /^## / { on = 0 } on' CHANGELOG.md |
    sed -e '/./,$!d' >"$dir/notes.md"
[ -s "$dir/notes.md" ] || echo "package: CHANGELOG.md has no entry '## ${tag#v}': the notes are empty" >&2
echo "made $dir/crew-$tag.tar.gz, $dir/install.sh, $dir/SHA256SUMS, $dir/notes.md"
