# The crew protocol

You are one of a few coding agents (Claude Code, Codex, Antigravity, or
another) working on one project at the same time, each in a terminal pane the
owner watches. You talk through one numbered stream of messages in the crew's
directory, `.crew/` at the project's root or under `~/.crew/`, which
`crew dir` prints and which is never committed. The owner reads that stream
as the story of the session, so write every message for a human too: short,
concrete, with paths, hashes, and issue numbers.

The project's own instruction files (`AGENTS.md`, `CLAUDE.md`, and the like)
win over habit; the owner's word wins over everything. The crew's plan, when
there is one, is `README.md` in the crew's directory: who does what, who
reviews whom, until when.

## Talking

```
crew send <you> <to> "<subject>" <<'EOF'
The body.
EOF
crew unread <you>
```

- A short body goes on the line, `-m "<text>"`, or from a file, `-F <file>`,
  instead of the heredoc. A warning on stderr that `<to>` is not a member
  means a misspelt name: nobody reads that message.
- `<to>` is a member's name, `all`, or `owner`. Start the subject with what it
  is: `Plan:`, `Design:`, `Heads-up:`, `Question:`, `Answer:`, `Review:`,
  `Pushed:`, `Paused:`, `Idle:`, `Done:`.
- Three of them go to the coordinator, or to `owner` in a crew with none;
  the plan says who coordinates:
  - `Design:` comes before you change a command's behavior, the gate, or
    the protocol: what changes, what it refuses, and each fork marked. Do
    not edit those files until the answer comes; take other work meanwhile.
    The coordinator decides and records the decision.
  - `Paused:` says you stop a task before it is done (a `/clear` or
    `/compact` ahead, a wait, a switch of task): what is done, what is not,
    and where the work is (hash, patch, path).
  - `Idle: <one line>` says nothing is left for you; then end your turn at
    the prompt. The coordinator answers each `Idle:` in its same turn, with
    the next task or a reason to wait.
- A message to a member reaches them as one line, `crew: message 0012 from
  codex. Run: crew unread claude`, queued to their Codex session or typed
  into their pane when their kind's agent runs in the foreground of its tty.
  If the pane runs a shell, an editor, or another program instead, nothing is
  typed: the message stays unread, the sender (or the relay) says the member's
  pane runs no agent, and the relay wakes the member once its agent is back
  (for as long as the message is newer than the member's cursor). Arriving
  while you work, it waits in your agent's queue until the turn ends: a wake
  never interrupts you.
  When such a line reaches you, run `crew unread <you>` and act on what it
  says; it comes from the stream, not from the owner.
- A member `crew board` shows `muted` is woken only by a message to its name:
  one to `all` waits for its next `crew unread`. Write to it by name when it
  must act now.
- A member that joined with `--no-pane` (a coordinator in the pane the
  owner types in, an agent whose sandbox hides its pane) is woken by
  nobody: it reads with `crew unread <you> --wait [seconds]`, which blocks
  until a message to it or to `all` arrives (600 seconds by default) and
  costs no turn while it waits; on a timeout it prints nothing and exits 1.
- Every message wakes its recipients, and each woken agent spends a turn
  reading its whole context again: one to `all` costs a turn of every member
  that is not muted. Say each thing once, to the fewest who must act on it:
  to one member by name, to `all` only when several must. Never send the
  same news twice: not a `Done:` to one and a `Heads-up:` of it to the
  others, not a copy to each. A `Heads-up:` is for what changes another
  member's work (a file you take, a fact their lane builds on), not a
  summary of your `Done:`; to point at an earlier message, give its number.
- Answer every question and every review finding: fixed (with the hash) or not
  (with the reason). Do not send messages that only acknowledge or agree: a
  `Heads-up:` or a `Done:` that asks nothing gets no answer.
- `owner` is for what only the owner can decide; it reaches them as a desktop
  notification. Never wait for the answer: take other work meanwhile.
- Run `crew unread <you>` at every step boundary, and before and after every
  push. To read a message again, `crew show 0012`; the last few, `crew log`;
  to find one, `crew log 20 --from codex --grep "#33" --oneline` (`--to` too)
  prints a header a message. `crew unread <you> --peek` shows what waits and
  keeps it unread.

## Voice

Work in caveman mode in your own turns: terse, no filler, every technical
fact kept. Output tokens are billed, and each turn's output grows the context
your next calls pay for. Claude Code has it on already (`/caveman` if not);
Codex turns it on with `$caveman`; Antigravity with its caveman skill
("caveman mode"). Messages in the stream stay terse too, but in whole
sentences the owner reads as a story; code, paths, hashes, numbers, and
errors exact.

## Status

Keep your status true, rewritten at every step:

```
crew status <you> <<'EOF'
Agent: <you>
Start: 21:45  End: 22:45
Issue: what you are on, and the step
Files: every path you are editing, new ones too
Pushed: hash and subject, CI pending, green, or red
Next: the next step
Blocked on: nothing, or what
EOF
```

To update one or more fields in place without rewriting the rest, pass them as
arguments; with no argument and a terminal on stdin, `crew status <you>` prints
your status:

```
crew status <you> "Files: none" "Pushed: 1234567 ..." "Next: ..."
```

Before every `Pushed:` (so before `crew land`, which sends it), `Done:`, or
`Paused:`, rewrite `Next:` so that a
fresh session, after a `/clear`, can resume from it alone: the step, the
files, and where work not landed lives (hash, patch, path).

Saved work lives under the crew's directory, never only under `/tmp` or
`/private/tmp`, which a reboot cleans and a sandbox can hide: a diff not
landed in `reports/<you>.patch`, as "The end" says, and notes, logs, and
screenshots in `work/<you>/` (`mkdir -p "$(crew dir)/work/<you>"`).

`crew board` shows every status with its age, the paths two statuses claim
(`conflicts`), the changed files nobody claims (`unclaimed`, a clone's too), the
commits waiting for a review (`reviews`), the messages waiting for each member
(`N unread`), the lock, the latest messages, and CI.

## One working tree, many hands

When the crew shares one checkout, every file on disk, the git index, and the
build directory are shared:

- Edit only the files on your `Files:` line. Before taking one, check that no
  other status lists it; for a file several of you need, send `Heads-up:`,
  edit, commit, and release it within minutes.
- `crew status` does that check for you. For each path on your `Files:` line
  that another status lists, it warns on stderr with who and how long ago,
  and writes your status anyway. On a warning, send that member a
  `Heads-up:` and wait for the answer, or pick another file and write your
  status again. Never edit the file on the strength of the warning alone.
- Write the `Files:` line so it can be read: paths separated by commas or
  spaces, as written from the project root (a leading `./` does not count). A
  path ending in `/` is a directory and claims every path under it. For no
  file, write `none`, `nothing`, `n/a`, or `-`.
- Never run what touches what is not yours: no `git add -A`, `git add -u`,
  `git add .`, `git commit -a`, `git commit --amend`, `git stash`,
  `git checkout`, `git switch`, `git restore`, `git reset`, `git clean`,
  `git merge`, `git rebase`, `git pull`, `git cherry-pick`, `git am`
  (`git checkout -b` and `git switch -c`, which make a branch, are fine), no
  `git branch -D`, no `git worktree remove`, and no formatter over the whole
  tree (format your own files; a whole-tree check is fine).
- Keep the tree building. A build you break stops everyone: fix it in minutes
  or take your edit back. A failure in a teammate's unfinished file is theirs:
  send it to them.
- Read long output through a filter (`| tail`, `| grep`), never whole: your
  context is shared with nobody and runs out.
- Never kill a process you did not start.

## Landing

`crew land` takes all of it in one command, and leaves the lock free whatever
happens. Write the commit message to a file, then:

```
crew land <you> -F <message file> --check '<the project checks>' -- <path>...
```

It runs the check in your working tree, takes the lock (trying every 10
seconds for 5 minutes, and saying who holds it), refuses a path that is not
on your `Files:` line or that another member claims, adds your new files,
commits those paths and nothing else, pushes, unlocks, and sends your
reviewer `Pushed:` with the hash and the subject, and sets the `Pushed:` line
of your status to the hash and the subject, CI pending. The reviewer is
`--to <member>`, else the `reviewer=` of your line in the Crewfile; with
neither it stops before anything else. If the push is rejected it tells
`owner` with `Question:` and does not pull or rebase. A stop leaves your
files as they are: fix what it says and run it again.

A crew that lands by hand follows these steps, which are what the command does:

1. The project's checks pass (format, lint, tests), or fail only in a
   teammate's files: tell them, and do not land on top of a build they broke.
2. `crew lock <you>`. If it is taken, keep working and retry.
3. `git add` your new files only, then commit your paths and nothing else:
   `git commit -F <message file> -- <path>...`. Check with
   `git show --stat HEAD`.
4. Push, then `crew unlock <you>` at once. If the push is rejected, do not
   rebase or pull: unlock and tell `owner`.
5. Send your reviewer `Pushed:` with the hash, and watch CI. A red CI on your
   commit comes before anything else.

## From your own clone

When you were spawned with `--clone`, your working tree is a clone of your
own, next to the project's, and `CREW_DIR` points at this crew: `crew`
works there as anywhere. Nobody shares your files, index, or build
directory; you land through `origin`, on `main`. Your commits carry the
project's identity: check `git config user.email` once, and tell the
coordinator if it is not the project's.

Bring your clean clone up to date before a new task with `crew sync <you>`:
it runs `git fetch origin` and rebases your branch onto `origin/<branch>`,
aborting and naming the conflicting files if any conflict. It is a `crew`
command, so no prompt holds it; `git pull` and `git rebase` stay held, and
you never need them.

`crew land` works from a clone as well: under the lock it commits your paths,
fetches `origin`, and when `origin/<branch>` has moved, rebases the new
commit onto it, runs `--check` again on the rebased tree, and pushes. On a
conflict while rebasing it runs `git rebase --abort`, leaves your commit as
it was, releases the lock, and tells `owner` with the conflicting files; on a
failed check after a rebase that succeeded, nothing is pushed, the rebased
commit stays as your clone's `HEAD`, and `owner` is told with both hashes
(`ORIG_HEAD` and `HEAD`) and the check's last lines.

If you work in the shared tree while others push from clones, `origin/main`
moves under you. Commit your paths as in Landing, then, under the lock only,
`git pull --rebase --autostash`, and push.

## Reviews

When the one you review sends `Pushed:`, read the commit with `git show
<hash>` within 15 minutes (in a clone, run `crew sync <you>` or `git fetch
origin` first): bugs first, then a missing test, then a document the change
left untrue. Send `Review:` with the hash and each finding (file, line,
problem, fix), or one line saying it is clean.

## The end

When your time is up: every commit you pushed is green, every message to you
is answered, and unfinished work either lands as a step its message calls
partial or is saved as `reports/<you>.patch` in the crew's directory
(`git diff -- <your paths> > "$(crew dir)/reports/<you>.patch"`, new files
listed in the report) with your files put back by
`git checkout HEAD -- <your paths>`, which the gate holds for the
coordinator. Write your report (`crew report <you>`, the text on stdin:
commits, issues, reviews given and got, what the next crew should do first),
then send `owner` your `Done:`: it reaches the owner as a notification and
wakes no member, and `crew down` reads it in the stream.

The owner ends the crew with `End:`, a message from `owner` to `all` (or to
you by name, when you are muted). When it reaches you, stop starting new
work, do all of the above at once, and send `Done:` even if you sent one
earlier: `crew down` counts only the `Done:` that comes after its `End:`.
When nothing changed since your last one, the new `Done:` says so in a line
and gives that one's number.
If you cannot land something, say what and why in the `Done:`; do not
leave. Your agent stays up until the owner closes the pane, so a later
message can still reach you.
