# Security

## What the gate is

`crew gate` and `crew watch` read the panes of the members they are given
every two seconds and answer the command prompts they recognise: Codex's
"Would you like to run the following command?" and Claude Code's "Bash
command ... Do you want to proceed?". A command that matches a rule of
`share/forbid`, or of the project's own `.crew/forbid`, is held for the
coordinator, and so is every other menu at the bottom of a pane (a file
edit, a fetch, a trust dialog). Right before it presses, the gate reads
the pane again and presses only for the same prompt.

## What the gate is not

- It is not a sandbox. An approved command runs with the agent's rights:
  your account, your files, your network. The gate decides only whether
  the key is pressed.
- It reads a screen. The rules are tried against the command as the
  prompt shows it: a command the agent wraps, aliases, or hides in a
  script runs as what it is, not as what the rule reads. `share/forbid`
  is a list of what the owner would stop, not a proof that nothing else
  can harm.
- It holds only what asks. An agent that asks for nothing is never held:
  Antigravity with `toolPermission: always-proceed`, Claude Code with
  permissions skipped, Codex with full access. Such an agent is bound by
  the protocol alone.
- `crew poke`, `crew key`, and a wake line type into a pane with your
  rights; the gate presses only the approve key of the member's kind.

Run the gate where you see each line it prints, and keep the agents'
own permission settings as tight as the work allows: the gate adds a
hold, it takes nothing away.

## What crew reads and writes

crew keeps its state in the crew's directory, `.crew/` at the project's
root or `~/.crew/<project>/`, which `crew init` keeps out of commits
through `.git/info/exclude`. The stream, the statuses, and the reports
in it are what the agents wrote: read them as such. `crew cost` reads
the agents' own logs on this machine and sends nothing. What goes over
the network is git and `gh`: a member's clone is made from the local
checkout, then fetched from and landed through the project's own
`origin`, as is the shared tree by `crew land`; and `crew board` asks
GitHub for CI through `gh` when it is installed, which `crew doctor`
checks with `gh auth status`. Nothing else leaves this machine.

## Reporting a vulnerability

Report it privately through GitHub's vulnerability reporting for the
repository (the Security tab, "Report a vulnerability"), not in an
issue. Say what you ran, what crew did, and what you expected; a screen
from `crew peek <name> 40` helps when the gate is involved. You get an
answer within a week.
