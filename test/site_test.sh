#!/bin/sh
# The GitHub Pages site in docs/: every command of crew --help is on it,
# every internal link and anchor resolves, the install line is the portable
# one-liner, no script or style is loaded from another host, and the voice
# keeps to the project's words.
#
#   sh test/run.sh site

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

html=$CREW_HOME/docs/index.html
css=$CREW_HOME/docs/style.css

check "docs/.nojekyll exists" "1" "$([ -f "$CREW_HOME/docs/.nojekyll" ] && echo 1)"
check "docs/index.html exists" "1" "$([ -f "$html" ] && echo 1)"
check "docs/style.css exists" "1" "$([ -f "$css" ] && echo 1)"

check "tagline on the site" "1" \
    "$(grep -c '<h1>Coding agents side by side, \(<br class="narrow">\)\{0,1\}in panes you can see\.</h1>' "$html")"
check "portable install one-liner on the site" "2" \
    "$(grep -c 'curl -fsSL https://github.com/mrfoxes/crew/releases/latest/download/install.sh | sh' "$html")"

# Every command listed in crew --help appears as 'crew <command>' on the site,
# and every 'crew <command>' in the reference table exists in crew --help.
help=$(sh "$CREW_HOME/bin/crew" --help)
cmds=$(printf '%s\n' "$help" | awk '/^  [a-z][a-z-]*([ |]|$)/ { print $1 }')
for cmd in $cmds; do
    check "site documents crew $cmd" "1" \
        "$(grep -q "crew $cmd" "$html" && echo 1 || echo 0)"
done
site_cmds=$(
    sed -n 's/.*<td class="cmd-col"><code>crew \([a-z][a-z-]*\).*/\1/p' "$html" |
        sort -u
)
for cmd in $site_cmds; do
    check "site command crew $cmd is in crew --help" "1" \
        "$(printf '%s\n' "$cmds" | grep -qx "$cmd" && echo 1 || echo 0)"
done

# Every internal #anchor link resolves to an id="" in docs/index.html.
anchors=$(sed -n 's/.*href="#\([^"]*\)".*/\1/p' "$html" | sort -u)
for a in $anchors; do
    check "anchor #$a resolves" "1" \
        "$(grep -q "id=\"$a\"" "$html" && echo 1 || echo 0)"
done

# Every local file referenced by href= or src= exists in docs/; a link to
# another host (GitHub, the fonts) is not fetched.
local_refs=$(
    sed -n 's/.*\(href\|src\)="\([^"#][^"]*\)".*/\2/p' "$html" |
        grep -v '^https\{0,1\}://' | sort -u
)
for ref in $local_refs; do
    check "local asset $ref exists" "1" \
        "$([ -f "$CREW_HOME/docs/$ref" ] && echo 1 || echo 0)"
done

# Nothing is cut off: a pre scrolls sideways, code in a table cell wraps, and
# the mockup's grids let their items shrink.
check "pre scrolls sideways" "1" \
    "$(awk '/^pre \{/,/^\}/' "$css" | grep -c 'overflow-x: auto')"
check "table code wraps" "1" \
    "$(awk '/^td code, th code \{/,/^\}/' "$css" | grep -c 'overflow-wrap: anywhere')"
check "the pane grid lets its items shrink" "1" \
    "$(grep -c 'repeat(3, minmax(0, 1fr))' "$css" | awk '$1 >= 1 { print 1 }')"

# Resource tags may load only local files or the two font hosts. Match the
# host boundary: a URL that merely contains "fonts." is not an exception.
# Navigation links to GitHub are not requests made by loading the page.
ext_assets=$(awk 'BEGIN { RS = "<" }
    /^[[:space:]]*(script|link|img|iframe|video|audio|source|object|embed)[[:space:]]/ {
        sub(/>.*/, "")
        tag = $0
        while (match($0, /(src|href|poster|data)="[^"]*"/)) {
            url = substr($0, RSTART, RLENGTH)
            sub(/^[^=]*="/, "", url); sub(/"$/, "", url)
            if (url ~ /^(https?:)?\/\// &&
                !(tag ~ /^link[[:space:]]/ &&
                  url ~ /^https:\/\/fonts\.(googleapis|gstatic)\.com(\/|$)/)) print url
            $0 = substr($0, RSTART + RLENGTH)
        }
    }' "$html")
check "resource hosts are local or Google Fonts" "" "$ext_assets"

# File budgets catch accidental growth and missing motion gates without a
# browser dependency. Runtime behavior and contrast are measured in #62.
bg=$CREW_HOME/docs/bg.js
check "the background script exists" "1" "$([ -f "$bg" ] && echo 1 || echo 0)"
if [ -f "$bg" ]; then
    check "bg.js is below 8 KiB" "1" \
        "$(wc -c <"$bg" | awk '$1 < 8192 { print 1 }')"
fi

# Inline scripts have the same motion and network budget as separate files.
inline=$tmp/inline.js
awk '/^[[:space:]]*<script>/ { inside = 1; next }
    /^[[:space:]]*<\/script>/ { inside = 0 }
    inside { print }' "$html" >"$inline"
for asset in "$CREW_HOME"/docs/*.css "$CREW_HOME"/docs/*.js "$inline"; do
    [ -f "$asset" ] || continue
    name=${asset##*/}
    # Ignore comments so a description of a missing guard cannot pass it.
    code=$tmp/site-$name
    awk '
        /^[[:space:]]*\/\// { next }
        {
            line = $0
            text = ""
            while (length(line)) {
                if (comment) {
                    end = index(line, "*/")
                    if (!end) break
                    line = substr(line, end + 2); comment = 0
                } else {
                    start = index(line, "/*")
                    if (!start) { text = text line; break }
                    text = text substr(line, 1, start - 1)
                    line = substr(line, start + 2); comment = 1
                }
            }
            print text
        }' "$asset" >"$code"
    if grep -Eq '@keyframes|(animation|transition)(-[a-z-]+)?[[:space:]]*:|requestAnimationFrame|IntersectionObserver|\.animate[[:space:]]*[(]' "$code"; then
        check "$name handles reduced motion" "1" \
            "$(grep -Eq 'prefers-reduced-motion[[:space:]]*:[[:space:]]*reduce' "$code" && echo 1 || echo 0)"
    fi
    if [ "$asset" = "$bg" ]; then
        check "bg.js observes tab visibility" "1" \
            "$(grep -Eq 'addEventListener[(][^,]*visibilitychange' "$code" && echo 1 || echo 0)"
        check "bg.js can cancel its animation frame" "1" \
            "$(grep -Eq 'cancelAnimationFrame[[:space:]]*[(]' "$code" && echo 1 || echo 0)"
    fi
    case "$asset" in
    *.css)
        # Local CSS needs no imports or external URLs; fonts come from the
        # explicit, allowlisted link in index.html.
        check "$name has no remote resources or imports" "" \
            "$(grep -Ei '@import|url[(][^)]*//' "$code" || :)"
        ;;
    *.js)
        # These scripts animate or copy text. They have no network job.
        check "$name has no network API or remote URL" "" \
            "$(grep -En "fetch[[:space:]]*[(]|XMLHttpRequest|WebSocket|EventSource|sendBeacon[[:space:]]*[(]|https?://|[\"']//" "$code" || :)"
        ;;
    esac
done

# The site is dark by design (color-scheme: dark), and has a mobile breakpoint.
check "the site is dark by design" "1" \
    "$(grep -q 'color-scheme: dark' "$css" && echo 1 || echo 0)"
check "mobile media query in style.css" "1" \
    "$(grep -q '@media (max-width:' "$css" && echo 1 || echo 0)"

# Words to avoid (case-insensitive whole words): orchestration, swarm,
# autonomous, AI, agentic, and no em dashes or local machine paths.
for bad in orchestration swarm autonomous ai agentic; do
    hits=$(grep -i -E "(^|[^a-zA-Z])$bad([^a-zA-Z]|$)" "$html" "$css" || :)
    check "word '$bad' not used on the site" "" "$hits"
done
check "no em dash on the site" "" "$(grep -E '—|&mdash;' "$html" || :)"
check "no local /Users/ path on the site" "" "$(grep '/Users/' "$html" || :)"
check "no email on the site" "" "$(grep -E '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$html" || :)"

# The real session from crew story (#55): six moments, crew story headings,
# Cuts marked [...], and message links resolving to # NNNN. headers.
for m in moment-crewfile moment-plan moment-gate moment-land moment-review moment-down; do
    check "session moment #$m exists" "1" \
        "$(grep -q "id=\"$m\"" "$html" && echo 1 || echo 0)"
done
for h in "# The crew of crew" "## The Crewfile" "## The members" "## The stream" "## The commits" "## The reports"; do
    check "session includes crew story heading '$h'" "1" \
        "$(grep -Fq "$h" "$html" && echo 1 || echo 0)"
done
for n in 0001 0009 0010 0034 0036; do
    check "session links to #msg-$n" "1" \
        "$(grep -q "href=\"#msg-$n\"" "$html" && echo 1 || echo 0)"
    check "session defines #msg-$n on message $n" "1" \
        "$(grep -q "id=\"msg-$n\"># $n\\." "$html" && echo 1 || echo 0)"
done
check "session marks cuts with [...]" "1" \
    "$(grep -Fq '[...]' "$html" && echo 1 || echo 0)"

# The release the site names comes from the deploy (.github/site.sh, run by
# .github/workflows/pages.yml), never from the page asking GitHub: docs/
# names no fixed version, and its words read right without a build.
check "the site names no fixed version" "" "$(grep -E 'v[0-9]+\.[0-9]+\.[0-9]+' "$html" || :)"
check "the release spots read right without a build" "The latest release
the latest release" "$(sed -n 's|.*<span data-release>\([^<]*\)</span>.*|\1|p' "$html")"
check "each release spot links to the releases on GitHub" "2" \
    "$(grep 'data-release' "$html" | grep -c 'href="https://github.com/mrfoxes/crew/releases"')"
site=$CREW_HOME/.github/site.sh
sh "$site" v9.8.7 "$tmp/site" >/dev/null
check "the build names the release in each spot" "2" \
    "$(grep -o '<span data-release>v9.8.7</span>' "$tmp/site/index.html" | wc -l | tr -d ' ')"
check "and changes nothing else" "" \
    "$(diff "$html" "$tmp/site/index.html" | grep '^[<>]' | grep -v 'data-release' || :)"
check "and copies the rest of docs/" "" \
    "$(cd "$CREW_HOME/docs" && for f in .nojekyll *.css *.js; do cmp -s "$f" "$tmp/site/$f" || echo "$f"; done)"
sh "$site" "" "$tmp/site-none" >/dev/null
check "with no release, the build leaves the words" "" "$(diff "$html" "$tmp/site-none/index.html")"
check "the build refuses a tag that is not vX.Y.Z" "2 2 2" \
    "$(for t in 1.0.2 v1.0 'v1.0.2|x'; do sh "$site" "$t" "$tmp/site-bad" 2>/dev/null; printf '%s ' "$?"; done | sed 's/ $//')"

finish
