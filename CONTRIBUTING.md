# Contributing

crew is a few POSIX shell scripts, and stays one. The rules below are the
ones its agents follow too, in `AGENTS.md`; this is the same list for a
human, with the reasons.

## What a change may use

- POSIX `sh`, `awk`, `sed`, and the tools macOS and Linux ship, plus
  `osascript` for iTerm2 and `tmux`. No other dependency, no build step,
  no language runtime: a user installs crew by linking `bin/crew`, and
  that must stay true.
- Everything in the repository is English: code, comments, messages, docs.
- `bin/crew` only dispatches. Each `lib/*.sh` holds one responsibility,
  listed under "Where things live" in `README.md`: a new command goes in
  the file whose responsibility it shares, and in `usage` in `bin/crew`.

## What a change must keep

- Nothing types into a pane without being asked to. Tests read screens
  captured in `test/fixtures/`, never live panes, and open, move, close,
  or type into nothing.
- A change to what agents must do updates `share/protocol.md` in the same
  commit, and `README.md` says what the user sees.
- A change to the gate's rules (`share/forbid`, `gate_forbidden`) updates
  the table in `test/gate_test.sh` too.
- A new prompt format for the gate comes with a fixture captured from the
  real agent, `crew peek <name> 40` into `test/fixtures/<kind>-<what>.txt`,
  and a line in `test/fixtures/VERSIONS` with the agent's version. A
  screen written from memory is not a fixture.

## Before you push

```
sh test/run.sh                      # all tests; sh test/run.sh gate: one area
for f in bin/crew lib/*.sh test/*.sh; do sh -n "$f"; done
shellcheck -s sh -S warning -x bin/crew lib/*.sh test/*.sh
```

CI runs the same three on Ubuntu and macOS at every push. A test file is
an area, `test/<area>_test.sh`, run in a shell of its own by
`test/run.sh`; add checks to the area the change belongs to, and a new
area when none fits.

## Commits

An imperative subject that says what changes, a body that says why and
how it was checked, as `git log` does; `Closes #<n>` on its own line when
the commit closes an issue. One change a commit: a short diff reads and
rebases well.

## Reporting a problem

Open an issue with what you ran, what crew printed, and what you
expected; for a prompt the gate misread, add the screen (`crew peek
<name> 40`) and the agent's version. A vulnerability goes the way
`SECURITY.md` says, not in a public issue.
