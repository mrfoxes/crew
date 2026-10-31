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

Tab completes the commands, their flags, the members, the keys, the message
numbers, and the kinds, in the shell you use:

```
ln -s ~/Documents/repos/github.com/mrfoxes/crew/share/completions/crew.fish ~/.config/fish/completions/crew.fish   # fish
fpath=(~/Documents/repos/github.com/mrfoxes/crew/share/completions $fpath); autoload -Uz compinit; compinit      # zsh, in ~/.zshrc
source ~/Documents/repos/github.com/mrfoxes/crew/share/completions/crew.bash                                       # bash, in ~/.bashrc
```

They read the commands and flags from `crew --help` when Tab is pressed, so a
new command completes with no edit to them, and the members from the crew
that `crew dir` finds.

## A session

Before the first spawn, `crew doctor` checks what a crew needs under it and
changes nothing:

```
crew doctor                                 # ok, warn, or fail a line, and what to do
```

It reads iTerm2's version from its app bundle (3.5 or later for `--above`
and `crew move`; it does not launch it) and whether it runs, tmux's (3.1 or
later to even a row); either terminal alone is enough, neither is a fail.
It checks `crew` on `PATH` and the checkout it resolves to, each kind's
agent on `PATH` with its `--version` against the one its fixtures were
captured from (`test/fixtures/VERSIONS`; a newer agent may draw prompts the
gate no longer reads), the caveman skill of each installed agent, a
notifier for `owner`, `gh auth status` for the board's CI, and, inside a
crew, a lock held for 10 minutes or more, whether a relay runs, and members
whose pane is gone. A fail makes the exit status 1; a warn does not.

In the project, from the coordinator's pane:

```
crew init                                   # .crew/ at the root, kept out of git
crew init --home                            # or under ~/.crew, tree untouched
$EDITOR "$(crew dir)/README.md"             # the plan, lanes, reviewers, end time
crew spawn claude claude                    # a pane beside this one, running claude
crew spawn codex codex
crew spawn agy --tab runtime agy            # in the tab runtime, opened for its first member
crew spawn agy --below codex agy            # under codex's pane: a column beside yours
crew spawn agy --above codex agy            # over it
crew spawn agy --beside codex agy           # right of it, in its row
crew spawn codex --above iterm:<id> codex   # over a pane from crew panes: yours, say
crew spawn claude claude --model 'x y'      # several words: each kept whole
crew spawn codex 'cd sub && codex'          # one word: a line for your shell
crew spawn mine --kind claude ./my-claude   # a kind its command does not show
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
crew board                  # statuses with their age and pane (gone, if closed), files claimed twice or by nobody, lock, messages, git, CI, cost
crew log 3                  # the last 3 messages, whole
crew show 12                # message 0012
crew focus codex            # codex's pane to the front, its tab and its window
crew focus codex --zoom     # alone in its tab, until the next focus (tmux)
crew focus -                # back to the pane the last focus was run from
crew peek codex 20          # the last 20 lines of codex's pane
crew poke codex "<line>"    # type a line and press Return
crew key codex esc          # press keys: y, enter, esc, tab, up, ctrl-c, alt-m, ...
crew watch codex claude     # answer their prompts and wake recipients, from this pane
crew gate codex claude      # the first half of watch: answer prompts, hold the forbidden
crew relay                  # the other half: wake recipients for every sender
```

When the crew shares one tree, `crew status` warns, on stderr, of each path on
the `Files:` line that another member's status lists (with who, and how many
minutes ago) and writes the status anyway; a path ending in `/` claims every
path under it. The board adds `== conflicts`, each path two members claim, and
`== unclaimed`, each file changed in the tree that nobody claims, each only
when it has a line.

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
than the shell runs there and the agent is ready, then types the join
line; `crew invite codex` does the same for a pane spawned without it, and
prints the prompt (a trust dialog) it finds waiting instead, for `crew key`.
Ready is the kind's input line (`idle` in `share/kinds`) drawn on two reads
in a row, or two reads alike: an idle Claude Code redraws its hint and its
notices every few seconds. Giving up, invite says which never came: an
agent in the pane, or a screen ready for a line.

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

## What it costs

`crew cost` counts what the members spent, from the logs their agents keep on
this machine (nothing goes over the network, and no pane is touched): a line
a member, then a total, with the tokens in five columns and the dollars where
the rates price the model:

```
crew cost                   # every member with a pane, thread, session, or kind
crew cost codex agy         # those members only
```

```
codex    input 36031  cached 118315581  write 1647717  output 261595  reasoning 181012  $72.62
agy      input 2730598  cached 28680398  write 0  output 300718  reasoning 159598  no rate for gemini-4-argon
total    input 2766629  cached 146995979  write 1647717  output 562313  reasoning 340610  $72.62
```

Each kind keeps its usage in its own place: Codex in
`~/.codex/sessions/YYYY/MM/DD/rollout-*-<thread>.jsonl`, the thread `crew
join` recorded in `threads/<name>` (the last cumulative total of its
`token_count` events; its input counts the cached and written tokens and its
output the reasoning, so each is taken out of the number it sits in);
Antigravity in `~/.gemini/antigravity-cli/conversations/<id>.db`, the newest
conversation that began with `crew join <name>` (it needs `sqlite3`; without
it the line says so, and the others go on); Claude Code in
`~/.claude/projects/*/<session>.jsonl`, the session `crew join` recorded in
`sessions/<name>` (`CLAUDE_CODE_SESSION_ID`), each message once, its
thinking counted as reasoning. A Claude Code member has tokens only: it runs
on a subscription. A member who joined before crew recorded a session shows
that, not a number. `CREW_CODEX_HOME`, `CREW_AGY_HOME`, and
`CREW_CLAUDE_HOME` move the three roots.

crew ships no prices. `rates` in the crew's directory, then
`${XDG_CONFIG_HOME:-~/.config}/crew/rates` (the owner's, for every project),
list the models, a line each, in dollars per million tokens; a line in the
crew's replaces the owner's for that model, and `-` is no price:

```
# model            input  cached  write  output  reasoning
gpt-6-astra          5.00    0.50      -   30.00      30.00
claude-opus-5-5     15.00    1.50  18.75   75.00      75.00
```

A model with no line shows its tokens and `no rate for <model>`. The last
section of `crew board`, `== cost`, shows each member's total and, where the
log has times (Codex and Claude Code), the last hour's.

## One command, the whole crew

A crew described once in its `Crewfile`, in the crew's directory, comes
up with `crew up`, from the coordinator's pane: one line for each tab and
each member, in the order they are placed.

```
# Crewfile: tabs and members, in the order crew up places them.
tab main layout=main watch board
tab proof layout=table
member claude   reviewer=claude2 -- claude --model claude-opus-5-5 --effort high
member claude2  reviewer=claude clone cache=.lake -- claude --model claude-opus-5-5
tab runtime layout=grid
member agy      reviewer=codex mute budget=20 -- agy
member codex    reviewer=agy mute budget=60 -- codex
member tess                              # started and joined by hand
```

- `tab <name> [layout=<layout>] [watch] [board]`: the first tab is the
  one `crew up` runs in, the coordinator's, named `<name>`; `watch` opens
  a pane beside the coordinator running `crew watch --all`, which gates
  every member with a pane, those spawned later too, and `board` one
  running `crew board --live`. Every next tab opens for its first member.
  `layout=` is one of `crew layout`'s: `table`, `grid` (the default),
  `<columns>x<rows>`, or `main`.
- `member <name> [option]... [-- <line>]` belongs to the last tab above
  it. After ` -- ` the line is the owner's shell's, verbatim, `#` and
  `&&` included, run in the project's root or the member's clone. A member
  with no line is started and joined by hand: crew up never spawns it.
- Options: `kind=<kind>` (else read from the line), `mute`, `noinvite`
  (a member is invited by default), `clone` and `cache=<dir>`, the latter
  repeatable, `reviewer=<member>` (crew land), `budget=<dollars>`.
- A `#` word starts a comment before ` -- `. An unknown word, an option on
  the wrong line, a name crew does not take, a member twice, a reviewer
  who is not a member, or a cache with no clone stops `crew up` before it
  does anything, naming the file and the line.

```
crew up                     # the crew of the Crewfile, up or back
crew up --dry               # what it would do, touching nothing
crew up lean                # start the Crewfile from the preset lean
```

`crew up` makes the crew's directory when there is none, then, tab by
tab, spawns each member without a live pane in its tab, names and colors
it, gives it its clone, mutes it, lays the tab out by its layout, and
invites every member spawned, all at once. Run again, it brings back only
what is missing: a closed pane returns in its place, a live agent is never
restarted, and a member with a pane the Crewfile does not list is named
and left alone. A preset is a Crewfile in `~/.config/crew/presets/<name>`
(under `$XDG_CONFIG_HOME`): `crew up <preset>` copies it to a crew that
has no Crewfile, and refuses one that has its own, which is the truth.

## Kinds of agent

What crew knows of each agent is one line of `share/kinds`: the name ps
shows for its process, the variable it sets for the commands it runs, the
mark that starts its input line, the key that approves its command
prompts, and its panes' color.

```
# kind    process  env              idle  approve  color
claude    claude   CLAUDECODE       ❯     enter    #d97757
codex     codex    CODEX_THREAD_ID  ›     y        #10a37f
agy       agy      -                >     -        #4285f4
```

`crew spawn` records a member's kind in `kind/<name>`, from `--kind` or
from the first word of its command that names a kind's process (`cd sub
&& codex` is codex); `crew join` records the kind of the agent it runs
under, its nearest ancestor process, or, where a sandbox hides ps, the
first kind whose variable is set, and keeps the spawned one when neither
tells. A member of no kind is `other`. `crew panes` and `crew board` show
each member's kind. `~/.config/crew/kinds` (under `$XDG_CONFIG_HOME`),
then a crew's own `kinds`, add kinds or replace these, a line for a kind
replacing the one before it: a wrapper script that runs Claude Code is one
line, `mycc mycc - ❯ enter #d97757`.

## Names and colors

Every pane `crew spawn` opens, or a member joins, shows the member's name
where its agent's titles cannot reach it, marked with its kind's color:

- tmux keeps both in the pane's own options (`@crew_name`, `@crew_color`)
  and shows them in the status line of its border, which crew turns on for
  the pane's window: `claude2 · ✳ Claude Code`, the name in the kind's
  color, then the title the agent sets. `tmux set -w pane-border-status
  off` hides it again.
- iTerm2 shows the name as the session's badge, set by the escape sequence
  iTerm2 reads from its output, written to the session's tty (iTerm2's
  AppleScript can set neither a tab's title nor a name an agent keeps),
  and tints the session's background an eighth of the way toward the
  kind's color, from the background it had, which the session keeps in
  `user.crew_background`.

`CREW_COLOR=0` names the pane without a color. `crew leave` takes both off
a pane still open.

## A clone for a member

`crew spawn <name> --clone <cmd>...` gives a member a checkout of its own,
`../<project dir name>-<name>`, instead of the project's: its builds,
index, and commits touch nobody else's, and it lands through `origin`.
`<cmd>` runs there with `CREW_DIR` set to the crew's directory, so the
member joins the same crew.

```
crew spawn lean --clone --cache .lake claude    # ../proj-lean, with the project's .lake copied
crew board                                      # under lean: clone: ../proj-lean, 2 behind origin/main
crew leave lean --clone                         # removes it when nothing is left
```

- The clone is made from the local checkout (no network for the objects),
  then `origin` is set to the project's own URL, `git fetch origin` runs,
  and `main` is checked out at `origin/main`: the member works on `main`.
  When origin has no `main`, the project's current branch stands in for it,
  and spawn says so.
- The project's own `user.*` settings (name, email, signing key) are copied
  into the clone: a plain `git clone` does not carry them, and the commits
  would go out under your global identity.
- Each `--cache <dir>` (a path from the project's root, such as `.lake` or
  `node_modules`) is copied into the clone, at the same place, when the
  project has it and the clone has not; spawn says what it copied.
- A clone there already is reused after `git fetch` and a fast-forward of
  its main, when its tree is clean. With changes, or of another origin, it
  is left as it is, and spawn says so and stops.
- `crew board` adds a line under the member: the clone, how many commits it
  is behind `origin/main` as last fetched (the board never fetches), and
  `IDENTITY` with both emails when the clone's `user.email` is not the
  project's.
- `crew leave <name> --clone` lists what the clone holds that origin does
  not (commits, changed and untracked files), and removes it only when
  there is nothing; otherwise it stays. `crew leave <name>` alone keeps the
  clone and `clones/<name>`, so the board still shows it.
- The gate holds `git pull` and `git rebase` for every member, a clone's
  too: the protocol has the member ask the coordinator, who answers with
  `crew key`. A project that wants them free has its own `.crew/forbid`.

## Tabs

`crew spawn <name> --tab <tab>` puts a member in the tab named `<tab>`:
the first member opens it, and each next one is placed beside the last
member still there, so a lane's members share a tab and the coordinator's
stays small. A member spawned next to another (`--beside`, `--below`,
`--above`) sits in that member's tab. `tabs/<tab>` lists a tab's members
in the order they were placed; `crew leave` takes a member out, and a tab
left empty is forgotten.

```
crew spawn claude --tab proof claude        # opens the tab proof
crew spawn claude2 --tab proof claude       # beside claude, in proof
crew spawn agy --tab runtime agy            # opens the tab runtime
crew spawn codex --tab runtime codex        # beside agy
```

tmux names the window after the tab and keeps the name (`automatic-rename`
and `allow-rename` off). iTerm2's AppleScript sets no tab title an agent's
titles would not overwrite, so there the tab's name is in each member's
badge, after the member's: `claude2 · proof`. `crew panes` lists a tab's
members together, in their order, and `crew board` names each member's
tab. Peek, poke, keys, the gate, and the relay reach a pane by its id,
whatever tab it is in, and `crew focus <name>` takes you there: tmux
switches to its session, window, and pane, and iTerm2 selects its window,
tab, and session. `--zoom` shows it alone in its tab until the next focus
in tmux (`resize-pane -Z`); iTerm2's AppleScript cannot, and says to use
View > Maximize Active Pane.

## Laying out a table

`crew layout <layout> --tab <tab>` moves the panes of a tab into rows, their
agents running on, and keeps the layout for the tab in `layouts/<tab>`:

```
crew layout table --tab proof               # a row for each kind
crew layout grid --tab proof                # as square as the count allows: 5 is 3 over 2
crew layout 3x2 --tab proof                 # rows of 3, in the tab's order
crew layout main --tab main                 # the first pane whole on the left, the others one over another
crew layout claude,claude2,claude3 / agy,agy2   # these rows, in the first one's tab
crew layout                                 # every tab again, by the layout it has
```

A table's rows come in the order the kinds first sit in the tab, a row's
panes in the tab's order. A closed pane leaves no hole: `crew layout` alone
lays every tab out again with the panes still there, and a member spawned
in a tab with a layout is placed in its row at once. A pane in its place
already is left there; a move the terminal refuses is said, and the layout
goes on with the next ones.

By hand, the same is spawns and moves in order. `--beside` and `--below`
split one pane, not a whole row, so open the first pane of every row down
the left, then fill each row rightward, as `crew layout` does:

```
crew spawn claude --tab proof claude        # the table, in a tab of its own
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
Claude Code's "Bash command ... Do you want to proceed?", and answers each
with its kind's `approve` key (a kind with none has its prompts held). A command that
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

You are often in another tab or app, so `crew watch` and `crew gate` also
send you a desktop notification (macOS or `notify-send`) when something
needs you, once for each event, never again while it lasts, and again only
once it has ended and come back. Each says what to run:

- a held prompt, with the member and the command: `crew focus <name>` to
  look, `crew key <name> <key>...` to answer;
- a member's agent that exited, its pane back to a shell where an agent ran
  before: `crew spawn ...` or `crew up` to bring it back;
- a member's pane that is gone: `crew leave <name>`, or bring it back the
  same way;
- off by default, a member idle for `CREW_IDLE_MINUTES=<n>` minutes: its
  agent's input line drawn, its screen unchanged for that long, and no
  message from it whose subject starts with `Done:`.

Each event also prints a line in the watch's pane, with the time.
`CREW_NOTIFY=0` turns the notifications off and never the lines. Where
there is no notifier the pane says so once.

## Where things live

```
bin/crew            the command
lib/store.sh        .crew/, the numbered stream, unread cursors, the push lock, the board
lib/kinds.sh        kinds of agent: share/kinds read and overridden, a member's kind told
lib/claims.sh       the Files: lines: the warning of a path claimed twice, the board's conflicts and unclaimed
lib/term.sh         the terminal contract, and what both keep alike: find our own, keys
lib/term-iterm.sh   iTerm2's half of it, through osascript: list, read, type, spawn, move
lib/term-tmux.sh    tmux's half of it
lib/layout.sh       placing panes: spawn beside, under, over; move; tabs; layouts
lib/crewfile.sh     the Crewfile read, checked, and asked
lib/up.sh           crew up: the crew of the Crewfile brought up, or back
lib/clones.sh       a member's clone: made, reused, shown on the board, removed
lib/panes.sh        members and their panes: join, mute, peek, poke, key, spawn, move, waking
lib/gate.sh         reading approval prompts, the rules, the gate's loop, what it tells the owner
lib/doctor.sh       crew doctor: the checks of what a crew needs, read only
lib/cost.sh         crew cost: what the members spent, from the agents' logs and the rates
share/protocol.md   what agents follow, printed by crew help and crew join
share/forbid        the gate's default rules
share/kinds         the kinds of agent crew knows
share/completions/  Tab completion: crew.fish (fish), _crew (zsh), crew.bash (bash)
test/               sh test/run.sh, an area a file (<area>_test.sh), with screens captured from real prompts
test/fixtures/VERSIONS  the agent and version each screen was captured from
.github/workflows/  the tests on Ubuntu and macOS, at every push
```

In a project, `.crew/` at its root, or `~/.crew/<project>/` after `crew init
--home` (the path with every character but a letter or digit as `-`, the way
Claude Code names its project directories); `crew dir` prints it, and
`CREW_DIR` names another one for one command:

```
README.md                  the plan for this session (optional)
Crewfile                   the crew's tabs and members, for crew up (optional)
up/watch, up/board         the panes crew up opened for the watch and the board
messages/NNNN-a-to-b-*.md  the stream
status/<name>.md           what each member is doing now (crew status)
panes/<name>               each member's pane
threads/<name>             a Codex member's thread, for codex queue
sessions/<name>            a Claude Code member's session, for crew cost
rates                      the project's prices per model, over the owner's (optional)
muted/<name>               a member woken only by messages to its name (crew mute)
kind/<name>                each member's kind (claude, codex, agy, other)
clones/<name>              the path of a member's clone (crew spawn --clone)
tabs/<tab>                 a tab's members, in the order they were placed
layouts/<tab>              the layout a tab is kept in (crew layout)
reports/<name>.md          each member's report at the end (crew report)
archive/<date and time>/   earlier sessions (crew archive)
forbid                     the project's gate rules (optional)
kinds                      the project's kinds of agent, added to share/kinds (optional)
project                    the project's path
relay.pid, relay.last      the relay's heartbeat and last number, while one runs
```

A linked worktree shares its project's crew, so the crew works the same in
one checkout or in several.
