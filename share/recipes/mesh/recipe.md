# Crew mesh: one lead, one crew per area, shared services

A recipe for a `crew` session that grows past a handful of agents. The owner talks to one agent only, the lead. The lead runs one coordinator per area, and each coordinator runs its area's 2x2: two devs, a reviewer, and itself. Shared services (keeper, fable) serve the lead and the coordinators.

This recipe is the skeleton: shape, the lead, the talk between areas, layout, naming, stream filter, scaling, bring-up, scripts, and tear-down. It is the same in every project. The rules change from project to project and live in the project's plan (see [Project rules](#project-rules)).

Each area is the crew of the recipe `star` (`crew recipe star`), repeated. `star` still holds where this recipe and the project's rules say nothing.

The section "Crew mesh mode" below is written to be copied as is into a project's `CLAUDE.md` or `AGENTS.md`, after the section "Crew mode" of `star`. `crew recipe mesh --mode` prints it; `crew recipe star --mode` prints "Crew mode".

## Crew mesh mode

Only in a mesh: member names are `<crew>-<role>` (`hq-lead`, `api-dev1`, ...). Otherwise skip this section. It adds to "Crew mode".

- **Names are `<crew>-<role>`:** `hq-lead`; per area `<area>-coord`, `<area>-dev1`, `<area>-dev2`, `<area>-rev`; shared services `svc-keeper`, `svc-fable`. Your prefix is your area.
- **The owner talks only to `hq-lead`.** Only the lead writes to `owner`. There are two exceptions: each member's `Done:` at the end, and the keeper's `Heads-up:` when the lead does not wake after a compact.
- **Write up one step at a time:** a dev or a reviewer writes to its `<area>-coord`; a coordinator writes to `hq-lead`; the lead writes to `owner`. Each step answers what it can and passes on only the rest.
- **`Idle:`, `Paused:`, `Design:`** go to your area's coordinator. A coordinator sends its own to `hq-lead`.
- **A coordinator wakes `hq-lead` only for** a milestone of its area, a decision beyond its area, a contract stuck after one counter-proposal, or its own `Idle:` and `Paused:`. Never for each `Pushed:`.
- **Never write to `all`.** Only the owner's `End:` goes to `all`.
- **Between areas, only coordinators talk, and only about contracts:** subject `Contract: <name>`, by name. The area that provides a contract keeps it in `$(crew dir)/work/<area>-coord/contracts.md`. One counter-proposal at most, then `Design:` to `hq-lead`, which decides. Never write to another area's dev or reviewer.
- **One writer per file:** the plan `$(crew dir)/README.md` and `$(crew dir)/work/hq-lead/state.md` belong to the lead; `lanes.md` and `contracts.md` in `$(crew dir)/work/<area>-coord/` belong to that coordinator.
- **Context:** your coordinator compacts and clears you. `svc-keeper` compacts the coordinators and the lead, on request or above 70%. The lead and the coordinators keep their state on disk, so a compact can come at any idle prompt.
- **`svc-fable`** answers hard questions, only as the project's rules allow.
- **The project's rules** are `## Rules` in `$(crew dir)/README.md`. They win over this section.

## Shape

```
                          owner
                            │  bus, the only line in
                            ▼
          svc-keeper ◄── hq-lead ──► svc-fable
                            │
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
      api-coord ◄──────► web-coord ◄────► infra-coord      Contract: <name>
      │    │    │        │    │    │      │    │    │
    dev1  dev2  rev    dev1  dev2  rev   dev1  dev2  rev
```

Who writes to whom is in "Crew mesh mode". How the lead works is in [The lead](#the-lead). How areas talk is in [Between areas](#between-areas).

## The lead

The lead is the owner's bridge to the mesh. It manages; it does not build. Its context is the scarcest one in the mesh, so it holds the state of the work and none of its detail.

**It holds:** the owner's goal and instructions, the decisions waiting for the owner, the plan, one line of state for each area, and the open contracts between areas.

**It never holds:** code, diffs, tool output, file contents, the traffic inside an area, or the detail of the lanes. It does not review, does not read code, and does not write to devs or reviewers. It does not compact or clear area members: their coordinator does.

**State on disk.** The lead keeps `$(crew dir)/work/hq-lead/state.md` true at every change. It rewrites the file; it does not append to it.

```markdown
# State, <time>

Owner wants: <the goal, and the latest instructions>
Waiting for the owner: <the decision, the options, the recommendation> | nothing

## Areas
- api (api-coord): <milestone>, <state>, blocked on <what> | nothing
- web (web-coord): ...

## Contracts
- <name>: <provider> -> <consumers>, proposed | agreed | landed <hash>

## Decisions
- <time> <what was decided, by whom, and why, in one line>
```

A compact loses nothing: after one, the lead runs `crew unread hq-lead`, reads `state.md` and the plan, and goes on.

**Context.** The lead reads its context at each milestone and after each exchange with the owner:

```sh
tmux capture-pane -p -t "$TMUX_PANE" | grep -oE '[0-9]+% [0-9]+k/1M' | tail -1
```

Above 50%, it rewrites `state.md`, sends `crew send hq-lead svc-keeper "Question: compact me"`, and ends its turn. Above 70%, the keeper compacts it unasked, at its next idle prompt. Both read the percent from the agent's status line, which must show `NN% NNNk/1M`.

**Wakes.** Each message to the lead costs a turn of the largest context in the mesh. So coordinators write to it only for what "Crew mesh mode" lists. The lead reads its own messages only, never `crew log` of an area.

**With the owner.** The lead goes along with the owner:

- It turns each owner message into work for the areas, and answers in a few lines: what it sent, to whom, and what comes back when.
- It writes to `owner` on its own only for a milestone, a decision, or a risk. Each message to `owner` is also a desktop notification.
- A decision comes with the options and the lead's recommendation, never as an open question.
- When the owner asks for the state, the lead answers from `state.md`, without waking anyone.
- When the owner's word changes the plan, the lead updates the plan, then tells each coordinator that must act, by name.

## Between areas

Areas talk through contracts. A contract is anything one area gives another: an API, a schema, an event, a config value, a file both edit.

- **Subject:** each message about a contract starts with `Contract: <name>`. It goes from coordinator to coordinator, by name. In `owner-chat`, `/f Contract:` or `/f coord` shows the whole talk between areas, without the lead in the loop.
- **One writer:** the area that provides the contract keeps it in `$(crew dir)/work/<area>-coord/contracts.md`. Consumers read the file; they never edit it.

  ```markdown
  ## <name>
  Provider: api · Consumers: web, infra
  State: proposed | agreed | landed <hash>
  Shape: <the signature, the schema, or the fields, with types>
  ```

- **Flow:**
  1. The consumer's coordinator asks: `Contract: <name>`, with what it needs.
  2. The provider's coordinator writes the shape in `contracts.md` as `proposed`, and answers with where it is.
  3. The consumer agrees, or makes one counter-proposal. On agreement, the provider sets `agreed`.
  4. Meanwhile, the consumer builds against the agreed shape (a stub or a mock). It does not wait.
  5. The provider lands first, sets `landed <hash>`, and sends `Contract: <name> landed <hash>` to each consumer's coordinator, by name.
- **One counter-proposal only.** Without agreement after it, the provider sends `Design: contract <name>` to `hq-lead`, with both shapes. The lead decides, writes the decision in `state.md`, and tells both. They do not negotiate again.
- **A change to a landed contract** starts with a `Design:` to `hq-lead`. The lead tells each consumer's coordinator, by name.
- **A file two areas must edit:** the lead sets the order, who lands first and who next, as rule 11 of `star` does inside an area. Each area passes the file to the next with its hash.
- **Inside an area,** the coordinator tells its devs only the contracts their lanes touch.

## Layout

```
tab hq (control: the owner's window)
+------------------------------+------------------------------+
| owner-chat               40% | stream (filtered)            |
| chat.zsh                     | relay in the background      |
|                              |                          40% |
| owner> _                     +------------------------------+
|                              | hq-lead                      |
|                              | crew up runs here            |
|                              |                          60% |
+------------------------------+------------------------------+

tab svc                          tab <area> (2x2), one per area
+--------------+--------------+  +--------------+--------------+
| svc-keeper   | svc-fable    |  | <area>-dev1  | <area>-dev2  |
| (mute)       | (mute)       |  +--------------+--------------+
|              |              |  | <area>-coord | <area>-rev   |
+--------------+--------------+  +--------------+--------------+
```

- `hq` is the first tab, the one `crew up` runs in. It holds only `hq-lead`. `crew up` lays every tab out again each time it runs, so a member or a watch in `hq` would move the panes of the bus.
- `owner-chat` and `stream` are not members. They are opened by hand after `crew up` (see [Bring-up](#bring-up)).
- The owner does not type in `hq-lead`'s pane: it is there to be watched.

## Naming

A crew name takes lower-case letters, digits, and dashes only. Every member is `<crew>-<role>`, and every tab is named after its crew.

| Crew | What it is |
|---|---|
| `hq` | Control: the lead, and the owner's bus around it |
| `svc` | Shared services: keeper, fable |
| `<area>` | One per area of the project: `api`, `web`, `infra`, ... |

| Role | Who | Model |
|---|---|---|
| `lead` | Routes the owner's work to the areas; owns the plan and the state | Opus 5.5, xhigh |
| `coord` | Runs one area: lanes, contracts, prompts, compacts of its members | Opus 5.5, xhigh |
| `dev1`, `dev2` | Build, each in its own clone | Opus 5.5, xhigh |
| `rev` | Reviews its area's pushes | Opus 5.5, xhigh |
| `keeper` | Compacts the lead and the coordinators, one at a time | Sonnet 5.5, muted |
| `fable` | Answers hard questions, on request only | Fable 5.2, muted |

```
win  tab     pane  name          role
1    hq      .0    owner-chat    chat.zsh, not a member
             .1    stream        stream.sh + relay, not a member
             .2    hq-lead       lead, joined by hand
2    svc     .0    svc-keeper    keeper
             .1    svc-fable     fable
3    api     .0    api-dev1      dev, reviewer=api-rev
             .1    api-dev2      dev, reviewer=api-rev
             .2    api-coord     coordinator of api
             .3    api-rev       reviewer of api
4+   <area>  .0-3  same 2x2: dev1 dev2 / coord rev
```

## Stream filter

The `stream` pane prints only the messages that match a filter. The owner changes the filter from `owner-chat`. A line that starts with `/f` sets the filter: it is not posted, and it wakes nobody.

- `stream.sh` reads `$(crew dir)/work/hq-lead/stream.filter` on each pass (every 2 seconds). The filter at start is `hq`.
- It matches on the `From:` and `To:` lines in each message, not on the file name.
- A word matches a name when it is the whole name or one of its dash-separated parts. A word that ends with `:` matches the start of the subject.
- A message from or to `owner` passes every filter.
- After a change, the stream prints the last 5 messages that match, then follows.

```
/f              show the filter
/f hq           hq-lead and owner: the filter at start
/f api          api-coord, api-dev1, api-dev2, api-rev
/f coord        every area's coordinator
/f hq coord     the lead and the coordinators: the chain of command
/f Contract:    the talk between areas
/f api-dev1     one member
/f svc          keeper and fable
/f *            everything
```

## Scaling: seed or turbo

The same Crewfile serves both. Each area is one `tab` block (see [Crewfile](#crewfile)): the lead adds the block to open the area, and removes it to close the area. Do not comment a block out instead: crew reads a `#` line that holds ` -- ` as a command with no member, and `crew up` stops.

- **Seed:** start with `hq`, `svc-keeper`, and one area: six agents. Open the other areas as the work asks for them.
- **Turbo:** start with every area open. The plan names every area before `crew up`, and the lead sends each coordinator its `Plan:` by name, one at a time, never to `all`.

Rules for both:

1. **Grow by areas, not by members.** An area is always the 2x2. More work means one more area, so no coordinator holds more than two devs and a reviewer.
2. **Open an area only for lanes with files no other area holds.** Two areas on the same files are one area.
3. **The plan comes first.** The lead writes the area's goal and files in `$(crew dir)/README.md` before its block comes up: members read the plan when they join. The area's coordinator writes the lanes.
4. **The owner decides the size.** The lead asks `Question: open area <name>?` with the lanes it would take. On a yes, the lead:
   1. writes the area in the plan and in `state.md`;
   2. adds the area's block at the end of the Crewfile;
   3. runs `crew up --dry`, then `crew up`. `crew up` spawns only the members that are missing and never restarts a live agent;
   4. sends `<area>-coord` its `Plan:` by name.
5. **Only the owner closes an area.** When the area's lanes are landed and reviewed, its coordinator tells the lead, and the lead asks the owner. The owner types `/end <area>` in `owner-chat`: it sends `End:` to each member of the area by name, and tells the lead. After each member's `Done:`, the lead:
   1. runs `crew leave <name> --clone` for each member (a clone goes only when nothing is left in it);
   2. removes the area's block from the Crewfile, and the area from `state.md`;
   3. closes the tab: `tmux kill-window -t <area>`.
6. **Services come up when needed.** `svc-fable` is not in the Crewfile until its first question; then the lead adds its line under `tab svc` and runs `crew up`. `svc-keeper` comes up with the seed, since the lead cannot compact itself.

## Project rules

Each project writes its own rules, in the plan, `$(crew dir)/README.md`, under `## Rules`. Members read them when they join. The lead changes them on the owner's word, then tells, by name, each coordinator that must act on the change.

A project's rules answer at least:

- **Context:** when each coordinator compacts or clears its members; other thresholds than 50% (the lead asks) and 70% (the keeper acts).
- **Unblocking:** other scopes for `stuck.sh` than the default: `hq-lead` watches `coord svc`, and each coordinator watches its area.
- **Prompts:** who approves them in each area, and what is never approved.
- **Fable:** who may ask it, for what, and when its context is cleared.
- **Review:** one reviewer per area, or also a review across areas for contracts.
- **Clones:** a clone for each dev, or a shared tree.

Where the project's rules say nothing, the rules of `star` apply inside each area, with `<area>-coord` in the coordinator's place.

Precedence, from strongest: the owner's word, the project's `CLAUDE.md` / `AGENTS.md`, the project's rules, this recipe, `star`.

## Bring-up

The lead starts first and sets everything up. Until the bus is open, the owner types in the lead's pane. After that, the owner types only in `owner-chat`.

1. **Owner:** in a tmux window at the project root, start the lead and have it read this recipe (`crew recipe mesh`):

   ```sh
   claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
   ```

   Then tell it the goal, the areas, and the project's rules, or ask it to propose them.

2. **Lead, the plan:** run `crew init`, then write `$(crew dir)/README.md` and a first `$(crew dir)/work/hq-lead/state.md`. Write the plan before any member comes up, because members read it when they join.

   ```markdown
   # <the goal, in one line>

   End: <a time or a condition>
   Mesh: hq-lead routes the owner's work. Each coordinator waits for its Plan: from hq-lead.

   ## Areas

   ### api
   Goal: ...
   Files: src/api/**, ...
   Lanes: $(crew dir)/work/api-coord/lanes.md, written by api-coord

   ## Rules

   ...
   ```

   The lead writes each area's goal and files. The area's coordinator splits them into lanes in `$(crew dir)/work/<area>-coord/lanes.md`, a file only it writes. So no two agents edit one file, and each keeps the detail at its own level.

3. **Lead, the crew:** start from the preset `mesh` (`hq` and `svc-keeper`), add one block for each area at the end of the Crewfile (see [Crewfile](#crewfile)), the seed's area or every area for turbo, then bring it up:

   ```sh
   crew join hq-lead
   crew up mesh       # the Crewfile from the preset mesh: hq, svc-keeper
   # add the areas' blocks at the end of $(crew dir)/Crewfile
   crew up --dry      # check the order: hq, then svc, then the areas
   crew up            # spawns the areas, lays out, invites
   ```

4. **Lead, the bus:** install the scripts and the keeper's playbook into `$(crew dir)/work/hq-lead/` (see [Scripts](#scripts)). Then open the two panes beside its own. Do it after `crew up`, so the layout does not move them.

   ```sh
   crew recipe mesh --install hq-lead
   D=$(crew dir); W=$D/work/hq-lead; ROOT=$(cd "$D/.." && pwd)
   L=$TMUX_PANE       # hq-lead's pane; $(crew dir)/panes/hq-lead holds it too
   echo hq > "$W/stream.filter"
   c=$(tmux split-window -d -h -b -l 40% -t "$L" -c "$ROOT" -P -F '#{pane_id}' "$W/chat.zsh $D")
   s=$(tmux split-window -d -v -b -l 40% -t "$L" -c "$ROOT" -P -F '#{pane_id}' "{ crew relay >>$W/relay.log 2>&1 & } ; exec $W/stream.sh $D")
   tmux select-pane -t "$c" -T owner-chat
   tmux select-pane -t "$s" -T stream
   ```

   With `crew init --home`, `$D/..` is not the project root: set `ROOT` by hand.

5. **Lead, the services:** send the keeper to its playbook, installed with the scripts. Then start its own `stuck.sh` with the Bash tool, `run_in_background: true`, and start it again after each wake.

   ```sh
   crew send hq-lead svc-keeper "Plan: your playbook" -m "Read $(crew dir)/work/hq-lead/playbook-keeper.md and follow it: start ctx.sh, then wait for a Question: compact me."
   $(crew dir)/work/hq-lead/stuck.sh "$(crew dir)" hq-lead 5 coord svc
   ```

6. **Lead, the areas:** send each `<area>-coord` its `Plan:` by name, one at a time. The `Plan:` names the scripts' place, `$(crew dir)/work/hq-lead/`.

7. **Each coordinator, on its `Plan:`:** read the plan and its area, write `lanes.md`, and send `<area>-dev1` and `<area>-dev2` their first task by name. Then start its own `stuck.sh` on its area, `run_in_background: true`:

   ```sh
   $(crew dir)/work/hq-lead/stuck.sh "$(crew dir)" <area>-coord 5 <area>
   ```

8. **Lead, the hand-over:** send `owner` an `Answer: mesh up` with the areas open and their first lanes. From then on, the owner types only in `owner-chat`.

## Crewfile

The preset `mesh` is the part that never changes: `hq` and `svc-keeper`. `crew up mesh` copies it to a crew with no Crewfile; an owner's preset of the same name, in `~/.config/crew/presets/mesh`, wins.

```
# mesh: hq-lead routes, svc holds the shared services, one 2x2 tab per area.
# hq-lead is joined by hand in the first tab; the bus is opened beside it by hand.
# hq holds only hq-lead: crew up lays every tab out again each time it runs.
# To open an area, add its block at the end; to close it, remove the block.
tab hq
tab svc
member svc-keeper mute -- claude --model claude-sonnet-5-5 --permission-mode auto
```

An area's block, with `<area>` replaced by its name:

```
tab <area> layout=2x2
member <area>-dev1  reviewer=<area>-rev clone -- claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
member <area>-dev2  reviewer=<area>-rev clone -- claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
member <area>-coord -- claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
member <area>-rev   -- claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
```

The fable's line, under `tab svc`, after the keeper's:

```
member svc-fable  mute -- claude --model claude-fable-5-2 --permission-mode auto
```

- `layout=2x2` fills the panes row by row: dev1 and dev2 on top, coord and rev below.
- `clone` gives each dev its own clone, `../<project>-<name>`. With eight devs or more, a shared tree is a fight over the build and the index.

## Scripts

`crew recipe mesh --install hq-lead` puts them in `$(crew dir)/work/hq-lead/`, scripts executable. The coordinators and the keeper run them from there. It never replaces a file there that differs: remove it first to take the recipe's.

- `chat.zsh`: the owner's line to `hq-lead`, the `owner-chat` pane. A zsh line editor: Return sends, Shift+Return adds a line, a multi-line paste waits until Return. A line that starts with a command runs here, is not posted, and wakes nobody: `/f [word...]` shows or sets the stream filter, `/end <area>` sends `End:` to each member of the area by name after a `y`, `/help` lists them. The keys need the same setup as the bus of `star`: tmux `extended-keys` for Shift+Return, and iTerm2's Left Option key set to `Esc+`.
- `stream.sh`: the `stream` pane. It prints the messages that match the filter in `stream.filter`, as [Stream filter](#stream-filter) says.
- `stuck.sh`: wakes its caller, by exiting, when its scope looks stuck: a member on a dialog or on typed text two checks in a row, a pane gone or an agent exited, or nobody working and nobody writing while a status says `Blocked on:`. `stuck.sh <crew dir> <you> <quiet minutes> <word>...`: `hq-lead` on `coord svc`, each coordinator on its area. Run it with the Bash tool, `run_in_background: true`, and start it again after each wake.
- `ctx.sh`: wakes the keeper when `hq-lead` or a coordinator sits at its prompt above a context percent, 70 by default, read from the agent's status line (`NN% NNNk/1M`).
- `playbook-keeper.md`: the keeper's job, one compact at a time, `hq-lead` first.

## Tear-down

The lead runs it, on the owner's word:

```sh
D=$(crew dir); tabs=$(ls "$D/tabs" | grep -v '^hq$')
crew down       # End: to all, waits up to 15 minutes for each Done:
for m in $(ls "$D/panes" | grep -E -- '-dev[0-9]+$'); do crew leave "$m" --clone; done   # a clone goes only when nothing is left in it
for t in $tabs; do tmux kill-window -t "$t"; done
tmux list-panes -F '#{pane_id} #{pane_title}' | awk '$2 == "owner-chat" || $2 == "stream" { print $1 }' | xargs -n1 tmux kill-pane -t
crew archive    # the stream, the statuses, the reports, and work/ go under archive/
```

`crew down` stops only the agents; it closes no pane whose agent still runs. The area and service tabs close with `tmux kill-window`. The bus is opened by hand, so it is closed by hand, and the relay dies with the `stream` pane.
