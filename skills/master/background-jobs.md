# Checking a session's own background jobs

Used by § HANDOVER step 1 (the "first jobs" line) and by wrapup's PAUSE step 6.6. (2026-11-26, found when a
MASTER wrote "Background jobs: none" in its handover while a stuck wait loop, an until-loop polling a task's
output file with `sleep 5`, was still running under it. The owner's rule: check what's running before
saying it is safe to restart.)

**A "none" written from memory is not a check.** Before saying a session is safe to hand over, pause or
restart, look at what is actually running.

1. **Your own processes:** `bash "${CLAUDE_SKILL_DIR}/bin/launch-session" children self` (from wrapup:
   `${CLAUDE_PLUGIN_ROOT}/skills/master/bin/launch-session`). It finds this session's claude process and lists
   its live children:
   - `SHELL pid=… up=…  <command>` is a background task, a Monitor or a wait loop, with what it runs now
     (`runs: sleep …`). The shell running the check itself is left out.
   - `other pid=…` is usually an MCP server or a helper. Leave those alone.
   It exits 1 if any shell is running. The command text is cut to 120 characters. Never copy one that holds a
   secret into the handover.
2. **Your tool-level jobs:** the background tasks and Monitors you started, CronList, and any self-paced
   loop (ScheduleWakeup).
3. **Decide for each one:**
   - **Stop it** (TaskStop, CronDelete, or ScheduleWakeup `stop: true`) if its question is already answered,
     or it is a stuck wait: it is polling for something that will never come, or for a task that already
     finished.
   - **Otherwise record it.** In a handover that is a first job: the question, and how the next session
     re-checks it. In a PAUSE it is a `Scheduled wakes` line.
4. **Re-run the check.** The handover's background-jobs line is what this second run shows plus what you
   recorded, never what you remember. Only then tell the owner it is safe to restart or close.
