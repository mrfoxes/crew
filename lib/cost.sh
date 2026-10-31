# crew cost: what the members spent, read from the logs their agents keep
# on this machine, never from the network. Each kind has a reader of its
# own that prints one row for every use of the model:
#
#   <time> <model> <new input> <cached input> <cache write> <output> <reasoning>
#
# (time is - when the log has none), and one awk sums the rows by member
# and model and prices them from the rates file. A reader takes the root of
# its agent's files from a variable (CREW_CODEX_HOME, CREW_AGY_HOME,
# CREW_CLAUDE_HOME) so that a test can point it at fixtures. Its variables
# start with c_: it runs inside commands whose own it must not touch.
# Sourced by bin/crew.

# The rates: a line for each model, dollars per million tokens, from the
# owner's ${XDG_CONFIG_HOME:-~/.config}/crew/rates and then the crew's own
# rates, a later line for a model replacing an earlier one. crew ships none.
cost_rates() {
    c_rdir=$(crew_dir 2>/dev/null) || c_rdir=""
    for c_rfile in "${XDG_CONFIG_HOME:-$HOME/.config}/crew/rates" ${c_rdir:+"$c_rdir/rates"}; do
        [ ! -f "$c_rfile" ] || cat "$c_rfile"
    done | awk '!/^[[:space:]]*(#|$)/ && NF >= 6 { print "rate", $1, $2, $3, $4, $5, $6 }'
}

# The time an hour ago, as the logs write it (UTC, to the second), for
# telling the last hour's rows. CREW_COST_NOW (epoch seconds) stands in for
# the clock in a test. BSD date takes -r, GNU date -d.
cost_cutoff() {
    c_then=$((${CREW_COST_NOW:-$(date +%s)} - 3600))
    date -u -r "$c_then" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null ||
        date -u -d "@$c_then" '+%Y-%m-%dT%H:%M:%S'
}

# What both Codex and the totals read a number with: the integer after
# "<key>": in s, or 0.
COST_NUM='
function num(s, key,    i) {
    i = index(s, "\"" key "\":")
    if (!i) return 0
    s = substr(s, i + length(key) + 3)
    match(s, /^[0-9]+/)
    return substr(s, 1, RLENGTH) + 0
}'

# Codex: the rows of the rollout for thread <id>, found under
# ${CREW_CODEX_HOME:-~/.codex}/sessions/. Its token_count events carry the
# cumulative total, so a row is the difference from the event before, and
# the rows add up to the last total. Its input counts the cached and the
# written tokens, and its output the reasoning, so each is taken out of the
# count it sits in.
cost_codex_rows() {
    case "$1" in
    "" | *[!A-Za-z0-9-]*) return 1 ;;
    esac
    c_log=$(ls "${CREW_CODEX_HOME:-$HOME/.codex}"/sessions/*/*/*/rollout-*-"$1".jsonl 2>/dev/null | head -n 1)
    [ -n "$c_log" ] || return 1
    grep -e '"type":"turn_context"' -e '"type":"token_count"' "$c_log" | awk "$COST_NUM"'
        /"type":"turn_context"/ {
            if (match($0, /"model":"[^"]*"/)) model = substr($0, RSTART + 9, RLENGTH - 10)
            next
        }
        /"total_token_usage":\{/ {
            s = substr($0, index($0, "\"total_token_usage\":{"))
            s = substr(s, 1, index(s, "}"))
            now[2] = num(s, "cached_input_tokens")
            now[3] = num(s, "cache_write_input_tokens")
            now[1] = num(s, "input_tokens") - now[2] - now[3]
            now[5] = num(s, "reasoning_output_tokens")
            now[4] = num(s, "output_tokens") - now[5]
            ts = "-"
            if (match($0, /"timestamp":"[^"]*"/)) ts = substr($0, RSTART + 13, RLENGTH - 14)
            line = ts " " (model == "" ? "unknown" : model)
            any = 0
            for (i = 1; i <= 5; i++) {
                d = now[i] - last[i]
                if (d < 0) d = now[i]
                if (d < 0) d = 0
                line = line " " d
                any += d
                last[i] = now[i]
            }
            if (any) print line
        }'
}

# Antigravity: awk to read a protobuf, from the hex of its bytes.
# varint(h, i) is the number whose bytes start at byte i of h, and pb_next
# the byte after it.
COST_PB='
function byte(h, i) {
    return (index("0123456789ABCDEF", substr(h, 2 * i + 1, 1)) - 1) * 16 + index("0123456789ABCDEF", substr(h, 2 * i + 2, 1)) - 1
}
function varint(h, i,    v, m, b) {
    v = 0
    m = 1
    while (1) {
        b = byte(h, i++)
        if (b < 0) break
        v += (b % 128) * m
        m *= 128
        if (b < 128) break
    }
    pb_next = i
    return v
}
function text(h, i, len,    s, k) {
    s = ""
    for (k = 0; k < len; k++) s = s sprintf("%c", byte(h, i + k))
    return s
}'

# The numbers a hex string of consecutive varints holds, one a line.
cost_varints() {
    awk -v h="$1" "$COST_PB"'
        BEGIN {
            h = toupper(h)
            for (i = 0; i < length(h) / 2; i = pb_next) print varint(h, i)
        }'
}

# Antigravity: the rows of the hex rows of a conversation's gen_metadata,
# one a line on stdin. Each row's field 1 holds, in its field 4, the
# usage: field 2 new input, 3 output, 5 cache read, 9 thinking; the model
# is field 19 of field 1. The log has no time for them.
cost_agy_decode() {
    awk "$COST_PB"'
        function walk(h, i, end, lvl,    tag, f, w, len, n) {
            while (i < end) {
                tag = varint(h, i)
                i = pb_next
                f = int(tag / 8)
                w = tag % 8
                if (w == 0) {
                    n = varint(h, i)
                    i = pb_next
                    if (lvl == 2) val[f] = n
                } else if (w == 2) {
                    len = varint(h, i)
                    i = pb_next
                    if (lvl == 1 && f == 19) model = text(h, i, len)
                    else if ((lvl == 0 && f == 1) || (lvl == 1 && f == 4)) walk(h, i, i + len, lvl + 1)
                    i += len
                } else if (w == 1) i += 8
                else if (w == 5) i += 4
                else return
            }
        }
        NF {
            delete val
            model = ""
            h = toupper($1)
            walk(h, 0, length(h) / 2, 0)
            print "-", (model == "" ? "unknown" : model), val[2] + 0, val[5] + 0, 0, val[3] + 0, val[9] + 0
        }'
}

# Whether sqlite3 is here, which Antigravity's logs need.
cost_has_sqlite3() {
    command -v sqlite3 >/dev/null 2>&1
}

# Antigravity: the conversation of <name> under
# ${CREW_AGY_HOME:-~/.gemini/antigravity-cli}/conversations/: the newest
# whose first steps hold 'crew join <name>'. None without sqlite3.
cost_agy_db() {
    cost_has_sqlite3 || return 2
    ls -t "${CREW_AGY_HOME:-$HOME/.gemini/antigravity-cli}"/conversations/*.db 2>/dev/null | while IFS= read -r c_db; do
        if sqlite3 -readonly "$c_db" 'select cast(step_payload as text) from steps where idx < 4' 2>/dev/null |
            grep -aqE "crew join $1([^a-z0-9-]|\$)"; then
            echo "$c_db"
            exit
        fi
    done
}

# Antigravity: the rows of the conversation in the database <db>.
cost_agy_rows() {
    sqlite3 -readonly "$1" 'select hex(data) from gen_metadata order by idx' 2>/dev/null | cost_agy_decode
}

# Claude Code: the rows of session <id>, from
# ${CREW_CLAUDE_HOME:-~/.claude}/projects/*/<id>.jsonl. A message is written
# on a line for each block of its content, each with the same usage, the
# last the whole one: it counts once. Claude Code counts the thinking in
# the output tokens, so it is taken out of them.
cost_claude_rows() {
    case "$1" in
    "" | *[!A-Za-z0-9-]*) return 1 ;;
    esac
    c_log=$(ls "${CREW_CLAUDE_HOME:-$HOME/.claude}"/projects/*/"$1".jsonl 2>/dev/null | head -n 1)
    [ -n "$c_log" ] || return 1
    grep -e '"usage":{' "$c_log" | awk "$COST_NUM"'
        {
            if (!match($0, /"id":"msg_[^"]*"/)) next
            id = substr($0, RSTART + 6, RLENGTH - 7)
            s = substr($0, index($0, "\"usage\":{"), 600)
            if (!(id in seen)) {
                seen[id] = ++n
                order[n] = id
            }
            ts = "-"
            if (match($0, /"timestamp":"[^"]*"/)) ts = substr($0, RSTART + 13, RLENGTH - 14)
            model = "unknown"
            if (match($0, /"model":"[^"]*"/)) model = substr($0, RSTART + 9, RLENGTH - 10)
            think = num(s, "thinking_tokens")
            row[id] = ts " " model " " num(s, "input_tokens") " " num(s, "cache_read_input_tokens") " " \
                num(s, "cache_creation_input_tokens") " " (num(s, "output_tokens") - think) " " think
        }
        END { for (i = 1; i <= n; i++) print row[order[i]] }'
}

# Every member of the crew in <dir>: one with a pane, a thread, a session,
# or a kind recorded.
cost_members() {
    (
        cd "$1" || exit
        ls panes threads sessions kind 2>/dev/null
    ) | grep -v ':$' | grep -v '^$' | sort -u
}

# What the usage of <name> is, as lines for cost_report: a row for each use
# of the model, or a note saying why there is none.
cost_member() {
    c_who=$2
    c_kind=$(kind_member "$1" "$c_who")
    if [ -z "$c_kind" ]; then
        if [ -s "$1/threads/$c_who" ]; then c_kind=codex; elif [ -s "$1/sessions/$c_who" ]; then c_kind=claude; fi
    fi
    c_rows=""
    case "$c_kind" in
    codex)
        c_id=$(cat "$1/threads/$c_who" 2>/dev/null) || c_id=""
        if [ -z "$c_id" ]; then
            echo "note $c_who no thread recorded: it has not joined from Codex"
        elif c_rows=$(cost_codex_rows "$c_id") && [ -n "$c_rows" ]; then
            :
        else
            echo "note $c_who no Codex log for the thread $c_id"
        fi
        ;;
    claude)
        c_id=$(cat "$1/sessions/$c_who" 2>/dev/null) || c_id=""
        if [ -z "$c_id" ]; then
            echo "note $c_who no session recorded: it joined before crew kept one"
        elif c_rows=$(cost_claude_rows "$c_id") && [ -n "$c_rows" ]; then
            :
        else
            echo "note $c_who no Claude Code log for the session $c_id"
        fi
        ;;
    agy)
        c_status=0
        c_db=$(cost_agy_db "$c_who") || c_status=$?
        if [ "$c_status" -eq 2 ]; then
            echo "note $c_who sqlite3 is not installed: Antigravity's usage cannot be read"
        elif [ -z "$c_db" ]; then
            echo "note $c_who no Antigravity conversation began with 'crew join $c_who'"
        elif ! c_rows=$(cost_agy_rows "$c_db") || [ -z "$c_rows" ]; then
            c_rows=""
            echo "note $c_who no usage in the Antigravity conversation"
        fi
        ;;
    *) echo "note $c_who no usage log for a member of kind ${c_kind:-unknown}" ;;
    esac
    [ -z "$c_rows" ] || printf '%s\n' "$c_rows" | awk -v n="$c_who" '{ print "row", n, $0 }'
}

# Sums rows by member and model, prices them, and prints them. The input is
# the rates (rate <model> <five prices>), then rows and notes, as
# cost_member prints them. The mode is report (a line a member and a total)
# or board (a short line a member).
COST_SUM='
function human(n) {
    if (n >= 1000000) return sprintf("%.1fM", n / 1000000)
    if (n >= 1000) return sprintf("%.1fk", n / 1000)
    return n
}
function money(m, v,    i, d) {
    d = 0
    for (i = 1; i <= 5; i++) d += v[i] * price[m, i] / 1000000
    return d
}
$1 == "rate" {
    priced[$2] = 1
    for (i = 1; i <= 5; i++) price[$2, i] = ($(i + 2) == "-") ? 0 : $(i + 2)
    next
}
$1 == "note" {
    who = $2
    if (!(who in known)) { known[who] = ++n; names[n] = who }
    $1 = ""
    $2 = ""
    note[who] = substr($0, 3)
    next
}
$1 == "row" {
    who = $2
    if (!(who in known)) { known[who] = ++n; names[n] = who }
    m = $4
    if (!((who, m) in has)) { has[who, m] = 1; models[who] = models[who] " " m }
    for (i = 1; i <= 5; i++) {
        tok[who, m, i] += $(i + 4)
        if ($3 != "-" && $3 >= cutoff) hour[who, m, i] += $(i + 4)
    }
    if ($3 != "-") timed[who] = 1
    next
}
END {
    for (k = 1; k <= n; k++) {
        who = names[k]
        delete t
        delete h
        dollars = 0
        hdollars = 0
        missing = ""
        nm = split(models[who], ms, " ")
        for (j = 1; j <= nm; j++) {
            m = ms[j]
            delete mt
            delete mh
            for (i = 1; i <= 5; i++) {
                mt[i] = tok[who, m, i]
                mh[i] = hour[who, m, i] + 0
                t[i] += mt[i]
                h[i] += mh[i]
                T[i] += mt[i]
            }
            if (m in priced) {
                dollars += money(m, mt)
                hdollars += money(m, mh)
                anyp[who] = 1
            } else missing = missing (missing == "" ? "" : ", ") m
        }
        if (nm == 0) {
            if (mode == "report") printf "%-8s %s\n", who, note[who]
            else printf "  %-8s %s\n", who, note[who]
            continue
        }
        total = t[1] + t[2] + t[3] + t[4] + t[5]
        if (mode == "report") {
            line = sprintf("%-8s input %d  cached %d  write %d  output %d  reasoning %d", who, t[1], t[2], t[3], t[4], t[5])
            if (anyp[who]) line = line sprintf("  $%.2f", dollars)
            if (missing != "") line = line "  no rate for " missing
            print line
        } else {
            line = sprintf("  %-8s %s tokens", who, human(total))
            if (anyp[who]) line = line sprintf("  $%.2f", dollars)
            if (anyp[who] && timed[who]) line = line sprintf("  $%.2f in the last hour", hdollars)
            else if (timed[who]) line = line sprintf("  %s tokens in the last hour", human(h[1] + h[2] + h[3] + h[4] + h[5]))
            if (missing != "") line = line "  no rate for " missing
            print line
        }
        any++
        D += dollars
        for (i = 1; i <= 5; i++) A[i] += t[i]
        if (anyp[who]) pricedany = 1
    }
    if (mode == "report" && any) {
        line = sprintf("%-8s input %d  cached %d  write %d  output %d  reasoning %d", "total", A[1], A[2], A[3], A[4], A[5])
        if (pricedany) line = line sprintf("  $%.2f", D)
        print line
    }
}'

# The usage of the members <names> of the crew in <dir>, summed: <mode> is
# report or board.
cost_sum() {
    c_mode=$1
    c_dir=$2
    shift 2
    {
        cost_rates
        for c_name in "$@"; do
            cost_member "$c_dir" "$c_name"
        done
    } | awk -v mode="$c_mode" -v cutoff="$(cost_cutoff)" "$COST_SUM"
}

# What the members spent: tokens, and dollars where the rates price the
# model, a line a member and a total. Read only: the logs of the agents on
# this machine, no network.
crew_cost() {
    dir=$(crew_dir) || return 1
    if [ $# -gt 0 ]; then
        for c_name in "$@"; do
            crew_member "$c_name" || return 2
        done
    else
        # shellcheck disable=SC2046 # member names hold no space
        set -- $(cost_members "$dir")
    fi
    if [ $# -eq 0 ]; then
        echo "crew: no member to count"
        return
    fi
    cost_sum report "$dir" "$@"
}

# The last section of the board: each member's running total.
cost_board() {
    c_dir=$1
    # shellcheck disable=SC2046 # member names hold no space
    set -- $(cost_members "$c_dir")
    [ $# -gt 0 ] || return 0
    echo
    echo "== cost"
    cost_sum board "$c_dir" "$@" | while IFS= read -r c_line; do
        c_who=$(printf '%s\n' "$c_line" | awk '{ print $1 }')
        c_budget=$(crewfile_get "$c_dir" "$c_who" budget)
        if [ -n "$c_budget" ]; then
            c_spent=$(printf '%s\n' "$c_line" | awk '$3 == "tokens" && $4 ~ /^\$/ { print substr($4, 2) }')
            c_line="$c_line  $(cost_against "${c_spent:-}" "$c_budget")"
        fi
        printf '%s\n' "$c_line"
    done
}

# The dollars <name> of the crew <dir> has spent, as 12.40, or nothing
# when the rates price none of its models.
cost_spent() {
    cost_sum board "$1" "$2" | awk '$3 == "tokens" && $4 ~ /^\$/ { print substr($4, 2); exit }' || :
}

# <spent> against <budget>, both in dollars: "of a $60 budget, 21%", or
# what stands in for a member crew cannot price.
cost_against() {
    if [ -z "$1" ]; then
        echo "a \$$2 budget, but no rate to price it"
        return
    fi
    awk -v s="$1" -v b="$2" 'BEGIN { printf "of a $%s budget, %d%%\n", b, (b > 0 ? s * 100 / b : 100) }'
}
