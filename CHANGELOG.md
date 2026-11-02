# Changelog

What each version of crew adds, newest first. A version is a tag on the
repository, `v1.0.0`, which `crew version` prints; the issues are in the
milestone of the version, on GitHub.

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
