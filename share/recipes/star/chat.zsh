#!/bin/zsh -f
# The owner's line to the coordinator: each message typed here is posted to
# the crew stream as a message from owner to coordinator.
#
# Keys (zle, emacs keymap):
#   Return               send the message
#   Shift+Return         new line (Option+Return too, when Option sends Esc)
#   multi-line paste     stays in the buffer until Return
#   Option+Delete        delete the word before the cursor (Ctrl-W too)
#   Option+Left/Right    move by word
#   Up/Down              move between lines, then through sent messages
#   Ctrl-C / Ctrl-D      stop (Ctrl-D on an empty line)

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

print -P '%B%F{yellow}Message for coordinator: Return sends, Shift+Return adds a line. Ctrl-C to stop.%f%b\n'

while :; do
    msg=
    vared -e -h -p '%B%F{yellow}owner>%f%b ' msg || break
    [[ -n ${msg//[[:space:]]/} ]] || continue
    lines=(${(f)msg})
    subject=${lines[1][1,60]}
    if crew send owner coordinator "Owner: $subject" -m "$msg" >/dev/null; then
        print -P '%F{242}sent%f'
        print -s -- "$msg"
    else
        print -P '%F{red}not sent%f'
    fi
done
