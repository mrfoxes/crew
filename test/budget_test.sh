#!/bin/sh
# Budgets: budget= on a member's Crewfile line against what it spent, on
# the board and in the watch, which tells the owner at 80% and at 100%.
#
#   sh test/run.sh budget

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
printf 'tab main\nmember codex budget=60 -- codex\nmember agy budget=20 -- agy\nmember claude -- claude\n' >"$dir/Crewfile"

check "against a budget" "of a \$60 budget, 21%" "$(cost_against 12.60 60)"
check "against a budget passed" "of a \$20 budget, 150%" "$(cost_against 30 20)"
check "a budget with no price" "a \$20 budget, but no rate to price it" "$(cost_against "" 20)"

# The board's cost section says each budget.
cost_members() { echo codex agy claude; }
cost_sum() {
    printf '  codex    6.3M tokens  $12.60  $1.00 in the last hour\n'
    printf '  agy      1.1M tokens  no rate for gemini-4-argon\n'
    printf '  claude   4.0M tokens\n'
}
check "the board's budgets" "
== cost
  codex    6.3M tokens  \$12.60  \$1.00 in the last hour  of a \$60 budget, 21%
  agy      1.1M tokens  no rate for gemini-4-argon  a \$20 budget, but no rate to price it
  claude   4.0M tokens" "$(cost_board "$dir")"

# The watch, once a minute: told at 80% and at 100%, once each; a member
# crew cannot price said once; a member with no budget left alone.
gate_state=$tmp/state
gate_dirs "$gate_state"
names="codex agy claude"
now=1000
gate_now() { echo "$now"; }
gate_notify() { echo "notify $1: $2"; }
spent_codex=40
cost_spent() { [ "$2" != codex ] || echo "$spent_codex"; }
check "under 80%, nothing" "12:00:00 budget agy: \$20, but no rate prices its model: crew cost agy" "$(gate_budgets)"
gate_budget_at=$now
spent_codex=48
now=1030
check "not again within the minute" "" "$(gate_budgets)"
now=1060
check "at 80%, told" "12:00:00 budget codex: \$48 of \$60 (80%)
notify codex: Spent \$48 of its \$60 budget (80%). Keep it from messages to all: crew mute codex" "$(gate_budgets)"
gate_new budget codex 80 || :
gate_new budget agy unpriced || :
now=1120
check "80% is told once" "" "$(gate_budgets)"
spent_codex=61
now=1180
check "at 100%, told again" "12:00:00 budget codex: \$61 of \$60 (100%)
notify codex: Spent \$61 of its \$60 budget (100%). Keep it from messages to all: crew mute codex" "$(gate_budgets)"
check "a member with no budget is not looked at" "0" "$(gate_budgets | grep -c claude)"

# The live board's spent column says the budget.
term_tty() { return 1; }
printf 'codex 12.60\n' >"$dir/tmp/live.cost"
echo tmux:%1 >"$dir/panes/codex"
gh() { return 1; }
check "the live board's budget" "1" "$(live_frame "$dir" | grep -c '^codex .* 12.60/60$')"

finish
