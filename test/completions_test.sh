#!/bin/sh
# The completions' tests: share/completions/ parses in each shell present,
# one awk program reads the commands and flags from the usage text in all
# three, and what Tab completes is the same in bash, zsh, and fish, driven
# without a terminal against a crew made here. A shell that is not installed
# is skipped, not failed.
#
#   sh test/run.sh completions

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

comp=$CREW_HOME/share/completions
have() { command -v "$1" >/dev/null 2>&1; }

# Each file parses in its shell.
if have fish; then
    check "crew.fish parses" "0" "$(fish -n "$comp/crew.fish" >/dev/null 2>&1; echo $?)"
fi
if have zsh; then
    check "_crew parses" "0" "$(zsh -n "$comp/_crew" >/dev/null 2>&1; echo $?)"
fi
if have bash; then
    check "crew.bash parses" "0" "$(bash -n "$comp/crew.bash" >/dev/null 2>&1; echo $?)"
fi

# The awk program that reads the usage text is the same in all three files.
parser() { sed -n '/# usage-parser begin/,/# usage-parser end/p' "$1"; }
check "the parser of _crew is the one of crew.bash" "$(parser "$comp/crew.bash")" "$(parser "$comp/_crew")"
check "the parser of crew.fish is the one of crew.bash" "$(parser "$comp/crew.bash")" "$(parser "$comp/crew.fish")"
check "the parser is there" "1" "$(parser "$comp/crew.bash" | grep -c '^        /\^  \[^ \]/ {$')"

# What it reads from the real usage text.
spec() { "$CREW_HOME/bin/crew" --help | awk "$(parser "$comp/crew.bash")"; }
words() { spec | awk -v c="$1" '$1 == c { $1 = ""; print }'; }
flags() { words "$1" | tr ' ' '\n' | sed -n 's/=.*//; /^--/p' | sort | tr '\n' ' ' | sed 's/ $//'; }
check "the first command" "help" "$(spec | sed -n 1p | cut -d' ' -f1)"
check "the last command" "version" "$(spec | tail -n 1 | cut -d' ' -f1)"
check "a command is a line" "1" "$(spec | grep -c '^peek ')"
check "spawn flags, across the lines of its usage" "--above --below --beside --cache --clone --join --kind --tab" "$(flags spawn)"
check "spawn takes a member after --beside" "1" "$(words spawn | grep -c -- ' --beside=member ')"
check "spawn takes a kind after --kind" "1" "$(words spawn | grep -c -- ' --kind=kind ')"
check "spawn's positionals" "<name> <cmd>..." "$(words spawn | tr ' ' '\n' | grep '^<' | tr '\n' ' ' | sed 's/ $//')"
check "move flags" "--above --below --beside" "$(flags move)"
check "gate flags" "--all --dry" "$(flags gate)"
check "watch flags" "--all --dry" "$(flags watch)"
check "join flags" "--no-pane --pane" "$(flags join)"
check "unread flags" "--peek --wait" "$(flags unread)"
check "unlock flags" "--force" "$(flags unlock)"
check "peek has no flag" "" "$(flags peek)"
check "send's positionals" "<from> <to> <subject>" "$(words send | sed "s/^ //")"
check "key's positionals" "<name> <key>..." "$(words key | sed "s/^ //")"
check "gate repeats its name" "<name>..." "$(words gate | tr ' ' '\n' | grep '^<' | tr '\n' ' ' | sed 's/ $//')"
check "the description is not read" "1" "$(spec | grep -c "^help$")"

# A command added to the usage text completes with no edit to the files.
future=$(
    printf 'usage: crew <command>\n\nFor everyone\n  help                 the protocol\n'
    printf '  focus <name>         bring <name> forward\n  land [--force]       merge\n'
    printf '  up <name>... [--kind <kind>]\n                       start them\n\ntrailer\n'
)
check "a command from the future" "focus <name>
land --force
up <name>... --kind=kind" "$(printf '%s\n' "$future" | awk "$(parser "$comp/crew.bash")" | sed 1d)"

# A crew of three members, two of them with a status, and two messages; crew
# on the PATH is a link to this checkout, as an install makes it.
crewdir=$tmp/c
mkdir -p "$crewdir/seq" "$crewdir/panes" "$crewdir/status" "$tmp/bin" "$tmp/home" "$tmp/fake"
ln -s "$CREW_HOME/bin/crew" "$tmp/bin/crew"
: >"$crewdir/panes/claude"
: >"$crewdir/panes/codex"
: >"$crewdir/status/claude.md"
: >"$crewdir/status/agy.md"
: >"$crewdir/seq/3"
: >"$crewdir/seq/12"

# Every command bin/crew dispatches, which the usage text must list too.
commands=$(sed -n '/^case "\$cmd" in$/,/^esac$/s/^\([a-z][a-z-]*\)[ |)].*/\1/p' "$CREW_HOME/bin/crew" | grep -vx case | sort | tr '\n' ' ' | sed 's/ $//')

# Each line is "<what is typed>|<what completes>", sorted; the last word of a
# line ending in a blank is empty.
cases() {
    printf 'crew |%s\n' "$commands"
    cat <<'EOF2'
crew pe|peek
crew peek cl|claude
crew peek |agy claude codex
crew peek claude |
crew peek --|
crew send |agy claude codex
crew send claude |agy all claude codex owner
crew send claude o|owner
crew send claude codex |
crew unread c|claude codex
crew gate claude co|codex
crew gate --|--all --dry
crew watch |agy claude codex
crew show |0003 0012
crew show 0003 |0003 0012
crew spawn |
crew spawn x --beside |agy claude codex
crew spawn x --kind |agy claude codex other
crew up |pair ring solo
crew up r|ring
crew spawn x --kind c|claude codex
crew spawn x --|--above --below --beside --cache --clone --join --kind --tab
crew spawn x --kind agy --b|--below --beside
crew spawn x --kind agy |
crew move claude --|--above --below --beside
crew move claude --below |agy claude codex
crew key |agy claude codex
crew key claude sh|shift-tab
crew key claude al|alt-
crew key claude alt-m|alt-m
crew key claude ctrl-c|ctrl-c
crew join --|--no-pane --pane
crew nosuch |
EOF2
}

# The drivers type a line and print the words completed, one a line. The
# crew is the one made above, or none with $nocrew set.
words_of() { tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//'; }
run_env() {
    if [ -n "${nocrew:-}" ]; then
        env -u CREW_DIR PATH="$tmp/bin:$PATH" HOME="$tmp/home" "$@"
    else
        env CREW_DIR="$crewdir" PATH="$tmp/bin:$PATH" HOME="$tmp/home" "$@"
    fi
}

cat >"$tmp/drive.bash" <<'EOF2'
. "$1"
read -ra COMP_WORDS <<<"$2"
case "$2" in *" ") COMP_WORDS+=("") ;; esac
COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
_crew
[ "${#COMPREPLY[@]}" -eq 0 ] || printf '%s\n' "${COMPREPLY[@]}"
EOF2
drive_bash() { run_env bash --norc --noprofile "$tmp/drive.bash" "$comp/crew.bash" "$1" </dev/null; }

# zsh sources the file without its last line, which runs _crew, and a compadd
# that prints the words starting with the one being completed.
cat >"$tmp/drive.zsh" <<'EOF2'
eval "$(sed '$d' "$1")"
compadd() {
    local -a v
    if [[ $1 == -a ]]; then
        v=(${(P)2})
    else
        while [[ $1 != -- ]]; do shift; done
        shift
        v=("$@")
    fi
    local a
    for a in $v; do
        [[ $a == $PREFIX* ]] && print -r -- $a
    done
    return 0
}
words=(${=2})
[[ $2 == *" " ]] && words+=("")
CURRENT=${#words}
PREFIX=$words[CURRENT]
_crew
EOF2
drive_zsh() { run_env zsh -f "$tmp/drive.zsh" "$comp/_crew" "$1" </dev/null; }

drive_fish() {
    run_env fish --no-config -c 'source $argv[1]; complete -C $argv[2]' "$comp/crew.fish" "$1" </dev/null | cut -f1
}

for sh in bash zsh fish; do
    have "$sh" || continue
    cases | while IFS='|' read -r line want; do
        got=$("drive_$sh" "$line" | words_of)
        if [ "$got" = "$want" ]; then
            echo ok
        else
            printf 'FAIL %s: %s\n  want: %s\n  got:  %s\n' "$sh" "$line" "$want" "$got"
        fi
    done >"$tmp/$sh.out"
    passed=$((passed + $(grep -c '^ok$' "$tmp/$sh.out")))
    failed=$((failed + $(grep -c '^FAIL' "$tmp/$sh.out")))
    grep -v '^ok$' "$tmp/$sh.out"

    # Outside a crew there are no members and no error.
    nocrew=1
    check "$sh: no member outside a crew" "" "$("drive_$sh" 'crew peek ' 2>&1 | words_of)"
    check "$sh: the commands outside a crew" "1" "$("drive_$sh" 'crew pe' 2>&1 | grep -c '^peek$')"
    nocrew=

    # The owner's kinds are added to the ones in share/kinds.
    mkdir -p "$tmp/config/crew"
    printf 'mycc mycc - ❯ enter #111111\n' >"$tmp/config/crew/kinds"
    check "$sh: the owner's kind" "mycc" "$(XDG_CONFIG_HOME=$tmp/config "drive_$sh" 'crew spawn x --kind my' | words_of)"
    rm -r "$tmp/config"
done

# A command that is not in this file completes as soon as it is in the usage.
cat >"$tmp/fake/crew" <<'EOF2'
#!/bin/sh
case "$1" in
--help) printf 'usage: crew <command>\n\nFor everyone\n  focus <name>      bring <name> forward\n  land [--force]    merge\n' ;;
dir) echo "$CREW_DIR" ;;
esac
EOF2
chmod +x "$tmp/fake/crew"
if have bash; then
    fake() { env CREW_DIR="$crewdir" PATH="$tmp/fake:$PATH" HOME="$tmp/home" bash --norc --noprofile "$tmp/drive.bash" "$comp/crew.bash" "$1" </dev/null | words_of; }
    check "bash: a command from the future" "focus" "$(fake 'crew fo')"
    check "bash: its member" "claude" "$(fake 'crew focus cl')"
    check "bash: its flag" "--force" "$(fake 'crew land --f')"
fi

finish
