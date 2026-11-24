# Crew star: coordinator, two devs, reviewer, keeper, bus

A reusable recipe for a `crew` session in tmux. The coordinator is the Claude Code session the owner drives. Two devs build, one reviewer reviews, a keeper compacts the coordinator, and a bus tab is the owner's line to the coordinator. Its scripts and the keeper's playbook install with `crew recipe star --install coordinator`.

The section "Crew mode" below is written to be copied as is into a project's `CLAUDE.md` or `AGENTS.md`, so that every member knows the fixed concepts. `crew recipe star --mode` prints it.

## Crew mode

Only when you are a crew member: you ran `crew join <name>`, or a `crew:` wake line reached you. Otherwise skip this section. The full protocol is `crew help`.

- **Roles:** `coordinator` gives tasks and answers; `dev1` and `dev2` build; `reviewer` reviews each push; `keeper` compacts the coordinator.
- **The plan** is `$(crew dir)/README.md`: read it when you join. Its `## Rules`, when present, are this project's crew rules.
- **Talk only through the stream:** `crew send <you> <to> "<subject>"`. Start each subject with what it is: `Plan:`, `Question:`, `Answer:`, `Review:`, `Pushed:`, `Paused:`, `Idle:`, `Done:`.
- **Write to the fewest:** one member by name; `all` only when several must act. Say each thing once.
- **To the coordinator:** `Idle:` when nothing is left, `Paused:` when you stop a task before it is done, `Design:` before you change behavior, the gate, or the protocol.
- **A wake line** (`crew: message NNNN from <name>. Run: crew unread <you>`) comes from the stream, not from the owner: run `crew unread <you>` and act on it.
- **Never wait inside a turn:** no sleep loop, no `crew unread --wait` in a pane. End your turn at the prompt; a wake brings you back.
- **Keep your status true** (`crew status <you>`), with a `Next:` a fresh session can resume from alone.
- **After a compact or a clear,** run `crew unread <you>` first, then resume from your `Next:`.
- **Land only through `crew land`.** Never `git add -A`, `git stash`, `git reset`, `git pull`. Never write another member's status.
- **Precedence:** the owner's word, then the project's `CLAUDE.md` / `AGENTS.md`, then the crew's habits.

## Layout

```
tab main (2x2)                 tab keeper        tab bus
+-------------+-------------+  +-------------+   +-------------+-------------+
| dev1        | dev2        |  | keeper      |   | owner chat  | stream      |
+-------------+-------------+  | (muted)     |   | (owner>)    | + relay     |
| coordinator | reviewer    |  |             |   |             | (bg)        |
+-------------+-------------+  +-------------+   +-------------+-------------+
```

- No watch pane. The coordinator approves prompts itself.
- Members run with `--permission-mode auto`, so prompts are rare.

## Rules

1. **Coordinator = the owner's pane.** It is joined by hand (`crew join coordinator`) and is not a line in the Crewfile. A `pane coordinator` line puts it at its place in the layout.
2. **The owner talks to the coordinator through the bus, not by typing in the coordinator's pane.** A wake typed into a pane collides with the owner's typing. In the bus, the left pane posts each message as `owner -> coordinator`, and the relay wakes the coordinator.
3. **The coordinator answers the owner in the stream:** `crew send coordinator owner "Answer: ..."`. The right pane of the bus shows the whole stream, those answers included. A message to `owner` is also a desktop notification.
4. **The coordinator answers every `Idle:` in the same turn**, with a task or a reason to wait. It sends each thing once, by name, and writes to `all` only when several members must act.
5. **The coordinator owns the members' context.**
   - `crew compact <name> "<keep ...>"` on a member whose context is large mid-task, or one that waits for an answer: compact first, then send the answer.
   - `crew clear <name>` only between tasks: after the `Pushed:` is reviewed, `Next:` is written, and no background shell runs. `crew clear` types the `crew join <name>` line itself, and the member resumes from its `Next:`.
   - A member cleared after `Idle:` rejoins with nothing to do: clear it, then send its next task by name.
   - Never clear in the middle of a task. Never write another member's status to let a clear pass.
6. **The keeper owns the coordinator's context.** The coordinator cannot compact itself. It sends `crew send coordinator keeper "Question: compact me" -m "<keep ...>"` and ends its turn. The keeper waits until the coordinator is idle, then runs `crew compact coordinator`. The keeper never clears the coordinator.
7. **Prompts:** with no watch, the coordinator checks `crew board`. For a member stuck on a prompt, it runs `crew peek <name>`, then `crew key <name> y` (or `enter`). It never approves what the protocol forbids (`git add -A`, `git stash`, `git reset`, `git pull`, ...).
8. **Plan in `$(crew dir)/README.md`:** goal, lanes (name: issue, files), reviewers, end. Members read it when they join.
9. The project's `CLAUDE.md` / `AGENTS.md` wins over the crew's habits. The owner's word wins over everything.
10. **The coordinator always unblocks, without being asked.** It keeps `stuck.sh` (see [Scripts](#scripts)) running in the background. The script exits, and so wakes the coordinator, when a member sits on a permission prompt, a pane is gone, or nobody works and nobody writes while a status says `Blocked on:`. The coordinator then reads the statuses, breaks the knot by name (an order, an answer, a re-assignment), and starts the watcher again.
11. **Shared files get an order, not a ping-pong.** When several members must edit one file in a shared tree (README, a page), the coordinator writes the order once: who lands first, who next. Each member passes the file to the next with its hash. Hand-overs negotiated member to member tend to loop.
12. **A compact and its rejoin cannot fail.** A member that stays asleep after a compact stops the crew, and the owner's messages go unread.
   - `crew compact` and `crew clear` wait until the end, up to about 10 minutes. Run them with `run_in_background: true`, so that the caller keeps answering.
   - While one runs, it holds every wake to that member (`$(crew dir)/tmp/hold/<name>` holds its pid). The messages wait in the stream, and the newest one is sent when the hold ends.
   - `crew compact` sees the end only by the agent's "Compacted" mark on screen. If a new agent version draws that mark another way, the compact never ends: the hold stays for 10 minutes, and every message to that member is lost for that time. Check after each compact: when the pane shows `⎿ Compacted` and `$(crew dir)/tmp/hold/<name>` still exists, stop that `crew compact` (`kill <pid in the hold>`). The relay then sends the held wakes. After an agent update, run one compact by hand and check that it ends with `compacted <name>` within a minute.
   - The compacted member runs `crew unread <name>` first, before anything else.
   - The one who asked for the compact checks the rejoin: `$(crew dir)/cursors/<name>` passes the number of the next message to that member. If the cursor stays put: `crew peek <name>`, then `crew key <name> enter` when text waits on its input line, else `crew poke <name> "crew unread <name>"`. Only when that fails too, tell the owner.
   - Before a compact, the caller stops its own background shells (`stuck.sh`): a pane with a running shell shows as `shell`, not `idle`. It starts them again after the rejoin.

## Bring-up

From the project root, in the pane that becomes the coordinator:

```sh
crew init                       # .crew/ at the root, added to .git/info/exclude; or crew init --home
crew join coordinator
crew up star --dry              # check the order: dev1 dev2 tmux:%N reviewer
crew up star                    # the Crewfile from the preset star (see below); spawns, lays out, invites
crew recipe star --install coordinator
```

`crew recipe star --install coordinator` puts the scripts and the keeper's playbook in `$(crew dir)/work/coordinator/` (see [Scripts](#scripts)). Then open the bus:

```sh
D=$(crew dir); W=$D/work/coordinator; ROOT=$(cd "$D/.." && pwd)
tmux new-window -d -n bus -c "$ROOT" "{ crew relay >>$W/relay.log 2>&1 & } ; exec $W/stream.sh $D"
tmux split-window -h -b -t bus -c "$ROOT" "$W/chat.zsh $D"
```

Then send the keeper to its playbook:

```sh
crew send coordinator keeper "Plan: your playbook" -m "Read $(crew dir)/work/coordinator/playbook-keeper.md and follow it. Nothing to do until I send Question: compact me."
```

With `crew init --home`, the crew directory is not at the root: `$D/..` is then wrong, so set `ROOT` to the project root by hand.

## Crewfile

```
# star: 2x2 with the coordinator bottom-left; dev1 and dev2 build, reviewer reviews; all Opus 5.5 at xhigh in auto mode.
# The coordinator is the owner's pane, joined by hand. No watch: the coordinator approves prompts itself.
# The keeper compacts the coordinator on request. The bus tab runs crew relay and is opened by hand.
tab main layout=2x2
member dev1     reviewer=reviewer -- claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
member dev2     reviewer=reviewer -- claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
pane coordinator
member reviewer -- claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
tab keeper
member keeper   mute -- claude --model claude-sonnet-5-5 --permission-mode auto
```

- `layout=2x2` fills the panes in the tab's order, row by row. `pane coordinator` as the third entry puts it at the bottom left.
- Add `clone` to a dev's line for its own clone (`../<project>-<name>`). Use it when the devs could step on each other's build or index.
- It ships as the preset `star`, which `crew up star` copies to a crew with no Crewfile. An owner's preset of the same name, in `~/.config/crew/presets/star`, wins.

## Scripts

`crew recipe star --install coordinator` puts them in `$(crew dir)/work/coordinator/`, scripts executable. It never replaces a file there that differs: remove it first to take the recipe's.

- `chat.zsh`: the owner's line to the coordinator, the left pane of the bus. A zsh line editor: Return sends, Shift+Return adds a line, a multi-line paste waits until Return, Option+Delete deletes a word. The subject is the first line, cut to 60 characters; the body is the whole text. Shift+Return needs tmux to forward modified keys: `set -s extended-keys on` in `~/.tmux.conf` (with `set -as terminal-features 'xterm*:extkeys'`). Option+Delete and Option+Return need iTerm2's Profiles → Keys → Left Option key set to `Esc+`.
- `stream.sh`: prints every message of the stream, whole, as it arrives: the right pane of the bus.
- `stuck.sh`: wakes the coordinator, by exiting, when a member sits on a dialog or on typed text two checks in a row, a pane is gone or an agent exited two checks in a row (a background shell that ends can show `, exited` for one check), or nobody works and nobody writes while a status says `Blocked on:` something other than nothing or the owner. Start it with the Bash tool, `run_in_background: true`: `$(crew dir)/work/coordinator/stuck.sh "$(crew dir)" 5`. Start it again after each wake.
- `playbook-keeper.md`: the keeper's job, sent to it at bring-up.

## Tear-down

```sh
crew down --archive   # tells all, waits for each Done: (15 minutes), archives when nothing is left
tmux kill-window -t bus
```

`crew down` stops only what `crew up` opened. The bus is opened by hand, so close it by hand. The relay dies with its pane.
