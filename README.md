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
$EDITOR .crew/README.md                     # optional: the plan, lanes, reviewers, end time
crew spawn claude claude                    # a pane beside this one, running claude
crew spawn codex codex
crew spawn agy --tab agy                    # a new tab instead of a split
```

Then tell each agent to join, by typing in its pane or with `crew poke`:

```
crew poke codex "Run: crew join codex. Then follow the protocol it prints."
```

`crew join <name>` prints the protocol (`share/protocol.md`), the plan, and
the messages waiting; an agent needs no instruction file to learn any of it.
An agent you started by hand joins the same way: `join` finds its pane from
`$TMUX_PANE`, `$ITERM_SESSION_ID`, or, when a sandbox drops those, the tty of
its nearest ancestor.

While they work:

```
crew board                  # statuses, push lock, latest messages, git, CI
crew peek codex 20          # the last 20 lines of codex's pane
crew poke codex "<line>"    # type a line and press Return
crew key codex esc          # press keys: y, enter, esc, tab, up, ctrl-c, ...
crew gate codex             # answer codex's approval prompts
```

`crew send codex claude "Review: ..."` posts message `0012-codex-to-claude-review.md`
and types one line into claude's pane: `crew: message 0012 from codex to
claude: Review: .... Run: crew unread claude`. A message to `owner` becomes a
desktop notification; one to `all` wakes every member but its sender. Set
`CREW_WAKE=0` to post without waking anyone.

## The gate

`crew gate <name>` reads the pane every two seconds and answers the approval
prompts it recognises, printing one line for each:

```
approved codex: cargo test --test editors
HOLD codex (git +reset): git reset --hard
```

It recognises Codex's "Would you like to run the following command?" and
Claude Code's "Bash command ... Do you want to proceed?". A command that
breaks a rule of `share/forbid` (or the project's own `.crew/forbid`, which
replaces it) is held, and so is every prompt that is not a command; you
decide those with `crew key`. Run it under a watcher that shows you each line,
and keep in mind what it means: an approved command runs with the agent's
rights.

## Where things live

```
bin/crew            the command
lib/store.sh        .crew/, the numbered stream, unread cursors, the push lock, the board
lib/term.sh         panes in iTerm2 and tmux: list, find our own, read, type, keys, spawn
lib/panes.sh        members and their panes: join, peek, poke, key, spawn, waking
lib/gate.sh         reading approval prompts, the rules, the gate's loop
share/protocol.md   what agents follow, printed by crew help and crew join
share/forbid        the gate's default rules
test/               sh test/run.sh, with screens captured from real prompts
```

In a project:

```
.crew/README.md                  the plan for this session (optional)
.crew/messages/NNNN-a-to-b-*.md  the stream
.crew/status/<name>.md           what each member is doing now
.crew/panes/<name>               each member's pane
.crew/reports/<name>.md          each member's report at the end
.crew/forbid                     the project's gate rules (optional)
```

A linked worktree shares its project's `.crew/`, so the crew works the same
in one checkout or in several.
