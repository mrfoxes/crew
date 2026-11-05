#!/bin/sh
# The loop from crew send to a pane to crew unread, end to end, in a tmux
# server of its own: crew up opens the watch, the board, and two members,
# fake agents that draw the captured screens of test/fixtures/ and record
# the bytes they are sent. It types only into panes it made, in a server on
# a socket under a temporary directory (tmux -S, no configuration), killed
# on exit: the owner's tmux and iTerm2 are never reachable from here. Every
# wait is bounded.
#
#   sh test/run.sh e2e
#
# Not part of 'sh test/run.sh' without arguments; CI runs it as a job.

set -u
here=$(cd "$(dirname "$0")" && pwd)
CREW_HOME=$(dirname "$here")
tmux_bin=$(command -v tmux) || {
    echo "crew: e2e needs tmux" >&2
    echo "e2e: 0 passed, 1 failed"
    exit 1
}

# Nothing of the owner's reaches the run: no server, crew, pane, or agent.
unset CREW_DIR TMUX TMUX_PANE ITERM_SESSION_ID TERM_SESSION_ID \
    CLAUDECODE CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID CREW_IDLE_MINUTES
tmp=$(mktemp -d)
sock=$tmp/tmux.sock
cleanup() {
    "$tmux_bin" -S "$sock" kill-server 2>/dev/null || :
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

passed=0
failed=0
check() {
    if [ "$2" = "$3" ]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$2" "$3"
    fi
}

# Runs <command>... every second until it succeeds, at most <seconds>
# times; its status says whether it did.
wait_for() {
    w_left=$1
    shift
    while ! "$@" >/dev/null 2>&1; do
        w_left=$((w_left - 1))
        [ "$w_left" -gt 0 ] || return 1
        sleep 1
    done
}
has() { grep -q -- "$2" "$1" 2>/dev/null; }
tm() { "$tmux_bin" -u -S "$sock" "$@"; }
screen() { tm capture-pane -p -t "$1"; }
# Whether any pane of the server shows <text>.
any_screen_has() {
    for as_pane in $(tm list-panes -s -t e2e -F '#{pane_id}'); do
        screen "$as_pane" | grep -q -- "$1" && return 0
    done
    return 1
}

# The world of the run: a project cloned from a bare origin, a home and a
# configuration of its own, fake agents named claude on the PATH.
export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/config
export CREW_WAKE=1 CREW_NOTIFY=0
export CREW_CODEX_HOME=$tmp/none CREW_AGY_HOME=$tmp/none CREW_CLAUDE_HOME=$tmp/none
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$tmp/agents/bin" "$tmp/agents/sh" "$tmp/log"
ln -s /bin/sh "$tmp/agents/sh/claude"
cat >"$tmp/agents/bin/claude" <<EOT
#!$tmp/agents/sh/claude
. "$here/e2e/agent.sh"
EOT
chmod +x "$tmp/agents/bin/claude"
# crew's own tmux commands read the screens as UTF-8 whatever the locale.
cat >"$tmp/agents/bin/tmux" <<EOT
#!/bin/sh
exec "$tmux_bin" -u "\$@"
EOT
chmod +x "$tmp/agents/bin/tmux"
# A prompt the gate must hold: the captured command prompt, another command.
sed 's|touch /private/tmp/crew-fixture-touch|git reset --hard HEAD~3|' \
    "$here/fixtures/claude-run.txt" >"$tmp/forbidden.txt"
export E2E_LOG=$tmp/log E2E_FIXTURES=$here/fixtures
export PATH="$tmp/agents/bin:$CREW_HOME/bin:$PATH"

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/project" 2>/dev/null
cd "$tmp/project" || exit 1
git config user.name e2e
git config user.email e2e@example.com
echo one >one.txt
git add one.txt
git commit -q -m "first"
git push -q origin HEAD:main 2>/dev/null
git branch -q -M main
git branch -q --set-upstream-to=origin/main main 2>/dev/null

# The server, and a pane that is the coordinator's. Every crew command
# below runs as that pane would: TMUX and TMUX_PANE name it.
tm -f /dev/null new-session -d -s e2e -x 240 -y 200 -c "$tmp/project" "sh"
coord=$(tm display-message -p -t e2e:0 '#{pane_id}')
server_pid=$(tm display-message -p '#{pid}')
export TMUX="$sock,$server_pid,0" TMUX_PANE=$coord
check "the server is the run's own" "$sock" "$(tm display-message -p '#{socket_path}')"

crew init >/dev/null
crewdir=$(crew dir)
cat >"$crewdir/Crewfile" <<'EOT'
tab main layout=main watch board
member ada reviewer=bob -- E2E_NAME=ada claude
member bob reviewer=ada -- E2E_NAME=bob claude
EOT
# Each fake agent reads its name from the line it was started with.
check "crew up brings the crew up" "0" "$(crew up >"$tmp/up.out" 2>&1; echo $?)"
ada=$(cat "$crewdir/panes/ada" 2>/dev/null)
bob=$(cat "$crewdir/panes/bob" 2>/dev/null)
check "ada has a tmux pane" "tmux:%" "$(printf '%s' "$ada" | cut -c1-6)"
check "bob has a tmux pane" "tmux:%" "$(printf '%s' "$bob" | cut -c1-6)"
check "watch and board panes opened" "5" "$(tm list-panes -s -t e2e -F x | wc -l | tr -d ' ')"
check "the focus is left on the coordinator's pane" "$coord" "$(tm display-message -p -t e2e '#{pane_id}')"

# Invited, each agent runs crew join and gets the protocol.
check "ada joined" "0" "$(wait_for 20 has "$tmp/log/ada.out" 'The crew protocol'; echo $?)"
check "bob joined" "0" "$(wait_for 20 has "$tmp/log/bob.out" 'The crew protocol'; echo $?)"
check "ada is a claude" "claude" "$(cat "$crewdir/kind/ada" 2>/dev/null)"

# A message to bob wakes its pane with the one line, and bob reads it.
crew send ada bob "Question: are you there" >/dev/null <<'EOT'
The body of the question.
EOT
check "bob is woken" "0" "$(wait_for 20 has "$tmp/log/bob.in" 'crew: message .* from ada. Run: crew unread bob'; echo $?)"
check "bob reads the message" "0" "$(wait_for 20 has "$tmp/log/bob.out" 'The body of the question'; echo $?)"

# A command prompt the rules allow is approved once, by the key of its kind.
tm send-keys -t "${ada#tmux:}" -l "!ask $here/fixtures/claude-run.txt"
tm send-keys -t "${ada#tmux:}" Enter
check "an allowed prompt is answered" "0" "$(wait_for 20 has "$tmp/log/ada.in" 'answer: \[\]'; echo $?)"
check "and only once" "1" "$(grep -c '^answer:' "$tmp/log/ada.in")"

# One the rules forbid is held: nothing presses a key.
tm send-keys -t "${bob#tmux:}" -l "!ask $tmp/forbidden.txt"
tm send-keys -t "${bob#tmux:}" Enter
sleep 6
check "a forbidden prompt is not answered" "0" "$(grep -c '^answer:' "$tmp/log/bob.in")"
check "the watch says it holds it" "0" "$(wait_for 10 any_screen_has 'HOLD bob'; echo $?)"
tm send-keys -t "${bob#tmux:}" Enter
check "the owner answers it" "0" "$(wait_for 10 has "$tmp/log/bob.in" 'answer: \[\]'; echo $?)"

# A landing from ada: committed, pushed to the bare origin, and told to bob.
echo two >two.txt
crew status ada >/dev/null <<'EOT'
Agent: ada
Start: 00:00  End: 23:59
Issue: two
Files: two.txt
Pushed: none
Next: land
Blocked on: nothing
EOT
echo "Add two.txt" >"$tmp/msg"
check "crew land pushes" "0" "$(crew land ada -F "$tmp/msg" --to bob --check true -- two.txt >"$tmp/land.out" 2>&1; echo $?)"
check "the origin has the commit" "Add two.txt" "$(git --git-dir="$tmp/origin.git" log -1 --format=%s main)"
check "bob is told" "0" "$(wait_for 20 has "$tmp/log/bob.in" 'from ada. Run: crew unread bob'; echo $?)"
check "bob reads the Pushed:" "0" "$(crew unread bob 2>/dev/null | grep -q 'Pushed: .*Add two.txt'; echo $?)"

# crew clear refuses a background shell in ada's footer, and types nothing.
draw_in() {
    tm send-keys -t "${1#tmux:}" -l "!draw $here/fixtures/$2"
    tm send-keys -t "${1#tmux:}" Enter
}
shows() { screen "${1#tmux:}" | grep -q -- "$2"; }
draw_in "$ada" claude-shell.txt
check "ada draws a background shell" "0" "$(wait_for 10 shows "$ada" '1 shell still running'; echo $?)"
check "crew clear refuses it" "1" "$(crew clear ada >"$tmp/clear.out" 2>"$tmp/clear.err"; echo $?)"
check "and says why" "0" "$(has "$tmp/clear.err" "a background shell runs in ada's pane"; echo $?)"
check "nothing is typed" "0" "$(grep -c '^/clear' "$tmp/log/ada.in")"

# A clear at ada's idle prompt: /clear, then the line to rejoin. A message
# sent while the clear runs is held, never typed into it, and ada reads it
# once it rejoined.
draw_in "$ada" claude-idle.txt
not_shows() { ! shows "$@"; }
check "ada is idle again" "0" "$(wait_for 10 not_shows "$ada" '1 shell'; echo $?)"
: >"$tmp/log/ada.slow"
crew clear ada >"$tmp/clear.out" 2>"$tmp/clear.err" &
clear_pid=$!
check "crew clear types /clear" "0" "$(wait_for 20 grep -q '^/clear$' "$tmp/log/ada.in"; echo $?)"
crew send bob ada "Question: still there" >/dev/null 2>"$tmp/send.err" <<'EOT'
Sent while ada was cleared.
EOT
# The watch's relay wakes ada: held, the wake is recorded, not typed.
held() { ls "$crewdir"/tmp/wake.*.ada >/dev/null 2>&1; }
check "the wake waits for the clear" "0" "$(wait_for 10 held; echo $?)"
rm -f "$tmp/log/ada.slow"
wait "$clear_pid"
check "crew clear goes through" "0" "$?"
check "it says ada took the line to rejoin" "cleared ada: it took the line to rejoin (crew join ada) and to resume from its Next:" "$(cat "$tmp/clear.out")"
check "the line after /clear is the one to rejoin, no wake" 'crew: your context was cleared. Run: crew join ada, then crew status ada, and resume from its Next: line. Work in caveman mode ($caveman) from now on.' "$(sed -n '/^\/clear$/{n;p;}' "$tmp/log/ada.in")"
joined() { [ "$(grep -c 'The crew protocol' "$tmp/log/$1.out" 2>/dev/null)" -ge "$2" ]; }
check "ada rejoined" "0" "$(wait_for 20 joined ada 2; echo $?)"
check "ada reads the message held" "0" "$(wait_for 20 has "$tmp/log/ada.out" 'Sent while ada was cleared'; echo $?)"

# A compact with instructions types /compact and them, waits for the
# compacted mark, and types nothing after: ada waits at its empty prompt.
check "crew compact goes through" "0" "$(crew compact ada keep the task >"$tmp/compact.out" 2>&1; echo $?)"
check "it says so" "compacted ada" "$(cat "$tmp/compact.out")"
check "the instructions go with /compact, nothing after" "/compact keep the task" "$(tail -n 1 "$tmp/log/ada.in")"
# The lowest line that starts with the mark is the input line: empty.
at_prompt() {
    screen "${1#tmux:}" | LC_ALL=C awk '
        index($0, "\342\235\257") == 1 { l = $0; gsub(/\302\240| /, "", l) }
        END { exit l != "\342\235\257" }'
}
check "ada shows the compacted mark" "0" "$(shows "$ada" 'Compacted (ctrl+o'; echo $?)"
check "ada waits at its empty prompt" "0" "$(at_prompt "$ada"; echo $?)"

# crew up --restart refuses the background shell the compacted screen
# still shows, and types nothing.
check "crew up --restart refuses a background shell" "1" "$(crew up --restart ada >"$tmp/restart.out" 2>"$tmp/restart.err"; echo $?)"
check "and says why" "0" "$(has "$tmp/restart.err" "a background shell runs in ada's pane"; echo $?)"
check "nothing is typed" "0" "$(grep -c '^/exit' "$tmp/log/ada.in")"

# A restart at ada's idle prompt: /exit, then its Crewfile line with
# --resume and the session it joined with, then the invitation. A message
# sent while it runs is held, and ada reads it once it is back.
draw_in "$ada" claude-idle.txt
check "ada is idle for the restart" "0" "$(wait_for 10 not_shows "$ada" '1 shell'; echo $?)"
ada_session=$(cat "$crewdir/sessions/ada" 2>/dev/null)
check "crew join recorded ada's session" "e2e-ada-" "$(printf '%s' "$ada_session" | cut -c1-8)"
: >"$tmp/log/ada.slow"
crew up --restart ada >"$tmp/restart.out" 2>"$tmp/restart.err" &
restart_pid=$!
check "crew up --restart types /exit" "0" "$(wait_for 20 grep -q '^/exit$' "$tmp/log/ada.in"; echo $?)"
crew send bob ada "Question: back yet" >/dev/null 2>"$tmp/send.err" <<'EOT'
Sent while ada was restarted.
EOT
check "the wake waits for the restart" "0" "$(wait_for 10 held; echo $?)"
rm -f "$tmp/log/ada.slow"
wait "$restart_pid"
check "crew up --restart goes through" "0" "$?"
check "it says so" "0" "$(has "$tmp/restart.out" '^restarted ada on its Crewfile line$'; echo $?)"
check "ada's agent runs its line with --resume" "args: [--resume $ada_session]" "$(tail -n 1 "$tmp/log/ada.args")"
check "ada is invited and joins" "0" "$(wait_for 20 joined ada 3; echo $?)"
check "ada reads the message held" "0" "$(wait_for 20 has "$tmp/log/ada.out" 'Sent while ada was restarted'; echo $?)"

# ada's Crewfile line changed under its live agent: crew up says so, and
# restarts nothing; bob's line, as it was, says nothing.
sed 's/^member ada reviewer=bob -- E2E_NAME=ada claude$/member ada reviewer=bob -- E2E_NAME=ada E2E_NEW=1 claude/' \
    "$crewdir/Crewfile" >"$tmp/Crewfile" && cp "$tmp/Crewfile" "$crewdir/Crewfile"
check "crew up with ada's line changed" "0" "$(crew up >"$tmp/up4.out" 2>&1; echo $?)"
check "it says the line changed" "crew: ada's Crewfile line changed since it started; 'crew up --restart ada' restarts it" "$(grep "^crew: ada's" "$tmp/up4.out")"
check "and restarts nothing" "1" "$(grep -c '^/exit' "$tmp/log/ada.in")"
check "bob's line says nothing" "" "$(grep "^crew: bob's" "$tmp/up4.out")"

# The end: crew down sends End: and waits for a Done: from each. ada leaves
# without one, which frees the wait for it; bob sends its Done: and stays
# up. --close closes the pane whose agent exited, and only that one.
crew down 1 --close >"$tmp/down.out" 2>&1 &
down_pid=$!
check "End: is sent" "0" "$(wait_for 20 grep -q 'End:' "$tmp/down.out"; echo $?)"
# The End: wakes ada with a line typed into its pane: "/exit", Claude Code's
# quit, waits until that line is in, or the two are typed into one line and
# ada never leaves (macOS CI saw it).
check "ada is woken for End:" "0" "$(wait_for 20 grep -q 'from owner\. Run: crew unread ada' "$tmp/log/ada.in"; echo $?)"
tm send-keys -t "${ada#tmux:}" -l '/exit'
tm send-keys -t "${ada#tmux:}" Enter
# tmux names the command by its path on macOS: compare its last part.
agent_left() { [ "$(tm display-message -p -t "${ada#tmux:}" '#{pane_current_command}' | sed 's#.*/##')" != claude ]; }
check "ada's agent left its pane" "0" "$(wait_for 20 agent_left; echo $?)"
# crew down closes a pane once ps shows only a shell in its foreground, as
# term_running reads it; tmux's pane_current_command can turn first, with a
# child of the agent still in the foreground for a moment (macOS CI saw it).
ada_tty=$(tm display-message -p -t "${ada#tmux:}" '#{pane_tty}')
shell_only() {
    ps -t "${ada_tty#/dev/}" -o stat=,comm= | awk '
        $1 ~ /\+/ { sub(/.*\//, "", $2); sub(/^-/, "", $2); if ($2 !~ /^(sh|bash|zsh|fish|dash|ksh|tcsh|login)$/) busy = 1 }
        END { exit busy }'
}
# On a failure, what holds the foreground goes to stderr, for CI's log.
check "only a shell is left in ada's pane" "0" "$(wait_for 20 shell_only && echo 0 || { ps -t "${ada_tty#/dev/}" -o pid=,ppid=,stat=,comm=,args= >&2; echo 1; })"
crew send bob all "Done: nothing left" >/dev/null <<'EOT'
Done.
EOT
wait "$down_pid"
check "ada's pane is closed" "0" "$(tm list-panes -s -t e2e -F '#{pane_id}' | grep -c "^${ada#tmux:}\$")"
check "bob's pane, its agent running, is not" "1" "$(tm list-panes -s -t e2e -F '#{pane_id}' | grep -c "^${bob#tmux:}\$")"

# The next crew: crew reset puts this one aside, bob's agent still up, and
# leaves the directory as crew init makes it. It refuses while the relay
# the watch ran lets go, so it is tried until it goes through.
reset_once() { crew reset >"$tmp/reset.out" 2>"$tmp/reset.err"; }
check "crew reset goes through" "0" "$(wait_for 15 reset_once; echo $?)"
check "it names the pane that still runs its agent" "crew: bob's pane $bob still runs its agent; it is no member now" "$(cat "$tmp/reset.err")"
check "it leaves the plan crew init writes" "0" "$(cmp -s "$crewdir/README.md" "$CREW_HOME/share/plan.md"; echo $?)"
check "and no Crewfile, member, or message" "" "$(find "$crewdir/Crewfile" "$crewdir/panes" "$crewdir/kind" "$crewdir/messages" "$crewdir/tabs" -type f 2>/dev/null)"
for e2e_pane in $(tm list-panes -s -t e2e -F '#{pane_id}'); do
    [ "$e2e_pane" = "$coord" ] || tm kill-pane -t "$e2e_pane"
done

# A crew around its coordinator: qa over it on the left, dev1 over dev2 on
# the right, as tmux draws it.
cat >"$crewdir/Crewfile" <<'EOT'
tab main layout=2x2
member qa   -- E2E_NAME=qa claude
member dev1 -- E2E_NAME=dev1 claude
pane coordinator
member dev2 -- E2E_NAME=dev2 claude
EOT
# Each pane's place: 0 in the first column or row, + past it. A row's top
# is not 0: crew turns on the border's status line above the panes.
place() {
    printf '%s ' "$2"
    tm display-message -p -t "${1#tmux:}" '#{pane_left} #{pane_top}'
}
grid() {
    {
        place "$(cat "$crewdir/panes/qa")" qa
        place "$(cat "$crewdir/panes/dev1")" dev1
        place "$1" coordinator
        place "$(cat "$crewdir/panes/dev2")" dev2
    } | awk '
        { n[NR] = $1; l[NR] = $2; t[NR] = $3
          if (NR == 1 || $2 < ml) ml = $2
          if (NR == 1 || $3 < mt) mt = $3 }
        END { for (i = 1; i <= NR; i++) print n[i], (l[i] == ml ? "0" : "+"), (t[i] == mt ? "0" : "+") }'
}
check "crew up brings the crew around the coordinator" "0" "$(crew up >"$tmp/up2.out" 2>&1; echo $?)"
for m in qa dev1 dev2; do
    check "$m joined" "0" "$(wait_for 20 joined "$m" 1; echo $?)"
done
check "the tab's order puts the coordinator's pane third" "qa dev1 tmux:$coord dev2" "$(tr '\n' ' ' <"$crewdir/tabs/main" | sed 's/ $//')"
check "2x2 draws qa and dev1 on top, the coordinator and dev2 under them" "qa 0 0
dev1 + 0
coordinator 0 +
dev2 + +" "$(grid "$coord")"

# crew reset with three members up names each; crew restore brings the crew
# back with no pane, and crew up, run from another coordinator's pane now,
# puts the members back and that pane in the coordinator's place.
check "crew reset again" "0" "$(crew reset >"$tmp/reset.out" 2>"$tmp/reset.err"; echo $?)"
check "it names each pane that still runs its agent" "dev1 dev2 qa" "$(sed -n "s/^crew: \([a-z0-9]*\)'s pane tmux:%[0-9]* still runs its agent; it is no member now\$/\1/p" "$tmp/reset.err" | sort | tr '\n' ' ' | sed 's/ $//')"
coord2=$(tm new-window -d -P -F '#{pane_id}' -t e2e -c "$tmp/project" sh)
for e2e_pane in $(tm list-panes -s -t e2e -F '#{pane_id}'); do
    [ "$e2e_pane" = "$coord2" ] || tm kill-pane -t "$e2e_pane"
done
export TMUX_PANE=$coord2
check "crew restore" "0" "$(crew restore >"$tmp/restore.out" 2>&1; echo $?)"
check "it says to bring the members back" "run 'crew up' to bring the members back" "$(tail -n 1 "$tmp/restore.out")"
check "the restored crew has no pane" "" "$(find "$crewdir/panes" -type f; grep 'tmux:' "$crewdir/tabs/main")"
check "crew up brings them back" "0" "$(crew up >"$tmp/up3.out" 2>&1; echo $?)"
for m in qa dev1 dev2; do
    check "$m joined again" "0" "$(wait_for 20 joined "$m" 2; echo $?)"
done
check "the new coordinator's pane is in its place, the old one gone" "qa dev1 tmux:$coord2 dev2" "$(tr '\n' ' ' <"$crewdir/tabs/main" | sed 's/ $//')"
check "2x2 again, around the new coordinator's pane" "qa 0 0
dev1 + 0
coordinator 0 +
dev2 + +" "$(grid "$coord2")"

# What the run saw, for a failure to be read from CI's log.
if [ "$failed" -gt 0 ]; then
    for dump_pane in $(tm list-panes -s -t e2e -F '#{pane_id}' 2>/dev/null); do
        printf -- '--- pane %s\n' "$dump_pane"
        screen "$dump_pane" | grep . | tail -n 15
    done
    printf -- '--- messages\n'
    ls "$crewdir/messages" 2>/dev/null | tail -n 12
    for dump_file in up.out land.out clear.out clear.err send.err compact.out restart.out restart.err up4.out down.out reset.out reset.err up2.out restore.out up3.out; do
        printf -- '--- %s\n' "$dump_file"
        tail -n 15 "$tmp/$dump_file" 2>/dev/null
    done
    for dump_file in "$tmp"/log/*; do
        printf -- '--- %s\n' "${dump_file##*/}"
        tail -n 8 "$dump_file"
    done
fi
printf 'e2e: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
