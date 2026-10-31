# Kinds of agent: what crew knows of Claude Code, Codex, Antigravity, and
# any other, read from share/kinds, then from the owner's
# ${XDG_CONFIG_HOME:-~/.config}/crew/kinds, then from the crew's own kinds,
# a later line for a kind replacing an earlier one; and each member's
# kind, kept in kind/<name>. Its variables start with k_: it runs inside
# commands whose own it must not touch. Sourced by bin/crew.

# Every kind's line, the last one read for each, in the order the kinds
# first appear: kind process env idle approve color resume.
kinds_table() {
    k_dir=$(crew_dir 2>/dev/null) || k_dir=""
    for k_file in "$CREW_HOME/share/kinds" "${XDG_CONFIG_HOME:-$HOME/.config}/crew/kinds" ${k_dir:+"$k_dir/kinds"}; do
        [ ! -f "$k_file" ] || cat "$k_file"
    done | awk '
        !/^[[:space:]]*(#|$)/ && NF >= 6 {
            if (!($1 in line)) order[++n] = $1
            r = (NF >= 7) ? $7 : "-"
            for (i = 8; i <= NF; i++) r = r " " $i
            line[$1] = $1 " " $2 " " $3 " " $4 " " $5 " " $6 " " r
        }
        END { for (i = 1; i <= n; i++) print line[order[i]] }'
}

# The names of the kinds crew knows, one a line.
kinds_names() {
    kinds_table | cut -d' ' -f1
}

# The <field> of <kind>: process, env, idle, approve, color, or resume.
# Nothing for a field that is - or a kind crew does not know.
kind_field() {
    kinds_table | awk -v k="$1" -v f="$2" '
        BEGIN { n = split("kind process env idle approve color resume", name, " "); for (i = 1; i <= n; i++) col[name[i]] = i }
        $1 == k && (f in col) {
            c = col[f]
            if ($c != "-") {
                v = $c
                if (f == "resume") for (i = c + 1; i <= NF; i++) v = v " " $i
                print v
            }
            exit
        }'
}

# The kind whose process a shell line runs: the first word of <line> that
# names one, the last part of a path counted (claude, /opt/bin/codex), so
# that 'cd sub && env X=1 codex --yolo' is codex.
kind_of_line() {
    { kinds_table; echo --; printf '%s\n' "$1"; } | awk '
        !seen && $0 == "--" { seen = 1; next }
        !seen { kind[$2] = $1; next }
        {
            gsub(/[;&|()"'"'"']/, " ")
            for (i = 1; i <= NF; i++) {
                w = $i
                sub(/.*\//, "", w)
                if (w in kind) { print kind[w]; exit }
            }
        }'
}

# The kind of the agent this command runs under: the nearest ancestor
# process that is one, else the first kind whose variable is set, for a
# sandbox that hides ps. Nothing when neither tells.
kind_of_self() {
    k_table=$(kinds_table)
    k_pid=$$
    while [ "${k_pid:-1}" -gt 1 ]; do
        k_comm=$(ps -o comm= -p "$k_pid" 2>/dev/null) || break
        k_comm=${k_comm##*/}
        k_found=$(printf '%s\n' "$k_table" | awk -v c="$k_comm" '$2 == c { print $1; exit }')
        if [ -n "$k_found" ]; then
            echo "$k_found"
            return
        fi
        k_pid=$(ps -o ppid= -p "$k_pid" 2>/dev/null | tr -d ' ')
    done
    for k_pair in $(printf '%s\n' "$k_table" | awk '$3 ~ /^[A-Za-z_][A-Za-z0-9_]*$/ { print $1 ":" $3 }'); do
        eval "k_value=\${${k_pair#*:}:-}"
        if [ -n "$k_value" ]; then
            echo "${k_pair%%:*}"
            return
        fi
    done
}

# Whether <kind> is one crew knows, or other.
kind_known() {
    [ "$1" = other ] || kinds_names | grep -qx -- "$1"
}

# <name>'s kind in the crew <dir>, or nothing; never fails, so that an
# assignment from it holds under set -e.
kind_member() {
    cat "$1/kind/$2" 2>/dev/null || :
}

# Records <kind> as <name>'s in the crew <dir>.
kind_record() {
    mkdir -p "$1/kind"
    echo "$3" >"$1/kind/$2"
}

# Whether the screen on stdin shows <kind>'s input line: a line near the
# bottom, its box drawn or not, that is the kind's idle mark alone or the
# mark and a space (❯ Try "…", › Ask Codex, >). Claude Code draws a
# no-break space after its mark, which counts as a space; the screen is
# read as bytes, the same in every locale. A kind with no mark, or one crew
# does not know, never shows it.
kind_drawn() {
    k_mark=$(kind_field "$1" idle)
    [ -n "$k_mark" ] || return 1
    LC_ALL=C awk -v m="$k_mark" '
        {
            gsub(/\302\240/, " ")
            gsub(/│|┃|╭|╮|╰|╯/, "")
            sub(/^[ \t]+/, "")
            sub(/[ \t]+$/, "")
            if ($0 != "") line[++n] = $0
        }
        END {
            for (i = n; i > 0 && i > n - 6; i--)
                if (line[i] == m || index(line[i], m " ") == 1) exit 0
            exit 1
        }'
}
