#!/bin/sh
# Builds the site into <dir>: docs/ as it is, with <tag>, the latest
# release, in each <span data-release> of index.html. docs/ holds words
# that read right without a build ("The latest release"), so the page
# needs no request to GitHub to say which release is out. Run by
# .github/workflows/pages.yml; an empty <tag> leaves those words.
#
#   sh .github/site.sh <tag> <dir>
set -eu

if [ $# -ne 2 ]; then
    echo "usage: sh .github/site.sh <tag> <dir>" >&2
    exit 2
fi
tag=$1
dir=$2
case "$tag" in
'') ;;
v[0-9]*.[0-9]*.[0-9]*)
    case "$tag" in
    *[!v0-9.]*)
        echo "site: '$tag' is not a tag vX.Y.Z" >&2
        exit 2
        ;;
    esac
    ;;
*)
    echo "site: '$tag' is not a tag vX.Y.Z" >&2
    exit 2
    ;;
esac
here=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$dir"
cp -R "$here/docs/." "$dir/"
if [ -n "$tag" ]; then
    sed "s|<span data-release>[^<]*</span>|<span data-release>$tag</span>|g" \
        "$here/docs/index.html" >"$dir/index.html"
    n=$(grep -o "<span data-release>$tag</span>" "$dir/index.html" | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || {
        echo "site: docs/index.html has no <span data-release>" >&2
        exit 1
    }
    echo "built $dir with $tag in $n places"
else
    echo "built $dir with no release named"
fi
