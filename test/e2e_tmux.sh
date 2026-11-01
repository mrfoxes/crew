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

# The end: crew down sends End: and waits for a Done: from each. ada leaves
# without one, which frees the wait for it; bob sends its Done: and stays
# up. --close closes the pane whose agent exited, and only that one.
crew down 1 --close >"$tmp/down.out" 2>&1 &
down_pid=$!
check "End: is sent" "0" "$(wait_for 20 grep -q 'End:' "$tmp/down.out"; echo $?)"
tm send-keys -t "${ada#tmux:}" -l '!exit'
tm send-keys -t "${ada#tmux:}" Enter
agent_left() { [ "$(tm display-message -p -t "${ada#tmux:}" '#{pane_current_command}')" != claude ]; }
check "ada's agent left its pane" "0" "$(wait_for 20 agent_left; echo $?)"
crew send bob all "Done: nothing left" >/dev/null <<'EOT'
Done.
EOT
wait "$down_pid"
check "ada's pane is closed" "0" "$(tm list-panes -s -t e2e -F '#{pane_id}' | grep -c "^${ada#tmux:}\$")"
check "bob's pane, its agent running, is not" "1" "$(tm list-panes -s -t e2e -F '#{pane_id}' | grep -c "^${bob#tmux:}\$")"

# What the run saw, for a failure to be read from CI's log.
if [ "$failed" -gt 0 ]; then
    for dump_pane in $(tm list-panes -s -t e2e -F '#{pane_id}' 2>/dev/null); do
        printf -- '--- pane %s\n' "$dump_pane"
        screen "$dump_pane" | grep . | tail -n 15
    done
    printf -- '--- messages\n'
    ls "$crewdir/messages" 2>/dev/null | tail -n 12
    for dump_file in up.out land.out down.out; do
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
