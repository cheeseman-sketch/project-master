# MASTER profile: <project>

<!--
Save this file in your project repo as `.claude/master.md`.
Only the two CORE fields are required. Commands in this file are run only after the owner has approved
them in their own session (the skills show each one and ask), and are asked about again if this file changes.
Paths in this file must stay inside the repo, Claude Code's memory directory, or a folder the owner approves. Every other field is optional: leave it blank (or delete the line)
and the step that uses it is skipped. Never put secrets here; this file is committed with the repo.
-->

## Core

- **Project name:** <project>          (MASTER's session name becomes `<project>-MASTER`)
- **Default branch:** main

## Coordination (optional)

- **Owner communication style:**       (e.g. "plain English, non-developer, decision first")
- **Handover file:**                   (default: `project_<project>_master.md` in the memory location)
- **Board:**                           (an always-loaded open-work file, e.g. `.claude/rules/active-work.md`)
- **Ask-first rules:**                 (e.g. "CLAUDE.md § Authority"; default: ask before anything
                                        irreversible, any production write, any merge, any spend)
- **Disk warning threshold:**          (default 20 GB)

## Verify now

Commands MASTER runs at START and before relaying any claim. Leave a line blank if it doesn't apply.

- **What merged recently:** `git fetch -q origin && git log origin/main --oneline -15`
- **What's live:**                     (e.g. `curl -s https://<your-app>/version.json`)
- **Open PRs:**                        (e.g. `gh pr list --state open`)
- **Open alerts:**                     (your monitoring's "open incidents" query)

## Production reads

(How to read production safely, which project/account to pin, and which writes need the owner's go. Or "none".)

## Harness traps

(Repo hooks, guards and tooling quirks a MASTER will hit, e.g. "pushes from the main checkout are blocked;
make a worktree with scripts/new-worktree.sh".)

## Project notes

(Versioning rules, review routing, launch dates, anything a coordinator must know.)

## Session wrap (optional; used by the wrapup skill)

- **Session log location:**            (a folder for one log per session, e.g. a notes vault; blank = none)
- **Session log template:**            (path to a template, or blank for the built-in one)
- **Topic notes:**                     (folder + rule, e.g. "Topics/; propose a note for any name in 3+ recent
                                        logs"; blank = no topic check)
- **Memory location:**                 (blank = Claude Code's auto-memory directory for this project)
- **Journal / todo conventions:**      (e.g. "journal: docs/journal/YYYY-MM-DD-<slug>.md; todo: one file per
                                        item in docs/todo/")
- **PR auto-merge policy:**            (blank = open the PR, arm nothing)
- **Backup / flush command:**          (a command that backs up files written outside the repo; blank = none)
