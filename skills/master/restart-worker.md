# Restarting a long-running worker

The detail behind SKILL.md § Restarting a long-running worker. (2026-11-26, found when a MASTER restarted two
long-running workers by hand. Each held scheduled wakes, meaning timers, one-shot crons or background
until-loops that live only inside that session. Nothing in the plugin made the worker write them down,
checked that the new session re-armed them, or closed the old window.)

**When:** a worker's REPORT carries `RESTART DUE` (the plugin's hook adds it after 2 compactions or 2 days, as
set in the profile), or the owner asks. A worker with no wakes and no long future can simply be closed out
or paused instead. The restart reuses the worker's original model, effort and merge class, so it needs no new
launch question. Tell the owner one line: "restarting <name> (restart due)". A "can merge" worker gets a
fresh merge token: record it in the handover file and retire the old one.

`launch-session` below means `bash "${CLAUDE_SKILL_DIR}/bin/launch-session"`.

## 1. Pause the old copy

Send the worker:

> "Restart due. Run /wrapup in PAUSE mode. Your resume note must have a `## Scheduled wakes` checklist, one
> line per wake as `- [ ] <time + zone> | <what it checks> | <how to re-arm>`, or `- none`. Then cancel every
> wake you hold (CronDelete, TaskStop, stop any ScheduleWakeup loop), run CronList and confirm it shows no
> jobs, and reply with the absolute path of the resume note, 'wakes cancelled', and whether your worktree is
> clean and pushed."

A wrap message from MASTER only restricts (PAUSE, no PR, arm nothing, keep the worktree), so this is within
what a coordinator may ask. Wait for the reply; it is step 4's condition (b).

## 2. Relaunch under the same name

Write the worker's role header (the brief block from SKILL.md with the original ship class, and the new merge
token line for "can merge") to a scratchpad file, then:

```bash
launch-session restart --repo <abs repo root> --model <m> --effort <e> --name <same name> \
  --master <project>-MASTER --header <header file> --note <abs resume note>
```

It refuses a note with no usable `Scheduled wakes` checklist. The brief it builds tells the new session to read
the note, re-arm every wake exactly (a wake already past runs now, with id `ran-now`), then send REPORT 1 with
one line per wake:

```text
WAKE <time + zone> | <check> | <task or cron id>
```

or the single line `WAKE none`.

## 3. Compare the wakes

Save the new session's REPORT 1 text to a scratchpad file and run
`launch-session check-wakes --note <note> --report <file>`. It compares time and check (ignoring case and
spacing) and prints `MATCH` or `MISMATCH` with the lines that differ. **On a mismatch, stop:** tell the owner
what is missing or extra, and close nothing. The old copy has already cancelled its wakes, so a missing wake
fires nowhere until it is fixed.

## 4. Close the old copy (the only window MASTER ever closes)

Close it only when both hold:
- **(a)** the new copy is confirmed started: it is listed by `ListAgents` and its REPORT 1 arrived with wakes
  that MATCH;
- **(b)** the old copy reported its PAUSE done, with wakes cancelled and its worktree clean and pushed (or its
  branch merged).

Two sessions share the name during the overlap, so pick by pid, never by name. `launch-session who <name>`
lists both oldest first, with pid, status, tty and cwd. The old copy is the earlier one, and its pid is also in
its socket path (`/tmp/cc-socks/<pid>.sock`) in the `ListAgents` row. Then:

```bash
launch-session close <old pid> --expect-name <name> --expect-cwd <abs repo root> --keep-pid <new pid>
```

It refuses, and touches nothing, unless all of these hold:
- the old pid is alive, is a claude process and is not MASTER's own session;
- its session record names it `<name>` and says it is idle;
- its cwd is the repo root or below it;
- the launcher started it (the launch ledger, or the launcher's command line for windows opened before 0.3.0);
- it has no background shell left, and its transcript shows no cron or loop wake still pending;
- the new pid is a live, newer claude session with the same name, on another terminal.

The script cannot see the worktree, so condition (b)'s "clean and pushed" is MASTER's own check (`git -C
<worktree> status`, `git ls-remote`). An MCP server that the worker's config starts through a shell
(`sh -c ...`) looks like a background shell, so close refuses; that is the safe direction.

Then it sends SIGTERM, never SIGKILL, waits for the exit and closes the window by its tty. That is Terminal
or iTerm by AppleScript; Ghostty closes its own window when the command exits. A window that still runs
anything but a shell is left open. Last, it confirms the new pid is still running.

- **Refused (exit 3) or still running (exit 4):** fall back to the old way. Tell the owner "safe to close:
  <name>, the older window (pid <old pid>, <tty>)" and leave it to them.
- **Exit 5 (the new copy is gone):** tell the owner at once.
- **Closed:** tell the owner one line: "restarted <name>: new pid <new>, <n> wakes re-armed; closed the old
  window (pid <old>, <tty>)".

Never close a session MASTER did not launch, and never close anything outside a restart's step 4.
