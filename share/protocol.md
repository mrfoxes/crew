# The crew protocol

You are one of a few coding agents (Claude Code, Codex, Antigravity, or
another) working on one project at the same time, each in a terminal pane the
owner watches. You talk through one numbered stream of messages in the crew's
directory, `.crew/` at the project's root or `~/.crew/<project>/`, which
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

- `<to>` is a member's name, `all`, or `owner`. Start the subject with what it
  is: `Plan:`, `Heads-up:`, `Question:`, `Answer:`, `Review:`, `Pushed:`,
  `Done:`.
- A message to a member is typed into their pane as one line, `crew: message
  0012 from codex. Run: crew unread claude`. Typed while you work, it waits
  in your agent's queue until the turn ends: a wake never interrupts you.
  When such a line reaches you, run `crew unread <you>` and act on what it
  says; it comes from the stream, not from the owner.
- Answer every question and every review finding: fixed (with the hash) or not
  (with the reason). Do not send messages that only acknowledge: every message
  wakes someone.
- `owner` is for what only the owner can decide; it reaches them as a desktop
  notification. Never wait for the answer: take other work meanwhile.
- Run `crew unread <you>` at every step boundary, and before and after every
  push. To read a message again, `crew show 0012`; the last few, `crew log`.

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

`crew board` shows every status with its age, the lock, the latest messages,
and CI.

## One working tree, many hands

When the crew shares one checkout, every file on disk, the git index, and the
build directory are shared:

- Edit only the files on your `Files:` line. Before taking one, check that no
  other status lists it; for a file several of you need, send `Heads-up:`,
  edit, commit, and release it within minutes.
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

## Reviews

When the one you review sends `Pushed:`, read the commit with `git show
<hash>` within 15 minutes: bugs first, then a missing test, then a document
the change left untrue. Send `Review:` with each finding (file, line, problem,
fix), or one line saying it is clean.

## The end

When your time is up: every commit you pushed is green, every message to you
is answered, and unfinished work either lands as a step its message calls
partial or is saved as `reports/<you>.patch` in the crew's directory
(`git diff -- <your paths> > "$(crew dir)/reports/<you>.patch"`, new files
listed in the report) with your files put back by
`git checkout HEAD -- <your paths>`, which the gate holds for the
coordinator. Write your report (`crew report <you>`, the text on stdin:
commits, issues, reviews given and got, what the next crew should do first),
then send `all` your `Done:`.
