# fish completion for crew: the commands, their flags, the members, the keys,
# the message numbers, and the kinds. Link it into ~/.config/fish/completions/.
#
# Nothing here lists a command or a flag: __crew_spec reads them from the
# usage text of 'crew --help' each time Tab is pressed, so a command added to
# bin/crew completes with no edit to this file. crew.bash and _crew hold the
# same awk program, which test/completions_test.sh keeps identical.

# One line a command: its name, then its words from the usage text, which are
# flags (--pane=pane when the flag takes a value) and positionals (<name>,
# <key>... when it repeats).
function __crew_spec
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
end

# The members: the panes and the statuses of the crew, once each. Nothing
# outside a crew, and no error.
function __crew_members
    set -l dir (command crew dir 2>/dev/null)
    or return 0
    begin
        command ls -1 $dir/panes
        command ls -1 $dir/status | string replace -rf '\.md$' ''
    end 2>/dev/null | sort -u
end

# The numbers of the messages, four digits as crew show reads them.
function __crew_numbers
    set -l dir (command crew dir 2>/dev/null)
    or return 0
    command ls -1 $dir/seq 2>/dev/null | awk '{ printf "%04d\n", $1 }'
end

# The archives of the crew, by the name crew archive and crew reset give
# them, for crew restore and crew story.
function __crew_archives
    set -l dir (command crew dir 2>/dev/null)
    or return 0
    command ls -1 $dir/archive 2>/dev/null
end

# The kinds: share/kinds of the checkout this crew runs from (found by
# following the links from the crew on PATH, as bin/crew does, so that the
# file is read wherever this one is installed or copied), then the owner's
# and the crew's own kinds files, and other. The kinds crew ships stand in
# when none can be read.
function __crew_kinds
    set -l self (command -s crew)
    while test -n "$self" -a -L "$self"
        set -l link (readlink $self)
        switch $link
            case '/*'
                set self $link
            case '*'
                set self (dirname $self)/$link
        end
    end
    set -l config $XDG_CONFIG_HOME
    test -n "$config"; or set config $HOME/.config
    set -l files $config/crew/kinds
    test -z "$self"; or set files (dirname $self)/../share/kinds $files
    set -l dir (command crew dir 2>/dev/null)
    and set files $files $dir/kinds
    set -l kinds (for f in $files
        test -f $f; and cat $f
    end | awk '!/^[[:space:]]*(#|$)/ && NF >= 6 && !seen[$1]++ { print $1 }')
    test -n "$kinds"; or set kinds claude codex agy
    printf '%s\n' $kinds other
end

# The presets: the owner's in $XDG_CONFIG_HOME/crew/presets, and the ones
# crew ships in share/presets of the checkout it runs from.
function __crew_presets
    set -l self (command -s crew)
    while test -n "$self" -a -L "$self"
        set -l link (readlink $self)
        switch $link
            case '/*'
                set self $link
            case '*'
                set self (dirname $self)/$link
        end
    end
    set -l config $XDG_CONFIG_HOME
    test -n "$config"; or set config $HOME/.config
    begin
        ls $config/crew/presets 2>/dev/null
        test -z "$self"; or ls (dirname $self)/../share/presets 2>/dev/null
    end | awk 'NF && !seen[$0]++'
end

# The candidates for the word being completed.
function __crew_complete
    set -l tokens (commandline -opc)
    set -l cur (commandline -ct)
    if test (count $tokens) -le 1
        __crew_spec | string split -f1 ' '
        return
    end
    set -l cmd $tokens[2]
    set -l words
    for line in (__crew_spec)
        set -l f (string split ' ' -- $line)
        if test "$f[1]" = "$cmd"
            set -e f[1]
            set words $f
        end
    end
    set -q words[1]; or return

    # The words before this one: a flag that takes a value takes the next
    # word too, any other word is the next positional.
    set -l skip 0
    set -l pos 0
    for w in $tokens[3..-1]
        if test $skip -eq 1
            set skip 0
            continue
        end
        if string match -q -- '--*' $w
            string match -q -- "$w=*" $words
            and set skip 1
        else
            set pos (math $pos + 1)
        end
    end

    # What this word is: a flag's value, or the next positional.
    set -l type
    if test $skip -eq 1
        set type (string match -- "$tokens[-1]=*" $words | string replace -r -- '^[^=]*=' '')
    else if not string match -q -- '-*' $cur
        set -l positionals (string match -r -- '^<.*' $words)
        if test (count $positionals) -gt $pos
            set type $positionals[(math $pos + 1)]
        else if test (count $positionals) -gt 0
            set type $positionals[-1]
            string match -q -- '*...' $type; or set type
        end
        set type (string replace -r -- '^<(.*?)>(\.\.\.)?$' '$1' $type)
        # spawn names a new member: no name to complete.
        test "$cmd $pos $type" != "spawn 0 name"; or set type
    end

    switch "$type"
        case name from member
            __crew_members
        case to
            __crew_members
            printf '%s\n' all owner
        case number
            __crew_numbers
        case archive
            __crew_archives
        case kind
            __crew_kinds
        case preset
            __crew_presets
        case key
            if string match -q -r -- '^(ctrl|alt)-' $cur
                set -l prefix (string replace -r -- '-.*' '' $cur)
                for l in a b c d e f g h i j k l m n o p q r s t u v w x y z
                    echo $prefix-$l
                end
            else
                printf '%s\n' enter esc tab shift-tab up down left right home end space backspace delete ctrl- alt-
            end
        case ''
            if test $skip -eq 0; and string match -q -- '-*' $cur
                string replace -r '=.*' '' -- $words | string match -r -- '--.*'
            end
    end
end

complete -c crew -f -a '(__crew_complete)'
