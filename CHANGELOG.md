# Changelog

All notable changes to this plugin are recorded here. Versions follow `version` in `.claude-plugin/plugin.json`.

## 0.1.0 (unreleased)

- First generic release, extracted from a coordinator workflow originally developed on a real project.
- `master` skill: START / RUN / HANDOVER for one coordinator session per project, driven by the project's
  `.claude/master.md` profile; drafts the profile from CLAUDE.md when it is missing.
- `wrapup` skill: PAUSE / COMPLETE end-of-session ritual with push verification via `git ls-remote`, honest
  worktree teardown, a `MEMORY.md` size check and a paste-ready resume prompt. Personal steps (session log,
  topic notes, journal/todo, auto-merge, backup flush) are optional profile fields.
- `templates/master-profile.md`: the profile template.
