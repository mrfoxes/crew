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
    "$(grep -c '<h1>Coding agents side by side, in panes you can see\.</h1>' "$html")"
check "portable install one-liner on the site" "2" \
    "$(grep -c 'curl -fsSL https://github.com/mrfoxes/crew/releases/latest/download/install.sh | sh' "$html")"

# Every command listed in crew --help appears as 'crew <command>' on the site.
cmds=$(sh "$CREW_HOME/bin/crew" --help | awk '/^  [a-z][a-z-]*([ |]|$)/ { print $1 }')
for cmd in $cmds; do
    check "site documents crew $cmd" "1" \
        "$(grep -q "crew $cmd" "$html" && echo 1 || echo 0)"
done

# Every internal #anchor link resolves to an id="" in docs/index.html.
anchors=$(sed -n 's/.*href="#\([^"]*\)".*/\1/p' "$html" | sort -u)
for a in $anchors; do
    check "anchor #$a resolves" "1" \
        "$(grep -q "id=\"$a\"" "$html" && echo 1 || echo 0)"
done

# Every local file referenced by href= or src= exists in docs/.
local_refs=$(
    sed -n 's/.*\(href\|src\)="\([^"#][^"]*\)".*/\2/p' "$html" |
        grep -v '^https://github\.com/mrfoxes/crew' | sort -u
)
for ref in $local_refs; do
    check "local asset $ref exists" "1" \
        "$([ -f "$CREW_HOME/docs/$ref" ] && echo 1 || echo 0)"
done

# No external script or stylesheet is loaded from another host.
ext_assets=$(
    grep -E '<(script|link)[^>]+(src|href)="https?://' "$html" |
        grep -v 'fonts\.' || :
)
check "no external script or style host" "" "$ext_assets"

# Light and dark theme rules and mobile breakpoint in style.css.
check "dark theme media query in style.css" "1" \
    "$(grep -c 'prefers-color-scheme: dark' "$css")"
check "mobile media query in style.css" "1" \
    "$(grep -c '@media (max-width:' "$css")"

# Words to avoid (case-insensitive whole words): orchestration, swarm,
# autonomous, AI, agentic.
for bad in orchestration swarm autonomous ai agentic; do
    hits=$(grep -i -E "(^|[^a-zA-Z])$bad([^a-zA-Z]|$)" "$html" "$css" || :)
    check "word '$bad' not used on the site" "" "$hits"
done

finish
