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

# No external script or stylesheet is loaded from another host.
ext_assets=$(
    grep -E '<(script|link)[^>]+(src|href)="https?://' "$html" |
        grep -v 'fonts\.' || :
)
check "no external script or style host" "" "$ext_assets"

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

finish
