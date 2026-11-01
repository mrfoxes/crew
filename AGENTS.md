# crew

Coding agents side by side in visible terminal panes, talking through a
numbered message stream. [README.md](README.md) says what it does and where
each piece lives.

## Rules

- Everything in the repository is English: code, comments, messages, docs.
- POSIX `sh`, `awk`, `sed`, and the tools macOS and Linux ship, plus
  `osascript` for iTerm2 and `tmux`: no other dependency, no build step.
- `bin/crew` only dispatches; each `lib/*.sh` holds one responsibility. A new
  command goes in the file whose responsibility it shares, and in `usage`.
- Nothing may type into a pane without being asked to: tests read captured
  screens from `test/fixtures/`, never live panes.
  The one exception is `test/e2e_tmux.sh` (`sh test/run.sh e2e`, never part
  of the rest): it types only into panes it made, in a tmux server of its own
  on a socket under a temporary directory that it kills on exit, out of reach
  of the owner's panes.
- A change to what agents must do updates `share/protocol.md` in the same
  commit; a change to the gate's rules updates `test/gate_test.sh`'s table too.
- A new prompt format for the gate comes with a fixture captured from the real
  agent (`crew peek <name> 40`), not written from memory.

## Commands

```
sh test/run.sh                      # all tests; sh test/run.sh gate: one area
for f in bin/crew lib/*.sh test/*.sh; do sh -n "$f"; done
shellcheck -s sh -S warning -x bin/crew lib/*.sh test/*.sh
```
