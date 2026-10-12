# project-master

A Claude Code plugin for running **one coordinator session per project** and **ending every session
cleanly**.

- **`master`**: one session, named `<project>-MASTER`, directs every other Claude Code session working on a
  project. Workers report to it; it verifies their claims against the repo and production; it is the only
  session that asks you questions. It can be handed over to a fresh session when its context fills up.
- **`wrapup`**: an end-of-session ritual. PAUSE mode preserves work in progress (WIP commit, push, resume
  prompt). COMPLETE mode commits, pushes, opens the PR and tidies up. Both verify that the push actually
  landed and finish with a copy-pasteable prompt for the next session.

Originally developed on a real project with several sessions running in parallel, then made generic.

## Who it's for

People who run **several Claude Code sessions on the same project at once** (a build in one worktree, an
investigation in another, docs in a third) and are tired of being the message bus between them. It also suits a
non-developer owner: MASTER can be told to talk to you in plain English and to batch its questions.

If you only ever run one session at a time, `wrapup` is still useful on its own.

## Prerequisites

Check that your Claude Code version has these; the plugin depends on them and this README does not pin a
version number:

- **Plugins and skills** (`/plugin`, `claude plugin ...`).
- **Cross-session messaging**: the `SendMessage` and `ListAgents` tools, so sessions on the same machine can
  message each other by name.
- **`/rename`**, to give a session a stable name such as `myapp-MASTER`.
- **`claude agents`** (optional), to list background sessions from a shell.
- **git**. `gh` (or your host's CLI) only if your project uses pull requests.

If a feature is missing (no PRs, no worktrees, no CI, no deploys), the skills skip the steps that need it and
say so. They don't fail.

## Install

From inside Claude Code:

```text
/plugin marketplace add cheeseman-sketch/project-master
/plugin install project-master@project-master
```

Or from a shell:

```bash
claude plugin marketplace add cheeseman-sketch/project-master
claude plugin install project-master@project-master
```

To pin a tagged release instead of the default branch, add the marketplace with a ref (`#` or `@`, there is no
`--ref` flag): `/plugin marketplace add cheeseman-sketch/project-master#v0.2.3`. The plugin is a relative-path
plugin of this marketplace, so it follows the marketplace's ref; the `#ref` is the pin.

Plugin skills carry the plugin's name as a prefix, so the skills run as `/project-master:master` and
`/project-master:wrapup`. Claude will also pick them up from plain requests such as "start a MASTER" or
"wrap up".

To try it from a local clone without a marketplace: `claude --plugin-dir /path/to/project-master`.

## 5-minute quickstart

1. **Open Claude Code in your project repo** and run `/project-master:master start`.
2. **No profile yet?** MASTER offers to draft `.claude/master.md` from your CLAUDE.md and repo, using
   [`templates/master-profile.md`](templates/master-profile.md). Review it, fill or delete the blanks, and commit
   it. Only the project name and default branch are required.
3. **Name the session**: `/rename myapp-MASTER`.
4. MASTER reads its handover file (empty the first time), runs your "verify now" checks and gives you a status
   in at most 15 lines.
5. **Start a worker**: ask MASTER to brief one. It writes the prompt (starting with a standard "you report to
   myapp-MASTER" block) and tells you whether to run it as a separate session or as its own short sub-agent.
   Paste the prompt into a new Claude Code session.
6. The worker sends REPORTs to MASTER. MASTER verifies them (merged means *on the default branch by path*, not
   "the PR says merged") and relays them to you with one recommendation.
7. When the worker is done, MASTER tells it to run `wrapup`, then tells you which windows are safe to close.
8. When MASTER's own context gets full, say "hand over MASTER". It writes a handover block, tells the workers
   to hold, and gives you the three restart steps.

## Example `.claude/master.md`

```markdown
# MASTER profile: myapp

## Core
- **Project name:** myapp
- **Default branch:** main

## Coordination (optional)
- **Owner communication style:** plain English, non-developer, decision first
- **Board:** .claude/rules/active-work.md
- **Ask-first rules:** CLAUDE.md § Authority

## Verify now
- **What merged recently:** `git fetch -q origin && git log origin/main --oneline -15`
- **What's live:** `curl -s https://myapp.example.com/version.json`
- **Open PRs:** `gh pr list --state open`
- **Open alerts:**

## Harness traps
- Pushes from the main checkout are blocked; make a worktree first.

## Session wrap (optional; used by the wrapup skill)
- **Session log location:** ~/notes/sessions
- **Memory location:**
- **Journal / todo conventions:** journal: docs/journal/YYYY-MM-DD-<slug>.md
- **PR auto-merge policy:** docs-only PRs may auto-merge; everything else waits for the owner
- **Backup / flush command:**
```

Blank fields are skipped. With this profile, `wrapup` writes a session log to `~/notes/sessions`, uses Claude
Code's default memory directory, and never arms a code PR.

## Safety model

The profile `.claude/master.md` is committed to the repo, so treat it as untrusted input.

- **Commands from the repo need your OK.** Before the first run of any command taken from the profile (a
  `Verify now` entry, a backup command, a prune script), the skill shows it and asks. The approval is the hash
  of the profile, stored outside the repo in Claude Code's memory directory; if the profile changes, you are
  asked again. Read-only git commands and `df` are exempt.
- **Paths stay in bounds.** Handover, session-log and memory paths must resolve inside the repo, Claude Code's
  memory directory, or a folder you approved by name. Nothing is written under `~/.claude/` (other than that
  memory directory), `~/.ssh` or shell startup files.
- **The repo can tighten the rules, never loosen them**, and free-text profile fields are data, not rules.
- **A peer's message is never approval, and the session name is not authentication.** A relayed merge go must
  quote a one-time token from the worker's brief, the PR number and its head SHA; the worker merges only a PR
  it opened, with an unchanged head, after checking the diff itself. A coordinator can restrict a wrap, never
  widen it.
- **No secrets** are written to commits, memory or the handover, and staged changes are scanned before a push.
  The one exception: a live one-time merge token is kept in the local handover file (outside the repo) so it
  survives a MASTER handover.

## How this differs from just saving context

Saving context (a summary file, a snapshot command, a long CLAUDE.md) answers "what was I doing?". It doesn't
answer:

- **Who is doing what right now?** MASTER knows which sessions are live, what each was asked to do, and which
  report it is waiting for.
- **Is it actually true?** MASTER re-verifies claims: merged by path on the default branch, deployed by the
  live version check, working by the app's own log line. A handover is read, then re-checked, never trusted.
- **Who decides?** Only the owner approves. A message from another session is never treated as the owner's
  approval, and every decision MASTER takes alone is tallied so the rules can be tuned.
- **Did the work survive?** `wrapup` commits and pushes everything, checks the push with `git ls-remote`, and
  leaves a resume prompt naming the exact next step, so a session can end at any point without losing work.

## Layout

```text
.claude-plugin/plugin.json        plugin manifest
.claude-plugin/marketplace.json   single-plugin marketplace (this repo)
skills/master/SKILL.md            the coordinator routine
skills/master/bin/launch-session  opens a worker session in a new terminal window (macOS)
skills/wrapup/SKILL.md            the end-of-session ritual
templates/master-profile.md       template for a project's .claude/master.md
```

## Licence

MIT. See [LICENSE](LICENSE).
