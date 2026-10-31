#!/bin/sh
# The cost tests: varints decoded, each agent's log read from a fixture cut
# from a real one, the rates read and overridden, and the sums in the cost
# command and in the board. Nothing here reads the agents' real logs.
#
#   sh test/run.sh cost

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

fx=$here/fixtures/cost
export CREW_CODEX_HOME=$fx/codex CREW_CLAUDE_HOME=$fx/claude
thread=00000000-0000-4000-8000-000000000001
session=00000000-0000-4000-8000-000000000002

# Varints: one byte, the 128 that needs two, 300, a longer one, and several
# in a row.
check "a one-byte varint" "5" "$(cost_varints 05)"
check "the largest one-byte varint" "127" "$(cost_varints 7F)"
check "a two-byte varint" "128" "$(cost_varints 8001)"
check "another two-byte varint" "300" "$(cost_varints AC02)"
check "a four-byte varint" "10000000" "$(cost_varints 80ADE204)"
check "varints in a row" "5 300 1" "$(cost_varints 05AC0201 | tr '\n' ' ' | sed 's/ $//')"
check "lower-case hex" "300" "$(cost_varints ac02)"

# Codex: the rows add up to the last total, its input without the cached and
# written tokens and its output without the reasoning.
sum() { awk '{ for (i = 1; i <= 5; i++) t[i] += $(i + 2) } END { print t[1], t[2], t[3], t[4], t[5] }'; }
check "codex rows sum to the last total" "180 5816568 479235 13549 11778" "$(cost_codex_rows $thread | sum)"
check "codex rows name the model" "gpt-6-astra" "$(cost_codex_rows $thread | cut -d' ' -f2 | sort -u)"
check "codex rows carry the time" "2026-10-31T14:52:51.186Z" "$(cost_codex_rows $thread | sed -n 1p | cut -d' ' -f1)"
check "a thread with no log" "1" "$(cost_codex_rows 00000000-0000-4000-8000-0000000000ff >/dev/null; echo $?)"
check "a thread that is a glob" "1" "$(cost_codex_rows '*' >/dev/null; echo $?)"

# Claude Code: a message on two lines counts once.
check "claude rows count a message once" "3" "$(cost_claude_rows $session | wc -l | tr -d ' ')"
check "claude rows sum" "6 194015 24778 1039 318" "$(cost_claude_rows $session | sum)"
check "claude rows take the thinking out of the output" "claude-opus-5-5 2 26973 23077 222 126" "$(cost_claude_rows $session | sed -n 1p | cut -d' ' -f2-)"
check "a session with no log" "1" "$(cost_claude_rows 00000000-0000-4000-8000-0000000000ff >/dev/null; echo $?)"

# Antigravity: three real rows of gen_metadata, as hex.
check "agy rows sum" "15798 69967 0 720 465" "$(cost_agy_decode <"$fx/agy-gen-metadata.hex" | sum)"
check "agy rows name the model" "gemini-4-argon" "$(cost_agy_decode <"$fx/agy-gen-metadata.hex" | cut -d' ' -f2 | sort -u)"
check "agy rows have no time" "-" "$(cost_agy_decode <"$fx/agy-gen-metadata.hex" | cut -d' ' -f1 | sort -u)"

# The hour before a moment, as the logs write it.
check "the cutoff" "1970-01-01T00:00:00" "$(CREW_COST_NOW=3600 cost_cutoff)"

# A crew: a Codex member, a Claude Code member, and one that never joined.
git init -q "$tmp/repo"
cd "$tmp/repo" || exit 1
dir=$(crew_init)
mkdir -p "$dir/sessions"
echo codex >"$dir/kind/cx"
echo $thread >"$dir/threads/cx"
echo claude >"$dir/kind/cc"
echo $session >"$dir/sessions/cc"
echo codex >"$dir/kind/idle"
check "members" "cc
cx
idle" "$(cost_members "$dir")"

# No rates: tokens, and a word for each model without a price.
want="cc       input 6  cached 194015  write 24778  output 1039  reasoning 318  no rate for claude-opus-5-5
cx       input 180  cached 5816568  write 479235  output 13549  reasoning 11778  no rate for gpt-6-astra
idle     no thread recorded: it has not joined from Codex
total    input 186  cached 6010583  write 504013  output 14588  reasoning 12096"
check "cost without rates" "$want" "$(crew_cost)"
check "cost of one member" "cx       input 180  cached 5816568  write 479235  output 13549  reasoning 11778  no rate for gpt-6-astra
total    input 180  cached 5816568  write 479235  output 13549  reasoning 11778" "$(crew_cost cx)"
check "cost of a name that is not one" "2" "$(crew_cost 'A b' >/dev/null 2>&1; echo $?)"

# The owner's rates price one model; the other has none. A - is no price.
mkdir -p "$XDG_CONFIG_HOME/crew"
printf '# dollars per million tokens\n# model input cached write output reasoning\ngpt-6-astra 1 1 1 1 1\n' >"$XDG_CONFIG_HOME/crew/rates"
check "the owner's rates price a model, not another" "cc       input 6  cached 194015  write 24778  output 1039  reasoning 318  no rate for claude-opus-5-5
cx       input 180  cached 5816568  write 479235  output 13549  reasoning 11778  \$6.32" "$(crew_cost cc cx | sed -n 1,2p)"
check "the total prices what has a rate" "total    input 186  cached 6010583  write 504013  output 14588  reasoning 12096  \$6.32" "$(crew_cost | tail -n 1)"
printf 'gpt-6-astra 2 0.2 - 8 8\nclaude-opus-5-5 15 1.5 18.75 75 75\n' >"$dir/rates"
check "the crew's rates replace the owner's" "1.37" "$(crew_cost cx | sed -n 1p | sed 's/.*\$//')"
check "and add to them" "0.86" "$(crew_cost cc | sed -n 1p | sed 's/.*\$//')"
rm -r "$XDG_CONFIG_HOME/crew"

# The board ends with each member's total, and the last hour's where the
# log has times: the last event of the Codex fixture is 16:52Z.
board=$(CREW_COST_NOW=1793467200 crew_board 1)
check "the board's last section is the cost" "== cost" "$(printf '%s\n' "$board" | grep '^==' | tail -n 1)"
check "the board prices a member and its last hour" "  cx       6.3M tokens  \$1.37  \$1.35 in the last hour" "$(printf '%s\n' "$board" | grep '^  cx ')"
check "the board says a member has no log" "  idle     no thread recorded: it has not joined from Codex" "$(printf '%s\n' "$board" | grep '^  idle ')"
check "an hour with nothing in it" "\$0.00 in the last hour" "$(CREW_COST_NOW=1893467200 crew_board 1 | grep '^  cx ' | sed 's/.*  //; s/.*\(\$0.00 in the last hour\)/\1/')"
rm "$dir/rates"

# Join records the session Claude Code runs under, leave forgets it.
check "join records the session" "abc-123" "$(CLAUDE_CODE_SESSION_ID=abc-123 crew_join cc >/dev/null; cat "$dir/sessions/cc")"
check "leave forgets the session" "" "$(crew_leave cc >/dev/null; cat "$dir/sessions/cc" 2>/dev/null)"

# A session whose log is not there.
echo claude >"$dir/kind/cc"
echo 00000000-0000-4000-8000-0000000000ff >"$dir/sessions/cc"
check "a session with no log" "cc       no Claude Code log for the session 00000000-0000-4000-8000-0000000000ff" "$(crew_cost cc | sed -n 1p)"
rm "$dir/sessions/cc"
check "a member with no session" "cc       no session recorded: it joined before crew kept one" "$(crew_cost cc | sed -n 1p)"

# Antigravity, through a database built here with sqlite3: found by the
# name that joins, 'agy' not matching 'agy2', and read.
if command -v sqlite3 >/dev/null 2>&1; then
    export CREW_AGY_HOME=$tmp/agy
    mkdir -p "$CREW_AGY_HOME/conversations"
    db=$CREW_AGY_HOME/conversations/c1.db
    {
        echo 'create table steps (idx integer, step_payload blob);'
        echo 'create table gen_metadata (idx integer, data blob);'
        echo "insert into steps values (0, 'Run: crew join agy2. Then follow it.');"
        i=0
        while read -r hex; do
            echo "insert into gen_metadata values ($i, x'$hex');"
            i=$((i + 1))
        done <"$fx/agy-gen-metadata.hex"
    } | sqlite3 "$db"
    check "a conversation is found by the name that joins" "$db" "$(cost_agy_db agy2)"
    check "a name that only begins like it is not" "" "$(cost_agy_db agy)"
    check "agy rows from a database" "15798 69967 0 720 465" "$(cost_agy_rows "$db" | sum)"
    echo agy >"$dir/kind/agy2"
    check "cost of an agy member" "agy2     input 15798  cached 69967  write 0  output 720  reasoning 465  no rate for gemini-4-argon" "$(crew_cost agy2 | sed -n 1p)"
    check "an agy member that never joined" "agy      no Antigravity conversation began with 'crew join agy'" "$(echo agy >"$dir/kind/agy"; crew_cost agy | sed -n 1p)"
    # A machine without sqlite3 says so and goes on.
    sqlite3() { return 127; }
    cost_has_sqlite3() { return 1; }
    check "no sqlite3 is said, not failed" "agy2     sqlite3 is not installed: Antigravity's usage cannot be read" "$(crew_cost agy2 | sed -n 1p)"
fi

finish
