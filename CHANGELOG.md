# Changelog

What each version of crew adds, newest first. A version is a tag on the
repository, `v1.0.0`, which `crew version` prints; the issues are in the
milestone of the version, on GitHub.

## Unreleased

- The protocol adds three subjects, each sent to the coordinator, or to
  `owner` in a crew with none. `Design:` comes before a change to a
  command's behavior, the gate, or the protocol, with its forks marked.
  `Paused:` says a task stops before it is done, and where its work is.
  `Idle:` says nothing is left; the coordinator answers it in the same
  turn. Before every `Pushed:`, `Done:`, or `Paused:`, a member rewrites
  `Next:` so a fresh session after a `/clear` can resume from it. Saved
  work lives under the crew's directory, in `reports/<you>.patch` and
  `work/<you>/`, never only under `/tmp`. A member with a pane never waits
  inside its turn (`crew unread --wait`, a sleep loop over CI): it ends the
  turn at the prompt, where a wake brings it back and `crew clear` can act.
- `crew land --check` runs the check on what the commit will hold, not in
  the working tree, where a teammate's unfinished files made it fail or
  pass: in the member's export, `exports/<member>/tree` under the crew's
  directory, `HEAD` with the member's paths laid over it, new, changed, and
  deleted. The export is reused through a private index, so only the files
  that changed are written again and a build cache in it stays valid. The
  check gets `CREW_MEMBER`, `CREW_DIR`, and `GIT_CEILING_DIRECTORIES`, so a
  `git` it runs never reaches the shared tree. When `HEAD` moved between the
  check and the lock, the check runs again under the lock, and a failure
  commits nothing. A clone checks in its export too, and after a rebase on
  an export of the rebased commit.
- `crew land` lands a tracked file turned into a directory, given as `d`,
  `d/`, or `d/x`: `git commit -- d` took the directory for a submodule and
  stopped with "'d' does not have a commit checked out". The export never
  reads, writes, or removes through a link, where a link of `HEAD`'s to a
  directory outside, turned into a directory or back, had it write or
  remove a file outside the export.
- `crew reset` puts the whole crew aside under `archive/<date and time>/`:
  the session, and the plan, the Crewfile, the tabs, the layouts, the mutes,
  and the members. It leaves `.crew/` as `crew init` makes it, keeping the
  project's and the machine's files (`project`, `rates`, `forbid`, `kinds`,
  `tmp/`, `exports/`, a clone still on disk), so a new crew no longer
  starts on the last one's plan, tab orders, and mutes. `crew restore
  [<archive>]` brings either kind of archive back, the latest by default,
  and refuses a crew with a session or a plan of its own; it never puts a
  pane back, and `crew up` brings the members back. `crew story <archive>`
  reads the plan, the Crewfile, and the members a reset put aside.
- `crew archive` carries the members' `work/` with the session.
- A Crewfile places the coordinator's pane, the watch, and the board
  anywhere in its first tab: `pane coordinator`, `pane watch`, or
  `pane board` among the member lines puts that pane at its place in the
  tab's order, so `layout=2x2` gives a grid around the coordinator, and
  `crew up` puts the coordinator's pane back in its place after a
  `crew restore`. With no `pane` line the order is as before: the
  coordinator, the watch, the board, then the members. `crew up --dry`
  prints the first tab's order.
- `crew clear <name>` and `crew compact <name> [instructions]` clear or
  compact a member's conversation, only at its idle prompt, never in the
  pane they run in, with the member's wakes held while they type and the
  newest held one sent after. A clear also refuses a background shell and a
  claimed file changed after the member's status; it types `/clear`
  (Codex: `/new`), waits for the cleared screen, then types the line that
  has the member rejoin and resume from its `Next:`, and checks that it was
  taken. A compact waits for the compacted mark; only Claude Code takes
  instructions. `lib/screen.sh` reads what each kind's screen says, from 25
  screens newly captured from Claude Code 2.1.318, Codex 0.166.0, and
  Antigravity 1.4.12, a tmux screen's styles telling dim placeholders and
  suggestions from typed text. Claude Code 2.1.318 no longer says esc
  interrupts its turn: its spinner's timer marks it.
- `crew up --restart <name>...` restarts live agents on their Crewfile
  lines, each in its own pane, at its idle prompt only: the kind's quit
  command (`/exit`, `/quit`), the shell waited for, then the line with the
  kind's resume argument, so a new model or option takes over the same
  conversation; `--fresh` starts a new one. Wakes are held meanwhile. An
  agent in a turn, with typed text, a dialog, or a background shell is
  refused. `crew up` records each member's line in `lines/<name>` and names
  a live member whose Crewfile line changed since it started.
- Idle members. `crew board` says what each member's pane shows after its
  pane, `idle, nothing to do for 7 min` for a member idle at its prompt
  with nothing unread, no commit waiting for its review, and an `Idle:` as
  its last message or none, and `idle (muted)` for a muted one, idle by
  design. It waits two seconds once for all members, not once each.
  `crew board --live` shows the same words, `dialog` in place of `prompt`
  and `free` for a member with nothing to do; it now sees Claude Code
  2.1.318's turn, which no longer says esc interrupts it.
- `crew watch` tells of a member with nothing to do after 5 minutes, once a
  stretch, where it was off unless `CREW_IDLE_MINUTES` was set and counted
  a member that had not sent `Done:`. The check is on by default now:
  `CREW_IDLE_MINUTES=<n>` changes the minutes, and `CREW_IDLE_MINUTES=0`
  turns it off. A muted member and one that sent `Done:` are never told.
  `--to <name>` sends that member, the coordinator, a `Heads-up:` in the
  stream instead of a notification to the owner; `crew up` does not pass
  it yet, so a crew up's watch notifies the owner.

## 1.1.0

- `crew <command> --help` prints that command's entry of the usage and
  runs nothing. `crew init --help` made a crew where it stood, and
  `crew archive --help` archived the stream. `init` refuses any word but
  `--home`, and `dir`, `panes`, `relay`, `archive`, and `version`, which
  take none, refuse one.
- The usage says what `crew init --home` names the directory:
  `~/.crew/-home-me-app` for `/home/me/app`, the root's path, so two
  projects of one name keep two crews.
- `crew invite`, and so `crew spawn --join` and `crew up`, answer the
  agent's trust dialog when the folder the agent runs in is the crew's
  project or the member's clone, and say so; for any other folder they
  print the dialog for `crew key`, as before. Claude Code 2.1.317 puts its
  cursor on "No, exit": invite moves it to "Yes, I trust this folder" first.
- crew ships the prices of Anthropic's models, in `share/rates`: `crew cost`
  and the board price a Claude Code member with no rates written. The
  owner's and the crew's rates replace a line or add one.
- The protocol asks for each thing once, to the fewest who must act on it:
  no `Heads-up:` that copies a `Done:`, no copy to each member, no message
  that only agrees. At the end, `Done:` goes to `owner`, which wakes no
  member, instead of `all`, which woke every one for each `Done:`.

## 1.0.2

- Every call to iTerm2 waits 5 seconds at most for each answer, not only
  the listing of 1.0.1: a read, a key, a spawn, a focus, a close, a color,
  and a move. A read that timed out is not tried again. An iTerm2 that did
  not answer held the gate for up to four minutes a member, each round.
- A round over the crew lists each terminal once, not once or twice a
  member: the gate's round, the board and the live board, `crew doctor`,
  `crew down`'s wait and what it says is left, a wake of all, the relay's
  retries, and a layout. Four iTerm2 panes, looked at for their tty and
  whether they are gone, took 2.2 seconds and take 0.3.
- Taking an iTerm2 pane's color off (`crew leave`, or a kind with no
  color) puts its background back. It tinted it an eighth toward black
  instead: the empty color reached AppleScript as 0.

## 1.0.1

- Inside tmux, crew no longer asks iTerm2 for its sessions. Every command
  that listed panes (`join`, `panes`, `board`, `invite`, a pane's tty, a
  gone pane) asked it through AppleScript, and an iTerm2 that did not
  answer, with tmux running in its window, held each one for AppleScript's
  two-minute timeout. Outside tmux, the listing gives up after 5 seconds and
  says so.

## 1.0.0

The first release: crew in the open, under the MIT license, with a site.
Before it, crew ran the owner's crews from a checkout without a tag; this
milestone adds what a stranger needs to install it, trust it, and run a
session with nobody at the keyboard.

### Install and documentation

- A license, this changelog, `CONTRIBUTING.md`, `SECURITY.md` (which names
  what crew sends over the network), and a version read from the tag (#29).
- An install in one line from a GitHub release (checked against
  `SHA256SUMS`), a release made by a pushed tag, and `crew update` (#32).
- A portable install, a five-minute quickstart, and a table of contents in
  the README (#53).
- The site on GitHub Pages (#56), with a design pass so that nothing is cut
  off at any width (#58).
- A real session on the site, from `crew story` (#55).
- The README prices a Claude Code member by its model's rate.

### Starting a crew

- Three presets, `solo`, `pair`, and `ring` (one whose agent is not installed
  is refused), a plan to start from, and a board that says what to run first
  (#52).
- `crew doctor` checks the Crewfile and a budget with no rates (#54).

### Members and panes

- A member with no pane: `crew join --no-pane` and `crew unread --wait`
  (#30).
- An exited agent brought back in its own pane, and in its own
  conversation (#46).
- Only an agent is woken: a wake line is never typed into a shell or
  another program (#38).
- A poke is typed as one line: no carriage return or control byte gets
  through (#35).
- A clone's crew is found when `CREW_DIR` does not reach the agent's
  commands (#36).
- The focus stays where it was when a pane is opened or moved, an iTerm2
  session crew never tinted is tinted, and a spawn labels its own pane after
  a layout.

### The stream and the board

- `crew story`: the session as one document, and `crew down --archive` saves
  it as `story.md` (#31).
- Status one-liners, `crew status <name> "Field: value"`, and reading a
  status (#47).
- The stream filtered: `crew log --from`, `--to`, `--grep`, `--oneline`,
  and `crew unread --peek` (#48).
- A review queue: each `Pushed:` until its `Review:`, on the board and in
  `crew down` (#49).
- The board counts each member's unread messages and lists its clone's
  unclaimed files (#50); the live board marks unread messages with `+`.
- `crew send --message` (`-m`) and `--file` (`-F`), and a warning for a
  recipient crew does not know (#51).
- Two archives made in the same second kept apart.
- Statuses, reports, and cursors written atomically (#43).

### Landing

- Landing from a clone over a moved origin, and `crew sync` (#40).
- Literal paths only, and directories by the files under them (#41).
- `Pushed:` recorded in the member's status when `crew land` pushes (#44).
- A clone's stashes kept, and an empty landing stopped before the check
  (#45).

### The gate

- git commands behind global options and wrappers are held (#42).
- A crew's own `forbid` is read at each prompt, and the gate holds when no
  rules can be read.

### Tests

- Test child processes kept away from real terminals (#33), and the tests
  kept out of the crew and the pane they run from.
- A test area counted passed only when it ends with its own passing
  summary, and the captured screens checked against `VERSIONS` both ways
  (#34).
- A zero interval refused, and counts read as decimal (#37).
- ShellCheck is told where `count_n` comes from, and clean.
- An end-to-end test in a private tmux server, with fake agents (#39).
