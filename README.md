# crew

Coding agents working side by side, in panes you can see.

`crew` runs a session of several coding agents (Claude Code, Codex,
Antigravity, or any other terminal agent) on one project, each in its own
iTerm2 or tmux pane. Nothing runs hidden: every agent is a normal interactive
session you can watch and type into. The agents talk through one numbered
stream of Markdown messages in the project's `.crew/` directory, which you
read as the story of the session, and a coordinator (you, or an agent you
pick) can read each pane, type into it, and answer its approval prompts.

It is a few POSIX shell scripts, `osascript` for iTerm2, and `tmux`: no
daemon, no service, no extension.

## Install

```
ln -s ~/Documents/repos/github.com/mrfoxes/crew/bin/crew ~/.local/bin/crew
```

## A session

In the project, from the coordinator's pane:

```
crew init                                   # .crew/ at the root, kept out of git
crew init --home                            # or under ~/.crew, tree untouched
$EDITOR "$(crew dir)/README.md"             # the plan, lanes, reviewers, end time
crew spawn claude claude                    # a pane beside this one, running claude
crew spawn codex codex
crew spawn agy --tab agy                    # a new tab instead of a split
crew spawn agy --below codex agy            # under codex's pane: a column beside yours
crew spawn agy --above codex agy            # over it
crew spawn agy --beside codex agy           # right of it, in its row
crew spawn codex --above iterm:<id> codex   # over a pane from crew panes: yours, say
crew spawn claude claude --model 'x y'      # several words: each kept whole
crew spawn codex 'cd sub && codex'          # one word: a line for your shell
```

tmux opens a pane over another directly; iTerm2's AppleScript splits only
downwards, so `--above` splits under the pane and moves the new one over it
with iTerm2's own `move_session` function, through AppleScript's `invoke API
expression`: iTerm2 3.5 or later, with no Python API to enable.

Then tell each agent to join, with `--join` on the spawn, with `crew invite`
once it is up, or by typing in its pane:

```
crew invite codex
crew poke codex 'Run: crew join codex. Then follow the protocol it prints. Work in caveman mode ($caveman) from now on.'
```

`crew join <name>` prints the protocol (`share/protocol.md`), the plan, and
the messages waiting; an agent needs no instruction file to learn any of it.
An agent you started by hand joins the same way: `join` finds its pane from
`$TMUX_PANE`, `$ITERM_SESSION_ID`, or, when a sandbox drops those, the tty of
its nearest ancestor.

Every member works in caveman mode, terse with every technical fact kept:
output tokens are billed, and each turn's output grows the context the next
calls pay for. The invite line asks for it with `$caveman`, which is how a
prompt calls a Codex skill, here `~/.codex/skills/caveman/`; Claude Code has
it on through the caveman plugin's hooks (or `/caveman`), and Antigravity
takes the same skill from `~/.gemini/skills/caveman/`. crew installs none of
them. The protocol asks the same of messages, in whole sentences the owner
reads as a story, with code, paths, hashes, numbers, and errors exact; the
wake line stays the number and the sender.

While they work:

```
crew board                  # statuses with their age and pane (gone, if closed), lock, messages, git, CI
crew log 3                  # the last 3 messages, whole
crew show 12                # message 0012
crew peek codex 20          # the last 20 lines of codex's pane
crew poke codex "<line>"    # type a line and press Return
crew key codex esc          # press keys: y, enter, esc, tab, up, ctrl-c, alt-m, ...
crew watch codex claude     # answer their prompts and wake recipients, from this pane
crew gate codex claude      # the first half of watch: answer prompts, hold the forbidden
crew relay                  # the other half: wake recipients for every sender
```

At the end, `crew archive` puts the stream, the cursors, the statuses, and
the reports under `archive/<date and time>/` and starts the stream over,
keeping the plan, the rules, the panes, and the mutes; `crew leave codex`
forgets a pane you closed; `crew version` says which crew this is.

`crew send codex claude "Review: ..."` posts message `0012-codex-to-claude-review.md`
and types one line into claude's pane: `crew: message 0012 from codex. Run:
crew unread claude`, the number and the sender only: free text in the line
could read as a command to the agent. A message to `owner` becomes a desktop
notification (`osascript` on macOS, `notify-send` on Linux); one to `all`
wakes every member but its sender, and one to a member who has not joined
says so. Set `CREW_WAKE=0` to post without waking anyone. `crew mute codex`
keeps an agent you would rather not wake often in the crew: a message to
`all` no longer wakes it, and says so, while one to `codex` still does; it
reads both with `crew unread`, and `crew board` shows it muted until `crew
unmute codex`.

A line typed while the agent is in a turn is queued, not read as an
interruption, and delivered when the turn ends: Claude Code 2.1.314 shows
`ctrl+enter to send now`, Codex 0.166.0 `Messages to be submitted after next
tool call`, Antigravity 1.4.11 `alt+m to send immediately`; each then runs
`crew unread`. A line typed into a pane before its agent is up goes to the
shell instead: `crew spawn codex --join codex` waits until something other
than the shell runs there and the screen has settled, then types the join
line; `crew invite codex` does the same for a pane spawned without it, and
prints the prompt (a trust dialog) it finds waiting instead, for `crew key`.

A Codex member is woken another way: `crew join` inside Codex 0.166.0 records
its thread (`CODEX_THREAD_ID`), and a message to it is queued with `codex
queue --thread`, which needs no terminal and reaches the session even from
another agent's sandbox; its pane is the way when the thread is gone. Codex
runs the commands of a session through its app-server daemon, whose
environment names the pane the daemon was first started from, not the
session's: `crew join` keeps the pane `crew spawn` recorded over the one the
environment names.

Inside Codex's sandbox crew can reach neither iTerm2 nor `ps`, so a message
Codex sends to a member in a pane wakes nobody by itself. `crew relay`, run
by the coordinator in a pane of their own, wakes the recipients of every new
message from outside; while it runs (`relay.pid`, rewritten every second),
`crew send` posts and leaves the waking to it. Each message is woken once:
the sender and the relay claim it with `tmp/wake.NNNN`, and whoever claims
first wakes.

## Laying out a table

One row for each kind of agent, its panes side by side. `--beside` and
`--below` split one pane, not a whole row, so open the first pane of every
row down the left, then fill each row rightward:

```
crew spawn claude --tab claude              # the table, in a tab of its own
crew spawn agy --below claude agy           # the first of the row under it
crew spawn claude2 --beside claude claude
crew spawn claude3 --beside claude2 claude
crew spawn agy2 --beside agy agy
```

```
+---------+---------+---------+
| claude  | claude2 | claude3 |
+---------+----+----+---------+
| agy          | agy2         |
+--------------+--------------+
```

iTerm2 shares a row out evenly, and so does tmux 3.1 or later, through
`select-layout -E`. A pane already open takes its place with `crew move`,
`--beside`, `--below`, or `--above` another, its agent running on:

```
crew move codex --beside agy2               # codex's pane, right of agy2's
```

The pane keeps its id, so `panes/<name>` stays true. tmux moves it with
`join-pane`. iTerm2 moves it with its own `move_session` (3.5 or later),
whose `before:` means one side in its docs and, over or under, the other in
its code: crew tries the code's value, then the other if the pane landed on
the wrong side. AppleScript shows no pane's position, only the order in
which a tab lists its panes, from the top left, and their sizes, so a move
counts once the tab has changed and the pane comes right after the other
(beside, under) or right before it (over). A pane iTerm2 does not place
there stays where iTerm2 left it, never closed, and the move fails saying
so; the focus stays where it was.

## The gate

`crew gate <name>...` reads their panes every two seconds and answers the
approval prompts it recognises, printing one line for each, with the time:

```
21:45:03 approved codex: cargo test --test editors
21:47:10 HOLD codex (git +reset): git reset --hard
```

It recognises Codex's "Would you like to run the following command?" and
Claude Code's "Bash command ... Do you want to proceed?". A command that
breaks a rule of `share/forbid` (or the project's own `.crew/forbid`, which
replaces it) is held, and so is every other menu waiting at the bottom of
the pane (a file edit, a fetch, a trust dialog): you decide those with `crew
key`. A question the agent asks in prose, with no choices under it, is not a
prompt. Antigravity 1.4.11 with `toolPermission: always-proceed` asks for
nothing but trust, so the gate has nothing to approve for it. Right before
it presses, the gate reads the pane again and presses only for the same
prompt; a screen it has answered is not answered again until the pane
redraws. `crew watch <name>...` is the gate and the relay in one pane. Run
either where you see each line, and keep in mind what a line means: an
approved command runs with the agent's rights.

## Where things live

```
bin/crew            the command
lib/store.sh        .crew/, the numbered stream, unread cursors, the push lock, the board
lib/term.sh         panes in iTerm2 and tmux: list, find our own, read, type, keys
lib/layout.sh       placing panes in iTerm2 and tmux: spawn beside, under, over; move
lib/panes.sh        members and their panes: join, mute, peek, poke, key, spawn, move, waking
lib/gate.sh         reading approval prompts, the rules, the gate's loop
share/protocol.md   what agents follow, printed by crew help and crew join
share/forbid        the gate's default rules
test/               sh test/run.sh, with screens captured from real prompts
.github/workflows/  the tests on Ubuntu and macOS, at every push
```

In a project, `.crew/` at its root, or `~/.crew/<project>/` after `crew init
--home` (the path with every character but a letter or digit as `-`, the way
Claude Code names its project directories); `crew dir` prints it, and
`CREW_DIR` names another one for one command:

```
README.md                  the plan for this session (optional)
messages/NNNN-a-to-b-*.md  the stream
status/<name>.md           what each member is doing now (crew status)
panes/<name>               each member's pane
threads/<name>             a Codex member's thread, for codex queue
muted/<name>               a member woken only by messages to its name (crew mute)
reports/<name>.md          each member's report at the end (crew report)
archive/<date and time>/   earlier sessions (crew archive)
forbid                     the project's gate rules (optional)
project                    the project's path
relay.pid, relay.last      the relay's heartbeat and last number, while one runs
```

A linked worktree shares its project's crew, so the crew works the same in
one checkout or in several.
