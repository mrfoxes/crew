# Changelog

What each version of crew adds, newest first. A version is a tag on the
repository, `v1.0.0`, which `crew version` prints; the issues are in the
milestone of the version, on GitHub.

## 1.0.0

The first release: crew in the open, under the MIT license, with a site.
Before it, crew ran the owner's crews from a checkout without a tag; this
milestone adds what a stranger needs to install it, trust it, and run a
session with nobody at the keyboard.

### Install and documentation

- A license, this changelog, `CONTRIBUTING.md`, `SECURITY.md`, and a
  version read from the tag (#29).
- An install in one line from a GitHub release, and `crew update` (#32).
- An install anyone can copy, and a five-minute quickstart (#53).
- The site on GitHub Pages (#56), with a real session on it, from
  `crew story` (#55).

### Starting a crew

- Built-in presets, a plan to start from, and a board that says what to
  do first (#52).
- `crew doctor` checks the Crewfile, and a budget with no rates (#54).

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

### The stream and the board

- `crew story`: the session as one document (#31).
- Status one-liners, `crew status <name> "Field: value"`, and reading a
  status (#47).
- `Pushed:` recorded in the member's status when `crew land` pushes (#44).
- The stream filtered: `crew log --from`, `--to`, `--grep`, `--oneline`,
  and `crew unread --peek` (#48).
- A review queue: each `Pushed:` until its `Review:`, on the board and in
  `crew down` (#49).
- The board counts each member's unread messages and its clone's
  unclaimed files (#50).
- `crew send -m` and `-F`, and a warning for a name crew does not know
  (#51).
- Statuses, reports, and cursors written atomically (#43).

### Landing

- Landing from a clone over a moved origin, and `crew sync` (#40).
- Literal paths only, and directories by the files under them (#41).
- A clone's stashes kept, and an empty landing stopped before the check
  (#45).

### The gate

- git commands behind global options and wrappers are held (#42).

### Tests

- The test suite kept out of the crew and the panes it runs from (#33).
- A test area counted passed only when it finishes, and fixtures and
  `VERSIONS` kept in step (#34).
- A zero interval refused, and counts read as decimal (#37).
- An end-to-end test in a private tmux server, with fake agents (#39).
