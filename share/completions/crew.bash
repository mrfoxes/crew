# bash completion for crew: the commands, their flags, the members, the keys,
# the message numbers, and the kinds. Source it from ~/.bashrc.
#
# Nothing here lists a command or a flag: _crew_spec reads them from the
# usage text of 'crew --help' each time Tab is pressed, so a command added to
# bin/crew completes with no edit to this file. crew.fish and _crew hold the
# same awk program, which test/completions_test.sh keeps identical.

# One line a command: its name, then its words from the usage text, which are
# flags (--pane=pane when the flag takes a value) and positionals (<name>,
# <key>... when it repeats).
_crew_spec() {
    command crew --help 2>/dev/null | awk '
        # usage-parser begin
        /^  [^ ]/ {
            emit()
            line = substr($0, 3)
            cmd = line
            sub(/ .*/, "", cmd)
            syn = substr(line, length(cmd) + 1)
            if (match(syn, /  +[^ ]/)) {
                if (!dcol) dcol = 2 + length(cmd) + RSTART + RLENGTH - 1
                syn = substr(syn, 1, RSTART - 1)
            }
            next
        }
        /^   +[^ ]/ && cmd != "" {
            match($0, /[^ ]/)
            if (!dcol || RSTART < dcol) syn = syn " " $0
            next
        }
        /^[^ ]/ || /^$/ { emit() }
        END { emit() }
        function emit(    n, w, i, t, parts, np, j, words, type) {
            if (cmd == "") return
            words = ""
            np = 0
            n = split(syn, w, " ")
            for (i = 1; i <= n; i++) {
                t = w[i]
                gsub(/[[]/, "", t)
                gsub(/[]]/, "", t)
                if (t == "" || t == "|") continue
                if (t ~ /^</) {
                    type = t
                    if (np) {
                        sub(/^</, "", type)
                        sub(/>.*/, "", type)
                        for (j = 1; j <= np; j++) words = words " " parts[j] "=" type
                        np = 0
                    } else words = words " " t
                } else {
                    for (j = 1; j <= np; j++) words = words " " parts[j]
                    np = 0
                    if (t ~ /^--/) np = split(t, parts, "|")
                    else words = words " <" t ">"
                }
            }
            for (j = 1; j <= np; j++) words = words " " parts[j]
            print cmd words
            cmd = ""
        }
        # usage-parser end
    '
}

# The members: the panes and the statuses of the crew, once each. Nothing
# outside a crew, and no error.
_crew_members() {
    local dir
    dir=$(command crew dir 2>/dev/null) || return 0
    # shellcheck disable=SC2012 # member names are letters, digits, and dashes
    { ls -1 "$dir/panes"; ls -1 "$dir/status" | sed -n 's/\.md$//p'; } 2>/dev/null | sort -u
}

# The numbers of the messages, four digits as crew show reads them.
_crew_numbers() {
    local dir
    dir=$(command crew dir 2>/dev/null) || return 0
    # shellcheck disable=SC2012 # the names are numbers
    ls -1 "$dir/seq" 2>/dev/null | awk '{ printf "%04d\n", $1 }'
}

# The kinds: share/kinds of the checkout this crew runs from (found by
# following the links from the crew on PATH, as bin/crew does, so that the
# file is read wherever this one is installed or copied), then the owner's
# and the crew's own kinds files, and other. The kinds crew ships stand in
# when none can be read.
_crew_kinds() {
    local self link dir files f kinds
    self=$(command -v crew) || self=
    while [ -n "$self" ] && [ -L "$self" ]; do
        link=$(readlink "$self")
        case "$link" in
        /*) self=$link ;;
        *) self=$(dirname "$self")/$link ;;
        esac
    done
    files=("${XDG_CONFIG_HOME:-$HOME/.config}/crew/kinds")
    [ -z "$self" ] || files=("$(dirname "$self")/../share/kinds" "${files[@]}")
    dir=$(command crew dir 2>/dev/null) && files+=("$dir/kinds")
    kinds=$(
        for f in "${files[@]}"; do
            [ ! -f "$f" ] || cat "$f"
        done | awk '!/^[[:space:]]*(#|$)/ && NF >= 6 && !seen[$1]++ { print $1 }'
    )
    printf '%s\n' "${kinds:-claude codex agy}" other
}

# The presets: the owner's in ${XDG_CONFIG_HOME:-~/.config}/crew/presets, and
# the ones crew ships in share/presets of the checkout it runs from.
_crew_presets() {
    local self link
    self=$(command -v crew) || self=
    while [ -n "$self" ] && [ -L "$self" ]; do
        link=$(readlink "$self")
        case "$link" in
        /*) self=$link ;;
        *) self=$(dirname "$self")/$link ;;
        esac
    done
    {
        ls "${XDG_CONFIG_HOME:-$HOME/.config}/crew/presets" 2>/dev/null
        [ -z "$self" ] || ls "$(dirname "$self")/../share/presets" 2>/dev/null
    } | awk 'NF && !seen[$0]++'
}

# Sets COMPREPLY to the words of $1 (blanks or lines apart) that start with
# the word being completed.
_crew_reply() {
    local IFS=$' \n'
    # shellcheck disable=SC2207 # one word a line, and mapfile is not in bash 3
    COMPREPLY=($(compgen -W "$1" -- "$cur"))
}

_crew() {
    local cur=${COMP_WORDS[COMP_CWORD]} cmd line words w i skip pos type pick last letters
    COMPREPLY=()
    if [ "$COMP_CWORD" -eq 1 ]; then
        _crew_reply "$(_crew_spec | cut -d' ' -f1)"
        return 0
    fi
    cmd=${COMP_WORDS[1]}
    line=$(_crew_spec | awk -v c="$cmd" '$1 == c { print; exit }')
    [ -n "$line" ] || return 0
    words=${line#"$cmd"}

    # The words before this one: a flag that takes a value takes the next
    # word too, any other word is the next positional.
    skip=0 pos=0 type=
    for ((i = 2; i < COMP_CWORD; i++)); do
        if [ "$skip" -eq 1 ]; then
            skip=0
            continue
        fi
        w=${COMP_WORDS[i]}
        case "$w" in
        --*)
            case "$words " in
            *" $w="*) skip=1 ;;
            esac
            ;;
        *) pos=$((pos + 1)) ;;
        esac
    done

    # What this word is: a flag's value, or the next positional.
    if [ "$skip" -eq 1 ]; then
        w=${COMP_WORDS[COMP_CWORD - 1]}
        type=${words#*" $w="}
        type=${type%% *}
    elif [[ $cur != -* ]]; then
        pick=0 last=
        for w in $words; do
            case "$w" in
            \<*)
                pick=$((pick + 1))
                last=$w
                [ "$pick" -ne $((pos + 1)) ] || break
                ;;
            esac
        done
        case "$last" in
        *...) type=${last%...} ;;
        *) [ "$pick" -ne $((pos + 1)) ] || type=$last ;;
        esac
        type=${type#<}
        type=${type%>}
        # spawn names a new member: no name to complete.
        [ "$cmd $pos $type" != "spawn 0 name" ] || type=
    fi

    case "$type" in
    name | from | member) _crew_reply "$(_crew_members)" ;;
    to) _crew_reply "$(_crew_members)
all
owner" ;;
    number) _crew_reply "$(_crew_numbers)" ;;
    kind) _crew_reply "$(_crew_kinds)" ;;
    preset) _crew_reply "$(_crew_presets)" ;;
    key)
        case "$cur" in
        ctrl-* | alt-*)
            letters=
            for w in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
                letters="$letters ${cur%%-*}-$w"
            done
            _crew_reply "$letters"
            ;;
        *) _crew_reply "enter esc tab shift-tab up down left right home end space backspace delete ctrl- alt-" ;;
        esac
        ;;
    "")
        if [ "$skip" -eq 0 ] && [[ $cur == -* ]]; then
            letters=
            for w in $words; do
                case "$w" in
                --*) letters="$letters ${w%%=*}" ;;
                esac
            done
            _crew_reply "$letters"
        fi
        ;;
    esac
    # ctrl- and alt- wait for their letter.
    if [ "${#COMPREPLY[@]}" -eq 1 ]; then
        case "${COMPREPLY[0]}" in
        *-) compopt -o nospace 2>/dev/null ;;
        esac
    fi
    return 0
}

complete -F _crew crew
