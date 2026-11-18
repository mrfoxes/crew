#!/bin/zsh -f
# The owner's line to hq-lead: each message typed here is posted to the crew
# stream as a message from owner to hq-lead. A line that starts with one of
# the commands below runs here instead: it is not posted and wakes nobody.
#
# Commands:
#   /f [word...]   show the stream's filter, or set it (see "Stream filter")
#   /end <area>    send End: to each member of <area> by name, after a y
#   /help          show these commands
#
# Keys (zle, emacs keymap):
#   Return               send the message
#   Shift+Return         new line (Option+Return too, when Option sends Esc)
#   multi-line paste     stays in the buffer until Return
#   Option+Delete        delete the word before the cursor (Ctrl-W too)
#   Option+Left/Right    move by word
#   Up/Down              move between lines, then through sent messages
#   Ctrl-C / Ctrl-D      stop (Ctrl-D on an empty line)
# Usage: chat.zsh <crew dir>, run from the project root.
D=$1
filter_file=$D/work/hq-lead/stream.filter

# Ask tmux for modifyOtherKeys mode 1, so Shift+Return arrives as its own
# sequence instead of a plain Return; turn it off again on the way out.
print -n '\e[>4;1m'
trap "print -n '\e[>4m'" EXIT

WORDCHARS='_'

insert-newline() { LBUFFER+=$'\n' }
zle -N insert-newline

bindkey -e
bindkey '^[[27;2;13~' insert-newline     # Shift+Return, tmux extended-keys-format xterm
bindkey '^[[13;2u'    insert-newline     # Shift+Return, extended-keys-format csi-u
bindkey '^[^M'        insert-newline     # Option+Return (Esc+Return)
bindkey '^[^?'        backward-kill-word # Option+Delete
bindkey '^[^H'        backward-kill-word
bindkey '^[[3;3~'     kill-word          # Option+Fn+Delete
bindkey '^[[1;3D'     backward-word      # Option+Left
bindkey '^[[1;3C'     forward-word       # Option+Right

usage() {
    print -P '%F{242}/f [word...]  show or set the stream filter: hq, api, coord, Contract:, *%f'
    print -P '%F{242}/end <area>   send End: to each member of <area> by name%f'
}

# /f: with no word, show the filter; else write it, and stream.sh picks it up.
set_filter() {
    if (( $# == 0 )); then
        print -P "%F{242}filter: $(cat $filter_file 2>/dev/null || print hq)%f"
        return
    fi
    mkdir -p ${filter_file:h}
    print -r -- "$*" >$filter_file && print -P "%F{242}filter: $*%f"
}

# /end <area>: End: by name to each member of the area's tab, then a note to
# hq-lead, which closes the area once each Done: is in (Scaling, rule 5).
end_area() {
    local area=$1 tab=$D/tabs/$1
    if [[ -z $area || $area == hq || $area == svc || ! -s $tab ]]; then
        print -P "%F{red}no area '$area': see $D/tabs/%f"
        return
    fi
    local -a members=(${(f)"$(<$tab)"})
    read -q "?End area $area: ${members[*]}? [y/N] " || { print; return; }
    print
    local m sent=()
    for m in $members; do
        crew send owner $m "End: land or save a patch, write your report, send Done:" >/dev/null && sent+=$m
    done
    crew send owner hq-lead "Owner: closing area $area" \
        -m "End: sent to ${sent[*]}. Wait for each Done:, then close the area (Scaling, rule 5)." >/dev/null
    print -P "%F{242}End: sent to ${sent[*]}%f"
}

print -P '%B%F{yellow}Message for hq-lead: Return sends, Shift+Return adds a line, /help for commands. Ctrl-C to stop.%f%b\n'

while :; do
    msg=
    vared -e -h -p '%B%F{yellow}owner>%f%b ' msg || break
    [[ -n ${msg//[[:space:]]/} ]] || continue
    print -s -- "$msg"
    words=(${=msg})
    case $words[1] in
    /f)    set_filter $words[2,-1]; continue ;;
    /end)  end_area $words[2]; continue ;;
    /help) usage; continue ;;
    esac
    lines=(${(f)msg})
    subject=${lines[1][1,60]}
    if crew send owner hq-lead "Owner: $subject" -m "$msg" >/dev/null; then
        print -P '%F{242}sent%f'
    else
        print -P '%F{red}not sent%f'
    fi
done
