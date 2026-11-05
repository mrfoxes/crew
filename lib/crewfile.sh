# The Crewfile: a crew described once, its tabs and members in the order
# crew up places them. It lives in the crew's directory; a preset is one
# kept in ${XDG_CONFIG_HOME:-~/.config}/crew/presets/<name>, or one crew
# ships in share/presets. Sourced by
# bin/crew.
#
#   # tabs and members, in the order crew up places them
#   tab main layout=main watch board
#   tab proof layout=table
#   member claude   reviewer=claude2 -- claude --model claude-opus-5-5
#   member claude2  reviewer=claude clone cache=.lake -- claude
#   tab runtime
#   member agy      reviewer=codex mute budget=20 -- agy
#   member tess     # started and joined by hand
#
# A word that starts with # starts a comment, to the end of the line, but
# after " -- ", which keeps the rest of the line as the owner's shell gets
# it. The first tab is the one crew up runs in, the coordinator's: its
# panes come in the order of its lines, the coordinator's first, then
# the watch and the board, unless a line "pane coordinator", "pane
# watch", or "pane board" puts one in its place among the members.

# Where the Crewfile of the crew <dir> lives.
crewfile_path() {
    echo "$1/Crewfile"
}

# Where the preset <name> lives; a name with a / is a path. The owner's
# preset of the name wins over the one crew ships in share/presets.
crewfile_preset() {
    case "$1" in
    */*) echo "$1" ;;
    *)
        if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/crew/presets/$1" ] ||
            [ ! -f "$CREW_HOME/share/presets/$1" ]; then
            echo "${XDG_CONFIG_HOME:-$HOME/.config}/crew/presets/$1"
        else
            echo "$CREW_HOME/share/presets/$1"
        fi
        ;;
    esac
}

# The names of the presets there are, the owner's and crew's, one a line.
crewfile_preset_names() {
    ls "${XDG_CONFIG_HOME:-$HOME/.config}/crew/presets" "$CREW_HOME/share/presets" 2>/dev/null |
        awk 'NF && $0 !~ /:$/ && !seen[$0]++' | sort
}

# Reads the Crewfile <file> and prints it as records, tab-separated, - for
# none:
#
#   tab <name> <layout> <watch> <board>
#   member <tab> <name> <kind> <mute> <invite> <clone> <caches> <reviewer> <budget> <line>
#   pane <tab> <coordinator, watch, or board>
#
# <watch>, <board>, <mute>, <invite>, and <clone> are 1 or 0, <caches> the
# cache= directories apart by commas. A pane record stands at its place
# among the members, and its tab opens the watch or the board it names.
# Anything it cannot read stops it before a record is printed, each error
# said with its file and line.
crewfile_read() {
    awk -v file="$1" -v kinds="$(kinds_names | tr '\n' ' ')other" '
        function fail(msg) { printf "crew: %s:%d: %s\n", file, NR, msg > "/dev/stderr"; bad = 1 }
        function isname(s) { return s ~ /^[a-z0-9-]+$/ && s != "all" && s != "owner" }
        BEGIN { split(kinds, k, " "); for (i in k) known[k[i]] = 1 }
        {
            line = $0
            cmd = ""
            hascmd = 0
            if (match(line, /[ \t]--([ \t]|$)/)) {
                cmd = substr(line, RSTART + RLENGTH)
                sub(/^[ \t]+/, "", cmd)
                sub(/[ \t]+$/, "", cmd)
                line = substr(line, 1, RSTART - 1)
                hascmd = 1
            }
            if (match(line, /(^|[ \t])#/)) line = substr(line, 1, RSTART - 1)
            $0 = line
            if (NF == 0) {
                if (hascmd) fail("a command needs a member line")
                next
            }
            if ($1 == "tab") {
                if (hascmd) fail("a tab runs no command")
                if (NF < 2 || !isname($2)) { fail("a tab needs a name: lower-case letters, digits, and dashes"); next }
                if ($2 in tabs) fail("tab " $2 " is there twice")
                tabs[$2] = 1
                tab = $2
                if (first == "") first = tab
                layout = "grid"; watch = 0; board = 0
                for (i = 3; i <= NF; i++) {
                    if ($i ~ /^layout=/) {
                        layout = substr($i, 8)
                        if (layout !~ /^(table|grid|main|[0-9]+x[0-9]+)$/) fail("layout " layout " is not table, grid, main, or <columns>x<rows>")
                    } else if ($i == "watch") { watch = 1; worded["watch"] = 1 }
                    else if ($i == "board") { board = 1; worded["board"] = 1 }
                    else fail("a tab takes layout=, watch, and board, not " $i)
                }
                out[++n] = "tab\t" tab "\t" layout "\t" watch "\t" board
                tabline = n
                next
            }
            # A pane no member sits in, at its place in the first tab: the
            # coordinator pane, or the watch or the board, which its tab then
            # opens as the words on the tab line do.
            if ($1 == "pane") {
                if (hascmd) fail("a pane runs no command")
                if (tab == "") { fail("a pane comes after a tab"); next }
                what = $2
                if (NF < 2 || (what != "coordinator" && what != "watch" && what != "board")) { fail("a pane is coordinator, watch, or board"); next }
                if (NF > 2) fail("a pane takes no option, not " $3)
                if (tab != first) { fail("pane " what " belongs on the first tab, the coordinator\047s"); next }
                if (what in placed) { fail("pane " what " is there twice"); next }
                placed[what] = 1
                if (what in worded) fail(what " is on the tab line and on a line of its own")
                if (what == "watch") watch = 1
                if (what == "board") board = 1
                out[tabline] = "tab\t" tab "\t" layout "\t" watch "\t" board
                out[++n] = "pane\t" tab "\t" what
                next
            }
            if ($1 == "member") {
                if (tab == "") fail("a member comes after a tab")
                if (NF < 2 || !isname($2)) { fail("a member needs a name: lower-case letters, digits, and dashes, not all or owner"); next }
                name = $2
                if (name in members) fail("member " name " is there twice")
                members[name] = 1
                kind = "-"; mute = 0; invite = 1; clone = 0; caches = ""; reviewer = "-"; budget = "-"
                for (i = 3; i <= NF; i++) {
                    if ($i ~ /^kind=/) {
                        kind = substr($i, 6)
                        if (!(kind in known)) fail("kind " kind " is not one crew knows: " kinds)
                    } else if ($i == "mute") mute = 1
                    else if ($i == "noinvite") invite = 0
                    else if ($i == "clone") clone = 1
                    else if ($i ~ /^cache=./) caches = caches (caches == "" ? "" : ",") substr($i, 7)
                    else if ($i ~ /^reviewer=/) {
                        reviewer = substr($i, 10)
                        reviewed[name] = reviewer
                        reviewline[name] = NR
                    } else if ($i ~ /^budget=/) {
                        budget = substr($i, 8)
                        if (budget !~ /^[0-9]+(\.[0-9]+)?$/) fail("budget " budget " is not a number of dollars")
                    } else fail("a member takes kind=, mute, noinvite, clone, cache=, reviewer=, and budget=, not " $i)
                }
                if (caches != "" && !clone) fail("cache= copies into a clone: add clone")
                if (hascmd && cmd == "") fail("nothing after --")
                out[++n] = "member\t" tab "\t" name "\t" kind "\t" mute "\t" invite "\t" clone "\t" (caches == "" ? "-" : caches) "\t" reviewer "\t" budget "\t" (cmd == "" ? "-" : cmd)
                next
            }
            fail("a line is a tab, a member, or a pane, not " $1)
        }
        END {
            for (m in reviewed) {
                if (!(reviewed[m] in members)) { NR = reviewline[m]; fail("reviewer " reviewed[m] " is not a member") }
                else if (reviewed[m] == m) { NR = reviewline[m]; fail(m " cannot review itself") }
            }
            if (bad) exit 1
            for (i = 1; i <= n; i++) print out[i]
        }' "$1"
}

# The <option> of <member> on its Crewfile line in the crew <dir> (kind,
# reviewer, budget, tab, line), or nothing: no Crewfile, no such member,
# or none given. Never fails, so that an assignment from it holds.
crewfile_get() {
    [ -f "$(crewfile_path "$1")" ] || return 0
    crewfile_read "$(crewfile_path "$1")" 2>/dev/null | awk -F '\t' -v m="$2" -v o="$3" '
        BEGIN { col["tab"] = 2; col["kind"] = 4; col["reviewer"] = 9; col["budget"] = 10; col["line"] = 11 }
        $1 == "member" && $3 == m && (o in col) { if ($(col[o]) != "-") print $(col[o]); exit }' || :
}
