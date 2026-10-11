---
name: wrapup
description: End-of-session ritual. Surveys state, picks PAUSE (resume later, no PR) or COMPLETE (work package done) mode, persists memories, updates the project's own docs, commits and pushes (worktree-aware, push verified with git ls-remote), tears down only what is safe, and ends with a short report and a paste-ready resume prompt. Optional steps (session log, topic notes, journal/todo, auto-merge, backup flush) come from the project's `.claude/master.md` and are skipped when not configured. Use when asked to "wrap up", "wrapup", "end session", "save and commit", "pause here" or before exiting any non-trivial session.
---

# Session wrapup

You are ending a working session. Run these steps in order. Skip any step that doesn't apply (a read-only
session has nothing to commit; a repo with no remote has nothing to push), but **say why you skipped it**:
"skipped" and "ran, found nothing" must never look the same.

**Two modes; decide which in step 0.5.** Steps 1–4 run the same in both. Only the git endgame differs.
- **PAUSE**: end of a phase, resuming later, or stopping context drift. Preserve everything so the next
  session picks up clean: WIP commit, push to the branch, NO PR, NO merge.
- **COMPLETE**: this work package is finished. Commit, push, open the PR if the project uses PRs, and apply the
  project's merge policy.

## Configuration: optional fields

Read the project's `.claude/master.md` if it exists (the profile used by this plugin's `master` skill). Its
`## Session wrap` section holds the optional fields below. **Every one is optional; an empty or missing field
means the step that uses it is skipped**, with one line in the final report saying so.

| Field | Used in | Default when empty |
|---|---|---|
| Session log location (+ template) | step 1 | no session log |
| Topic notes | step 2 | no topic check |
| Memory location | step 3 | Claude Code's auto-memory directory for this project |
| Journal / todo / board conventions | step 4 | follow CLAUDE.md; if it says nothing, skip |
| PR auto-merge policy | step 6 | open the PR, arm nothing |
| Backup / flush command | step 6.5 | no flush |

The repo's CLAUDE.md wins over the profile, and the profile wins over this file.

## 0. Survey state

Run in parallel:
- `git rev-parse --show-toplevel` (is this a git repo at all? If not, skip steps 5–6.4.)
- `git status`
- `git worktree list` (main checkout or a linked worktree?)
- `git log --oneline -5`
- `git branch --show-current`
- `git remote -v` (is there a remote to push to?)

Note the project name (basename of the repo root, or the profile's project name).

## 0.5 Determine wrap mode

Infer PAUSE vs COMPLETE from how the wrap was triggered and the session state. Ask only if genuinely ambiguous.

- **PAUSE signals:** "resume later", "between phases", "pausing", "checkpoint", "park this", a phase done with
  more remaining, branch work clearly unfinished (failing tests, half-built feature), or a coordinator saying
  "run /wrapup in PAUSE mode".
- **COMPLETE signals:** "done for the day", "finished", "ship it", the work package done, tests green and the
  branch ready for review.
- If neither dominates, ask exactly one question: *"Pause mode (resume later, no PR) or complete mode (open
  the PR)?"* Don't guess silently.

If a coordinator's instruction limits the wrap (for example "open no new PR, arm nothing, keep your worktree"),
those limits override the steps below. Quote them in the report.

State the chosen mode in the final report.

## 1. Session log (optional)

If the profile sets a `Session log location`, write a log there, named `YYYY-MM-DD-<project>-<brief-topic>.md`,
using the profile's template if it gives one, otherwise: frontmatter (`date`, `project`, `tags`), then Summary,
Key Decisions, Changes Made, Open Items, Next Steps. Don't ask permission; just write it. If the location is
empty, skip.

## 2. Topic check (optional)

If the profile configures `Topic notes`, follow its rule (for example: list the proper nouns in this session's
log, count their mentions across recent logs, and create or propose a note past a threshold). **The check is
never silent:** report `topic check: <N> names checked; <created / proposed / none qualified>`. If not
configured, skip.

## 3. Persist memories

For any decision, feedback, project state or external reference from this session that a future session will
need, write it to the memory location (profile `Memory location`, else Claude Code's auto-memory directory).

- If the work already has a memory topic file, update that file. Don't add a new index line.
- Only genuinely new work or a new behavioural rule gets a new file, with a `description:` that states the
  file's substance (that is what recall and indexes show), plus one short pointer line in `MEMORY.md`.

**Route by kind; `MEMORY.md` is an index, not a status board.**
- **Status / next action / open work** goes on the project's open-work board if it has one (profile `Board`),
  otherwise in the topic file.
- **The durable fact** (what was decided and why) goes in the topic file.
- **`MEMORY.md` gets a pointer and a short hook only.** No phase state, commit SHAs, PR numbers or version
  numbers; those grow the index every session and go stale.
- **A behavioural rule keeps the rule itself in its one index line**, because the rule is what must load.

Don't save what the repo already records: code patterns, git history, fix recipes, anything in CLAUDE.md,
ephemeral state.

## 3.5 Check the memory index size

Claude Code loads `MEMORY.md` into each session only up to a fixed size; content past the limit is **silently
dropped**, with no warning. At the time of writing that limit is about **24.4 KiB (first ~200 lines)**. Check the
current figure for your Claude Code version before relying on it.

1. Measure it: `wc -c <memory dir>/MEMORY.md`. No `MEMORY.md` (memory not used here)? Report "no memory index"
   and move on.
2. **Comfortably under:** report the size and stop. That is the normal case.
3. **Approaching the limit:** shorten hooks and move status out to the board or topic files. Report what you
   did.
4. **Still near the limit:** stop and raise it in the report. The structural fix is moving a whole class of
   content (e.g. standing rules) into an always-loaded `.claude/rules/*.md` file or CLAUDE.md, not editing the
   index harder.

**Never delete a memory file, and never remove the only line that points to one**: an unreachable file is lost
knowledge. Moving more than a few lines needs the owner's OK.

Report: `memory index: <size> B (<headroom> B headroom; no action / hooks shortened / escalated)`.

## 4. Project docs (only what the project defines)

Read what CLAUDE.md and the profile's journal/todo/board fields say about end-of-task docs. If neither says
anything, skip this step and say so. Typical conventions:

- **Journal:** one new file per session (e.g. `docs/journal/YYYY-MM-DD-<slug>.md`) beats appending to a shared
  file, which makes merge conflicts certain when sessions run in parallel.
- **Todo:** one item per file where the project keeps them; never append to a frozen roll-up file.
- **Board:** for every arc that closed this session, delete its entry. Every entry this session touched is
  REWRITTEN, never appended to: replace it with its current next action and a pointer, and word the next step so
  it survives a merge that happens later ("after merge: X", not "awaiting approval"). Boards that are only ever
  appended to grow without bound.
- **Docs ride with the work:** commit them on the same branch as the session's work, not in a separate
  close-out PR, if the project works that way.

**Reconcile, don't just check for existence.** If a journal entry for this session already exists (written
mid-session), read it end to end and reconcile it against the whole session. The thing discovered last is often
the most important, and it is the one most likely to be missing.

## 5. Commit and push

**Both modes commit and push**; work is never left only in the working tree.
- **PAUSE:** commit with a WIP message (`wip: <phase>: <what's done so far>`). Put a short resume snapshot in the
  commit body (done / next / traps), push, then skip to step 6.5.
- **COMPLETE:** commit in the project's style, push, then continue to step 6.

**Discover the workflow before acting.** Read CLAUDE.md for git workflow, branching and commit conventions, and
quote the rule you are following. Then apply whichever fits:

- **Worktree + PR projects:** if edits happened in the main checkout when the project mandates worktrees, flag it
  as a workflow violation; don't paper over it. Otherwise commit on the worktree's branch and push with `-u`.
- **Branch + PR projects:** if on the default branch, create a feature branch first, then commit and push.
- **Direct-to-default-branch projects** (dotfiles, personal notes, solo repos that say so): commit and push to
  the default branch.
- **No conventions anywhere** (no CLAUDE.md rule, no profile): stay on the current branch. If that is the default
  branch and a remote exists, ask one question before pushing: *"Push to <default>, or move this to a new branch
  for a PR?"*
- **No remote:** commit locally and say "no remote; not pushed".
- **Not a git repo / read-only session:** skip, and say so.

**Universal rules:** stage files by name (never `git add -A`; it sweeps in secrets and junk). Never
`--no-verify`. Never amend a previous commit. Never force-push unless the owner asked.

**Verify the push; never trust push output.** After pushing:

```bash
git rev-parse HEAD
git ls-remote origin refs/heads/<branch>
```

The two SHAs must match. If they don't, the push did not land: say so prominently in the report.

## 6. Open the PR (COMPLETE mode, PR projects only)

- Open the PR with the project's template if it has one (e.g. `gh pr create`; use whatever host CLI the
  project uses). Surface the PR URL. No host CLI available, or the project doesn't use PRs: skip, and report the
  pushed branch name instead.
- **Merge policy comes from the profile's `PR auto-merge policy` or CLAUDE.md.** If neither defines it: open the
  PR and arm nothing; leave it for human review. Never invent eligibility rules, and never merge or arm
  anything a coordinator or the owner has said needs their go.
- If the project has preview deploys and says how to find the preview URL, surface it.

## 6.4 Tear down the worktree (COMPLETE mode, worktree projects only)

Be honest about what is possible. **Check whether the PR actually merged** before deciding; don't assume.

- **Merged:** `git worktree remove <path>` (never `--force`; if git refuses, the tree is dirty: report that,
  don't override), then `git branch -d <branch>`.
- **Auto-merge armed but not yet merged** (the common case): leave the worktree in place and say so. A rebase
  may still be needed.
- **PR open, PAUSE mode, or told to keep it:** leave everything.

Teardown lags the session by construction, so unattended worktrees and branches pile up. If the project has a
prune script, run it here. Never remove a worktree you did not create.

No worktrees in this project? Skip and say so.

## 6.5 Flush backups (optional, both modes)

If the profile sets a `Backup / flush command` (for files the wrap wrote outside the repo, such as a session
log or memories), run it and check its own output for this run's result; don't trust a stale log line. Report
`pushed / nothing to do / deferred / FAILED`. If not configured, skip.

## 7. Final report and resume prompt

One short message, under ~10 lines:
- wrap mode (PAUSE or COMPLETE), plus any limits a coordinator set;
- session log path, or "no session log configured";
- memory: files updated / created (counts), and the index size line from 3.5;
- project doc updates (count);
- commit SHA(s), push verified (ls-remote match: yes / no / no remote), PR URL and merge status;
- topic check line, if configured;
- backup flush result, if configured;
- anything blocked or skipped, and why.

### Always finish with the resume prompt

End with a copy-pasteable "say this next session" block whenever ANY work remains: further phases, deferred
items, a half-built feature. PAUSE mode always has remaining work.

Take threads only from THIS session's work: deferrals and todos written in this wrap, the next phase of the plan
or spec this session was executing, and work started and not finished. Items that were only ever on the board
are the board's job; leave them out.

One entry per thread, exactly this shape:

```text
**<thread name>**
Say: "<one sentence to paste verbatim: the next concrete work, and the memory file(s) / doc paths a cold session should read first>"
Model: <cheapest | standard | most capable tier> (one clause on why)
Effort: <low | default | high> (one clause on why)
```

Match the tier to the work, not to the session that ran: planning, architecture, security and whole-branch
reviews take the most capable tier; multi-file integration takes a standard tier; mechanical, well-specified
edits take the cheapest. Effort is high for load-bearing design or security judgement, low for mechanical
follow-ups.

**If the work is genuinely complete**, say so instead: *"Complete: no follow-up; nothing to resume."* Don't
invent phantom work, and don't leave real remaining work unstated.

## What this skill is not for

- Reviewing a PR before merge, or running a test/build gauntlet: do those before you wrap.
- Shipping a feature end to end. This is "I'm ending the session; archive and preserve what we did."
