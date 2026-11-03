#!/bin/sh
# The doctor's tests: each check against a machine of stubs, healthy first
# and then missing a terminal, a tool, an agent, or a skill, and a crew with
# a stale lock or a gone pane. Nothing here asks the real machine.
#
#   sh test/run.sh doctor

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

# A machine with everything the doctor looks for, one stub for each call it
# makes; a test takes one thing away.
export HOME="$tmp/home"
mkdir -p "$HOME/.codex/skills/caveman" "$HOME/.gemini/skills/caveman" "$HOME/.claude/plugins" "$tmp/bin"
echo '{"plugins": {"caveman@caveman": []}}' >"$HOME/.claude/plugins/installed_plugins.json"
ln -s "$CREW_HOME/bin/crew" "$tmp/bin/crew"
doctor_which() { if [ "$1" = crew ]; then echo "$tmp/bin/crew"; else echo "/usr/bin/$1"; fi; }
doctor_iterm_version() { echo 3.7.5; }
doctor_iterm_running() { return 0; }
doctor_tmux_version() { echo 3.8; }
doctor_agent_version() {
    case "$1" in
    claude) echo 2.1.317 ;;
    codex) echo 0.166.0 ;;
    agy) echo 1.4.12 ;;
    esac
}
doctor_gh_authed() { return 0; }
term_list() { :; }
term_running() { return 0; }

# The doctor's report and its status, kept in files: a pipe would hide the
# status.
report() { crew_doctor >"$tmp/report" 2>&1; echo $? >"$tmp/status"; }
status() { cat "$tmp/status"; }
has() { grep -c -- "$1" "$tmp/report"; }

report
check "a healthy machine exits 0" "0" "$(status)"
check "a healthy machine has no warn or fail" "0" "$(grep -c '^warn\|^fail' "$tmp/report")"
check "iTerm2 is read and running" "1" "$(has '^ok    iTerm2: 3.7.5, running$')"
check "tmux is read" "1" "$(has '^ok    tmux: 3.8$')"
check "crew resolves to this checkout" "1" "$(has "^ok    crew: $tmp/bin/crew, this checkout$")"
check "each agent is read against its fixtures" "1" "$(has '^ok    codex: 0.166.0, fixtures from 0.166.0$')"
check "the plugin is found" "1" "$(has '^ok    caveman: the plugin for claude$')"
check "outside a crew" "1" "$(has "^ok    session: not inside a crew")"
check "the summary" "1" "$(has '^doctor: 0 warn, 0 fail$')"

# A terminal short of a feature, or absent.
doctor_tmux_version() { echo 3.0; }
report
check "an old tmux warns" "1" "$(has '^warn  tmux: 3.0 is older than 3.1$')"
check "an old tmux says what to do" "1" "$(has 'select-layout -E')"
check "an old tmux is no fail" "0" "$(status)"
doctor_tmux_version() { :; }
report
check "no tmux, with iTerm2, is ok" "1" "$(has '^ok    tmux: not installed (iTerm2 is enough)$')"
doctor_tmux_version() { echo 3.8; }
doctor_iterm_version() { echo 3.4.23; }
report
check "an old iTerm2 warns" "1" "$(has '^warn  iTerm2: 3.4.23 is older than 3.5$')"
doctor_iterm_version() { :; }
report
check "no iTerm2, with tmux, is ok" "1" "$(has '^ok    iTerm2: not installed (tmux is enough)$')"
doctor_iterm_version() { echo 3.7.5; }
doctor_iterm_running() { return 1; }
report
check "iTerm2 not running is said" "1" "$(has '^ok    iTerm2: 3.7.5, not running$')"
doctor_iterm_running() { return 0; }
doctor_iterm_version() { :; }
doctor_tmux_version() { :; }
report
check "no terminal at all fails" "1" "$(has '^fail  terminal: neither iTerm2 nor tmux found$')"
check "no terminal at all exits 1" "1" "$(status)"
check "no terminal at all counts" "1" "$(has '^doctor: 0 warn, 1 fail$')"
doctor_iterm_version() { echo 3.7.5; }
doctor_tmux_version() { echo 3.8; }

# crew off PATH, and crew on PATH from another checkout.
doctor_which() { [ "$1" = crew ] || echo "/usr/bin/$1"; }
report
check "crew off PATH warns" "1" "$(has '^warn  crew: not on PATH$')"
check "crew off PATH says the ln line" "1" "$(has "ln -s \"$CREW_HOME/bin/crew\" ~/.local/bin/crew")"
mkdir -p "$tmp/other/bin"
ln -s "$tmp/other/bin/crew" "$tmp/bin/elsewhere"
doctor_which() { if [ "$1" = crew ]; then echo "$tmp/bin/elsewhere"; else echo "/usr/bin/$1"; fi; }
report
check "crew from another checkout warns" "1" "$(has "^warn  crew: $tmp/bin/elsewhere resolves to $tmp/other, not this checkout")"
doctor_which() { echo "/usr/bin/$1"; }

# An agent missing, one newer than its fixtures, or of a version unread.
doctor_which() { if [ "$1" = codex ]; then :; elif [ "$1" = crew ]; then echo "$tmp/bin/crew"; else echo "/usr/bin/$1"; fi; }
report
check "a missing agent warns" "1" "$(has '^warn  codex: codex is not on PATH$')"
check "a missing agent is no fail" "0" "$(status)"
check "a missing agent skips its skill" "0" "$(has '^.*caveman: .*codex')"
doctor_which() { if [ "$1" = crew ]; then echo "$tmp/bin/crew"; else echo "/usr/bin/$1"; fi; }
doctor_agent_version() {
    case "$1" in
    claude) echo 2.1.400 ;;
    codex) echo 0.170.0 ;;
    agy) echo 1.4.12 ;;
    esac
}
report
check "an agent newer than its fixtures warns" "1" "$(has '^warn  claude: 2.1.400 is newer than its fixtures (2.1.317)$')"
check "the newest fixture of the kind counts" "1" "$(has '^warn  codex: 0.170.0 is newer than its fixtures (0.166.0)$')"
check "it says to capture again" "2" "$(has "crew peek <name> 40")"
check "an agent as old as its fixtures is ok" "1" "$(has '^ok    agy: 1.4.12, fixtures from 1.4.12$')"
doctor_agent_version() { echo 2.1.315; }
report
check "an agent between its fixtures is ok" "1" "$(has '^ok    claude: 2.1.315, fixtures from 2.1.317$')"
doctor_agent_version() { :; }
report
check "an agent that prints no version is ok" "1" "$(has '^ok    agy: agy, version unknown$')"
doctor_agent_version() {
    case "$1" in
    claude) echo 2.1.317 ;;
    codex) echo 0.166.0 ;;
    agy) echo 1.4.12 ;;
    esac
}
printf 'mycc mycc - ❯ enter #111111\n' >"$tmp/kinds"
mkdir -p "$XDG_CONFIG_HOME/crew"
cp "$tmp/kinds" "$XDG_CONFIG_HOME/crew/kinds"
doctor_agent_version() { echo 1.0.0; }
report
check "a kind with no fixtures is ok" "1" "$(has '^ok    mycc: 1.0.0, no fixtures to compare$')"
rm -r "$XDG_CONFIG_HOME/crew"
doctor_agent_version() {
    case "$1" in
    claude) echo 2.1.317 ;;
    codex) echo 0.166.0 ;;
    agy) echo 1.4.12 ;;
    esac
}

# The caveman skills.
rmdir "$HOME/.codex/skills/caveman"
report
check "a missing Codex skill warns" "1" "$(has "^warn  caveman: no skill for codex at $HOME/.codex/skills/caveman$")"
check "a missing skill is no fail" "0" "$(status)"
rmdir "$HOME/.gemini/skills/caveman"
report
check "a missing Antigravity skill warns" "1" "$(has "^warn  caveman: no skill for agy at $HOME/.gemini/skills/caveman$")"
rm "$HOME/.claude/plugins/installed_plugins.json"
report
check "a missing Claude Code plugin warns" "1" "$(has '^warn  caveman: no plugin for claude$')"
mkdir -p "$HOME/.claude/skills/caveman"
report
check "a Claude Code skill counts" "1" "$(has '^ok    caveman: the plugin for claude$')"
mkdir -p "$HOME/.codex/skills/caveman" "$HOME/.gemini/skills/caveman"
echo '{"plugins": {"caveman@caveman": []}}' >"$HOME/.claude/plugins/installed_plugins.json"

# A notifier and gh.
doctor_which() {
    case "$1" in
    osascript | notify-send) ;;
    crew) echo "$tmp/bin/crew" ;;
    *) echo "/usr/bin/$1" ;;
    esac
}
report
check "no notifier warns" "1" "$(has '^warn  notifier: no osascript or notify-send$')"
doctor_which() { if [ "$1" = osascript ]; then :; elif [ "$1" = crew ]; then echo "$tmp/bin/crew"; else echo "/usr/bin/$1"; fi; }
report
check "notify-send alone is a notifier" "1" "$(has '^ok    notifier: notify-send$')"
doctor_which() { if [ "$1" = gh ]; then :; elif [ "$1" = crew ]; then echo "$tmp/bin/crew"; else echo "/usr/bin/$1"; fi; }
report
check "no gh warns" "1" "$(has '^warn  gh: not installed$')"
doctor_which() { if [ "$1" = crew ]; then echo "$tmp/bin/crew"; else echo "/usr/bin/$1"; fi; }
doctor_gh_authed() { return 1; }
report
check "gh not logged in warns" "1" "$(has '^warn  gh: not logged in$')"
doctor_gh_authed() { return 0; }

# Inside a crew: its directory, a lock, a relay, and the panes.
git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
report
check "a crew is named" "1" "$(has "^ok    session: the crew at $dir$")"
check "a free lock" "1" "$(has '^ok    lock: free$')"
check "no relay is only said" "1" "$(has '^ok    relay: not running')"
mkdir "$dir/lock"
echo "codex 12:00" >"$dir/lock/owner"
report
check "a fresh lock is ok" "1" "$(has '^ok    lock: held by codex 12:00 for 0 minutes$')"
touch -t 200001010000 "$dir/lock"
report
check "a stale lock warns" "1" "$(has '^warn  lock: held by codex 12:00 for [0-9]* minutes$')"
check "a stale lock says what to do" "1" "$(has "crew unlock --force")"
rm -r "$dir/lock"
echo $$ >"$dir/relay.pid"
report
check "a relay is said" "1" "$(has '^ok    relay: running$')"
rm "$dir/relay.pid"
echo tmux:%1 >"$dir/panes/claude"
echo tmux:%2 >"$dir/panes/codex"
term_list() { printf 'tmux:%%1\t/dev/ttys001\tx\n'; }
report
check "a pane that is there is ok" "1" "$(has '^ok    member claude: pane tmux:%1$')"
check "a gone pane warns" "1" "$(has '^warn  member codex: pane tmux:%2 is gone$')"
check "a gone pane says crew leave" "1" "$(has '      crew leave codex$')"
check "a gone pane is no fail" "0" "$(status)"
term_running() { return 1; }
report
check "a pane back at a shell warns" "1" "$(has '^warn  member claude: pane tmux:%1 is back at a shell$')"
check "a pane back at a shell says crew up or crew leave" "1" "$(has '      crew up, or crew leave claude$')"
term_running() { return 0; }

# Inside a crew: the Crewfile and its budgets against the rates.
cat >"$dir/Crewfile" <<'EOF'
tab main layout=main watch board
member claude reviewer=codex -- claude
tab work layout=table
member codex reviewer=agy budget=60 -- codex
member agy reviewer=claude -- agy
EOF
report
check "a good Crewfile is ok" "1" "$(has '^ok    Crewfile: 2 tabs, 3 members$')"
check "a budget of a member with no log yet does not warn" "0" "$(has '^warn  budget codex:')"
printf 'gpt-6-other 5.00 0.50 - 30.00 30.00\n' >"$dir/rates"
export CREW_CODEX_HOME="$here/fixtures/cost/codex"
echo 00000000-0000-4000-8000-000000000001 >"$dir/threads/codex"
echo codex >"$dir/kind/codex"
report
check "a budget whose model no rate prices warns" "1" "$(has '^warn  budget codex: \$60, but no rate for gpt-6-astra$')"
check "it names the rates file to add to" "1" "$(has "add a rate to $dir/rates")"
printf 'gpt-6-astra 5.00 0.50 - 30.00 30.00\n' >>"$dir/rates"
report
check "a budget with rates for its model does not warn" "0" "$(has '^warn  budget codex:')"
printf 'tab main\nmember bad broken\n' >"$dir/Crewfile"
report
check "a broken Crewfile fails with its file and line" "1" "$(has "^fail  Crewfile: $dir/Crewfile:2: ")"
check "a broken Crewfile exits 1" "1" "$(status)"
rm -f "$dir/Crewfile" "$dir/rates" "$dir/threads/codex" "$dir/kind/codex"

# Doctor changes nothing: the crew is as it was.
check "the crew is untouched" "claude
codex" "$(ls "$dir/panes")"
check "arguments are refused" "2" "$(crew_doctor now >/dev/null 2>&1; echo $?)"

finish
