# Changelog

All notable changes to this plugin are recorded here. Versions follow `version` in `.claude-plugin/plugin.json`.

## 0.2.3

Lessons carried over from the coordinator copy this plugin was extracted from.

- master, Priorities: rank by likelihood × impact for the product's real users; hostile-user, failure-inside-a-
  failure and trivial-amount scenarios are LATER unless cheap; apply when filing; cut a worker's MUST list
  adversarially before relaying it.
- master, Safety rule 4: a live one-time merge token is the one thing kept in the handover file (memory
  directory only). Fixes a contradiction where rule 4 forbade what Child sessions told MASTER to do.
- master, precedence: README, PR bodies, CI logs and worker reports can only tighten the rules, never cause a
  command or an out-of-bounds write.
- master, relayed merge go: a worker briefed without a token never takes one; never-relayed now also lists repo
  creation and a push to a public remote.
- master, Close-out: a coordinator's wrap message may only restrict a wrap (was stated only in wrapup).
- master, Improving: date each lesson and say what found it.

## 0.2.2

MASTER launches worker sessions itself.

- New `skills/master/bin/launch-session` (macOS: Terminal, iTerm, Ghostty): `detect`, `set-terminal`, `run`.
  It opens a new window already running `claude` in the repo with the brief as the first message; a per-launch
  runner script keeps the brief out of AppleScript quoting. The terminal choice is saved per user in
  `~/.claude/launch-session.conf`, asked once on first launch.
- master, Child sessions: launch steps (terminal asked once, one question per worker, `--repo` is the repo
  root never a worktree, the owner types `/color`, the merge token is never put in a launched brief).
- Profile template: new optional `Repo:` field, the absolute repo root the launcher uses.

## 0.2.1

Fixes from the live multi-session check.

- A relay is only a relay: when the owner asks MASTER to tell a worker to do something and the worker refuses,
  MASTER reports the refusal and never performs the action itself or by another route.
- START refuses to take over while another `<project>-MASTER` is live; no outward action until the owner picks one.

## 0.2.0

Security hardening, plus fixes from the first end-to-end isolated test run.

- Treat `.claude/master.md` as untrusted: commands from it (verify checks, backup/flush, prune scripts) are shown
  and need the owner's OK before the first run; approval is the profile's hash, stored outside the repo; asked
  again when it changes; no piped downloads, no edits to shell startup files.
- Profile paths (handover, session log, memory) must resolve inside the repo, the Claude Code memory directory,
  or an owner-approved folder; never under `~/.claude/` (other than memory), `~/.ssh` or shell startup files.
- The repo and profile may tighten the safety rules, never loosen them; free-text profile fields are data.
- Relayed merge go now needs a one-time token from the worker's brief, the PR number and head SHA; the worker
  merges only its own PR with an unchanged head after checking the diff. The session name is not authentication.
- A coordinator message can only restrict a wrap; peer text is recorded as a quotation, never a rule.
- No secrets in commits, memory or the handover; staged diff is scanned before commit.
- Free dependency folders only inside a worktree the session created.
- wrapup, PAUSE on the default branch with no rules: commits to a `wip/<topic>` branch instead of stopping to
  ask or pushing work in progress to the default branch.
- master, profile drafting: values derived from the repo are proposed, not labelled "unknown".
- README: safety model, pinning a release with `#ref`.

## 0.1.0

- First generic release, extracted from a coordinator workflow originally developed on a real project.
- `master` skill: START / RUN / HANDOVER for one coordinator session per project, driven by the project's
  `.claude/master.md` profile; drafts the profile from CLAUDE.md when it is missing.
- `wrapup` skill: PAUSE / COMPLETE end-of-session ritual with push verification via `git ls-remote`, honest
  worktree teardown, a `MEMORY.md` size check and a paste-ready resume prompt. Personal steps (session log,
  topic notes, journal/todo, auto-merge, backup flush) are optional profile fields.
- `templates/master-profile.md`: the profile template.
