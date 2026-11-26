#!/usr/bin/env bash
# Tests for skills/master/bin/launch-session: who, check-wakes, restart (brief only) and close.
# Run: bash tests/launch-session.test.sh
# close runs against a FAKE process table (LAUNCH_SESSION_FAKE_PROC): nothing real is signalled and no window
# is touched. The only real processes used are this test's own shell and a `sleep`, and both must be refused.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
LS="$HERE/../skills/master/bin/launch-session"
T="$(mktemp -d "${TMPDIR:-/tmp}/pm-launch-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL - $1"; echo "       expected: [$2]"; echo "       got:      [$3]"; }
expect()   { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
contains() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "*$2*" "$3" ;; esac; }
lacks()    { case "$3" in *"$2"*) bad "$1" "no $2" "$3" ;; *) ok "$1" ;; esac; }

REPO="$T/repo"; mkdir -p "$REPO/sub"
OLD=90001 NEW=90011
OLD_START='Thu 26 Nov 10:00:00 2026'
H="$T/home"; F="$T/proc"

proc() { # proc <pid> <comm> <ppid> <tty> [cwd]
  mkdir -p "$F/$1"; printf '%s' "$2" > "$F/$1/comm"; printf '%s' "$3" > "$F/$1/ppid"; printf '%s' "$4" > "$F/$1/tty"
  printf '%s' "${5:-}" > "$F/$1/cwd"; : > "$F/$1/children"; printf 'Thu 26 Nov 09:00:00 2026' > "$F/$1/lstart"
}
session() { # session <pid> <name> <status> <startedAt> <sessionId>
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","startedAt":%s,"name":"%s","status":"%s"}' "$1" "$5" "$REPO" "$4" "$2" "$3" \
    > "$H/.claude/sessions/$1.json"
}
TR="$H/.claude/projects/-tmp-repo/sid-old.jsonl"
tr_line() { printf '%s\n' "$1" >> "$TR"; }
CREATE='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_c1","name":"CronCreate","input":{"cron":"0 9 * * *"}}]}}'
LIST_EMPTY='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_l1","name":"CronList","input":{}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_l1","type":"tool_result","content":"No scheduled jobs."}]}}'
LIST_FULL='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_l2","name":"CronList","input":{}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_l2","type":"tool_result","content":"a1b2c3d4 0 9 * * * one-shot"}]}}'
WAKE_PENDING='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_w1","name":"ScheduleWakeup","input":{"delaySeconds":1200,"prompt":"check"}}]}}'
WAKE_STOP='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_w2","name":"ScheduleWakeup","input":{"stop":true}}]}}'

fixture() { # a valid restart overlap: old copy idle in Terminal, new copy busy in another window
  rm -rf "$H" "$F"; mkdir -p "$H/.claude/sessions" "$H/.claude/projects/-tmp-repo" "$F"; : > "$F/actions.log"
  proc 89998 Terminal 1 '??'
  proc 89999 login 89998 ttys901
  proc 90000 -zsh 89999 ttys901 "$REPO"
  proc $OLD claude 90000 ttys901 "$REPO"
  printf '%s' "$OLD_START" > "$F/$OLD/lstart"
  printf 'claude --model opus --effort high -n acme-x You are a worker session reporting to acme-MASTER.\\012- Send REPORT 1' > "$F/$OLD/args"
  printf 'npm exec some-mcp\ncaffeinate\n' > "$F/$OLD/children"
  proc $NEW claude 90010 ttys902 "$REPO"
  session $OLD acme-x idle 1000 sid-old
  session $NEW acme-x busy 2000 sid-new
  printf '%s\t%s\t%s\t%s\n' "$OLD" "$OLD_START" acme-x "$REPO" > "$H/.claude/launch-session.launched"
  : > "$TR"; tr_line "$CREATE"; tr_line "$LIST_EMPTY"
}
close() { HOME="$H" LAUNCH_SESSION_FAKE_PROC="$F" LAUNCH_SESSION_CLOSE_WAIT=1 bash "$LS" close "$@" 2>&1; }
std_close() { close $OLD --expect-name acme-x --expect-cwd "$REPO" --keep-pid $NEW; }

# --- close: the happy path -----------------------------------------------------------------------------------
fixture
out=$(std_close); rc=$?
expect   "close: valid overlap exits 0"                         0 "$rc"
contains "  ...reports CLOSED with pid and tty"                  "CLOSED: old 'acme-x' pid $OLD on ttys901 (Terminal" "$out"
contains "  ...names the ledger as the evidence"                 "from the launch ledger" "$out"
contains "  ...confirms the new copy is still running"           "kept: new 'acme-x' pid $NEW is still running" "$out"
contains "  ...sent SIGTERM to the old pid"                       "kill -TERM $OLD" "$(cat "$F/actions.log")"
contains "  ...closed the Terminal window by its tty"            'tty of t is "/dev/ttys901"' "$(cat "$F/actions.log")"
lacks    "  ...never touched the new pid"                         "$NEW" "$(cat "$F/actions.log")"

fixture; rm "$H/.claude/launch-session.launched"
contains "close: pre-ledger window passes on the launcher argv"  "from the launcher command line" "$(std_close)"

fixture; : > "$TR"; tr_line "$CREATE"; tr_line "$LIST_EMPTY"; tr_line "$WAKE_PENDING"; tr_line "$WAKE_STOP"
contains "close: a loop wakeup that was stopped is fine"         "CLOSED:" "$(std_close)"

fixture; : > "$TR"
contains "close: a session that never scheduled anything is fine" "CLOSED:" "$(std_close)"

fixture; printf 'claude\nvim\n' >> "$F/$OLD/children"; proc 90002 vim 90000 ttys901 "$REPO"
out=$(std_close)
contains "close: a non-shell left on the tty keeps the window open" "window left open: still running on ttys901: vim" "$out"
lacks    "  ...and runs no AppleScript"                           "osascript" "$(cat "$F/actions.log")"

fixture; LAUNCH_SESSION_FAKE_OSA_RESULT='window left open: it has other tabs' \
  contains "close: a multi-tab Terminal window is left open"      "it has other tabs" "$(LAUNCH_SESSION_FAKE_OSA_RESULT='window left open: it has other tabs' std_close)"

# --- close: refusals (exit 3, nothing in actions.log) -----------------------------------------------------------
refused() { # refused <label> <expected text> <setup...>; runs the standard close after the setup
  local label="$1" want="$2"; shift 2
  fixture; "$@"
  local out rc; out=$(std_close); rc=$?
  if [ "$rc" = 3 ] && [ ! -s "$F/actions.log" ]; then contains "refuses: $label" "$want" "$out"
  else bad "refuses: $label" "exit 3, no actions" "rc=$rc actions=[$(cat "$F/actions.log")] $out"; fi
}
noop() { :; }
set_status_busy()  { session $OLD acme-x busy 1000 sid-old; }
set_other_name()   { session $OLD acme-y idle 1000 sid-old; }
set_other_cwd()    { printf '%s' "$T" > "$F/$OLD/cwd"; }
set_sub_cwd()      { printf '%s' "$REPO/sub" > "$F/$OLD/cwd"; }
set_not_claude()   { printf 'node' > "$F/$OLD/comm"; }
set_dead()         { rm -rf "${F:?}/$OLD"; }
set_no_record()    { rm "$H/.claude/sessions/$OLD.json"; }
set_no_ledger()    { rm "$H/.claude/launch-session.launched"; printf 'claude --model opus -n acme-x' > "$F/$OLD/args"; }
set_reused_pid()   { printf 'Fri 27 Nov 08:00:00 2026' > "$F/$OLD/lstart"; printf 'claude' > "$F/$OLD/args"; }
set_bg_shell()     { printf '/bin/zsh\n' >> "$F/$OLD/children"; }
set_cron_unlisted() { : > "$TR"; tr_line "$LIST_EMPTY"; tr_line "$CREATE"; }
set_cron_left()    { : > "$TR"; tr_line "$CREATE"; tr_line "$LIST_FULL"; }
set_wake_pending() { : > "$TR"; tr_line "$WAKE_STOP"; tr_line "$WAKE_PENDING"; }
set_no_transcript() { rm "$TR"; }
set_new_dead()     { rm -rf "${F:?}/$NEW"; }
set_new_older()    { session $NEW acme-x busy 500 sid-new; }
set_new_other()    { session $NEW acme-z busy 2000 sid-new; }
set_new_same_tty() { printf 'ttys901' > "$F/$NEW/tty"; }
set_no_tty()       { printf '??' > "$F/$OLD/tty"; }

refused "old copy busy"                     "is not idle (status 'busy')"        set_status_busy
refused "name differs"                      "is named 'acme-y', not 'acme-x'"     set_other_name
refused "cwd outside --expect-cwd"          "/repo"                        set_other_cwd
refused "not a claude process"              "is not a claude process (node)"     set_not_claude
refused "pid not running"                   "is not running"                      set_dead
refused "no session record"                 "no session record"                   set_no_record
refused "not started by the launcher"       "was not started by launch-session"   set_no_ledger
refused "pid reused since the launch"       "was not started by launch-session"   set_reused_pid
refused "background shell still running"    "still has a background shell"        set_bg_shell
refused "cron created after last CronList"  "has not run CronList since"          set_cron_unlisted
refused "CronList still shows a job"        "did not return \"No scheduled jobs\"" set_cron_left
refused "loop wakeup still pending"         "last ScheduleWakeup was not a stop"   set_wake_pending
refused "transcript missing"                "transcript for session sid-old not found" set_no_transcript
refused "new copy not running"              "the new session (pid $NEW) is not running" set_new_dead
refused "new copy is older"                 "did not start after"                 set_new_older
refused "new copy has another name"         "is not named 'acme-x'"               set_new_other
refused "new copy shares the tty"           "shares the old one's terminal"        set_new_same_tty
refused "no terminal"                       "has no terminal"                     set_no_tty

fixture; set_sub_cwd
contains "close: cwd below --expect-cwd (a worktree inside the repo) is fine" "CLOSED:" "$(std_close)"

fixture; out=$(close $NEW --expect-name acme-x --expect-cwd "$REPO" --keep-pid $NEW); rc=$?
expect   "refuses: pid equals --keep-pid (exit 3)"               3 "$rc"
contains "  ...and says never close the new copy"                "never close the new copy" "$out"
fixture; out=$(close $OLD --expect-name acme-x --keep-pid $NEW); rc=$?
expect   "refuses: missing --expect-cwd (exit 3)"                3 "$rc"
out=$(close abc --expect-name acme-x --expect-cwd "$REPO" --keep-pid $NEW); rc=$?
expect   "refuses: non-numeric pid (exit 3)"                     3 "$rc"

fixture; touch "$F/$OLD/stubborn"; out=$(std_close); rc=$?
expect   "close: still alive after SIGTERM exits 4"               4 "$rc"
contains "  ...and says it is never sent SIGKILL"                 "never sent SIGKILL" "$out"
lacks    "  ...and closed no window"                              "osascript" "$(cat "$F/actions.log")"
lacks    "  ...and sent no kill -9"                               "-9" "$(cat "$F/actions.log")"

# Real processes, real probes: both are refused before anything is sent.
out=$(HOME="$H" bash "$LS" close $$ --expect-name acme-x --expect-cwd "$REPO" --keep-pid 1 2>&1); rc=$?
expect   "real: refuses the caller's own session (exit 3)"       3 "$rc"
contains "  ...naming it as the caller's own"                    "this caller's own session" "$out"
sleep 60 & SP=$!
out=$(HOME="$H" bash "$LS" close $SP --expect-name acme-x --expect-cwd "$REPO" --keep-pid 1 2>&1); rc=$?
kill $SP 2>/dev/null; wait $SP 2>/dev/null
expect   "real: refuses a non-claude process (exit 3)"           3 "$rc"
contains "  ...naming its command"                               "is not a claude process (sleep)" "$out"

lacks "script never uses SIGKILL"  "kill -9" "$(grep -v '^#' "$LS")"
lacks "script never uses -KILL"    "-KILL" "$(grep -v '^#' "$LS")"

# --- who -------------------------------------------------------------------------------------------------------
fixture
out=$(HOME="$H" LAUNCH_SESSION_FAKE_PROC="$F" bash "$LS" who acme-x)
expect   "who: lists the old copy first"                         "pid=$OLD" "$(printf '%s\n' "$out" | head -n 1 | cut -f1)"
contains "  ...marks the ledger launch"                          "launched=yes" "$(printf '%s\n' "$out" | head -n 1)"
contains "  ...and says two share the name"                      "2 sessions share the name" "$out"
out=$(HOME="$H" LAUNCH_SESSION_FAKE_PROC="$F" bash "$LS" who nobody); rc=$?
expect   "who: no such name exits 1"                             1 "$rc"

# --- check-wakes -------------------------------------------------------------------------------------------------
note() { printf '%s\n' "$@" > "$T/note.md"; }
report() { printf '%s\n' "$@" > "$T/report.txt"; }
cw() { bash "$LS" check-wakes --note "$T/note.md" --report "$T/report.txt"; }
NOTE_TWO=('# Resume note' '' '## Scheduled wakes' '- [ ] 18:10 Europe/London | deploy run 123 finished | CronCreate one-shot "10 18 26 11 *"' \
  '- [ ] every 30 min | CI on PR 42 | Monitor until-loop on gh pr checks 42' '' '## Next step' '- carry on')

note "${NOTE_TWO[@]}"
report 'REPORT 1' 'WAKE 18:10 Europe/London | deploy run 123 finished | a1b2c3d4' 'WAKE every 30 min | CI on PR 42 | task b7'
out=$(cw); rc=$?
expect   "check-wakes: same wakes match (exit 0)"                0 "$rc"
expect   "  ...and says how many"                                "MATCH: 2 wake(s)" "$out"

report '- `WAKE   18:10 europe/london |  Deploy run 123 finished | x1`' 'WAKE every 30 min | ci on pr 42 | t2'
expect   "check-wakes: case, spacing, bullets and backticks are ignored" "MATCH: 2 wake(s)" "$(cw)"

report 'WAKE 18:10 Europe/London | deploy run 123 finished | a1b2c3d4'
out=$(cw); rc=$?
expect   "check-wakes: a missing wake is a MISMATCH (exit 1)"    1 "$rc"
contains "  ...naming the wake not re-armed"                     "in the note, not re-armed: every 30 min | ci on pr 42" "$out"

report 'WAKE 18:10 Europe/London | deploy run 123 finished | a1' 'WAKE every 30 min | CI on PR 42 | t2' 'WAKE 09:00 UTC | extra | t3'
contains "check-wakes: an extra wake is a MISMATCH"              "re-armed, not in the note: 09:00 utc | extra" "$(cw)"

report 'WAKE 18:15 Europe/London | deploy run 123 finished | a1' 'WAKE every 30 min | CI on PR 42 | t2'
contains "check-wakes: a moved time is a MISMATCH"               "MISMATCH" "$(cw)"

report 'WAKE 18:10 Europe/London | deploy run 123 finished' 'WAKE every 30 min | CI on PR 42 | t2'
out=$(cw); rc=$?
expect   "check-wakes: a WAKE line without an id is a MISMATCH (exit 1)" 1 "$rc"

note '## Scheduled wakes' '- none'; report 'WAKE none'
expect   "check-wakes: none on both sides matches"               "MATCH: no scheduled wakes on either side" "$(cw)"
note '## Scheduled wakes' 'None (this session held no timers).'; report 'WAKE none'
expect   "check-wakes: a 'None (...)' line counts as none"       "MATCH: no scheduled wakes on either side" "$(cw)"
report 'WAKE 18:10 Europe/London | deploy | a1'
contains "check-wakes: none in the note but a wake re-armed"     "MISMATCH" "$(cw)"
note "${NOTE_TWO[@]}"; report 'WAKE none'
contains "check-wakes: wakes in the note but WAKE none"          "MISMATCH" "$(cw)"
report 'REPORT 1: all re-armed'
out=$(cw); rc=$?
expect   "check-wakes: a report with no WAKE lines is a MISMATCH (exit 1)" 1 "$rc"

note '# Resume note' 'nothing about wakes'; report 'WAKE none'
out=$(cw); rc=$?
expect   "check-wakes: a note without the section exits 2"       2 "$rc"
contains "  ...and says so"                                      'no "Scheduled wakes" section' "$out"
note '## Scheduled wakes' '' '## Next'; out=$(cw); rc=$?
expect   "check-wakes: an empty section (not even none) exits 2" 2 "$rc"
out=$(bash "$LS" check-wakes --note "$T/missing.md" --report "$T/report.txt"); rc=$?
expect   "check-wakes: an unreadable note exits 2"               2 "$rc"

# --- restart (brief only; LAUNCH_SESSION_PRINT_BRIEF stops before any window opens) ------------------------------
printf 'You are a worker session reporting to acme-MASTER.\n- Ship class: normal code.\n\nTASK\nthe original task\n' > "$T/header.txt"
note "${NOTE_TWO[@]}"
rs() { HOME="$H" LAUNCH_SESSION_PRINT_BRIEF=1 bash "$LS" restart --repo "$REPO" --model m --effort high --name acme-x "$@" 2>&1; }
out=$(rs --master acme-MASTER --header "$T/header.txt" --note "$T/note.md"); rc=$?
expect   "restart: builds a brief (exit 0)"                      0 "$rc"
contains "  ...starting with the role header"                    "You are a worker session reporting to acme-MASTER." "$(printf '%s\n' "$out" | head -n 1)"
contains "  ...naming the note by its absolute path"             "Read $T/note.md end to end" "$out"
contains "  ...with the fixed WAKE format"                       "WAKE <time + zone> | <check> | <task or cron id>" "$out"
contains "  ...and the none form"                                "WAKE none" "$out"
out=$(rs --master acme-MASTER --header "$T/header.txt" --note note.md); rc=$?
expect   "restart: refuses a relative note path"                 1 "$rc"
note '# Resume note' 'no wakes section'
out=$(rs --master acme-MASTER --header "$T/header.txt" --note "$T/note.md"); rc=$?
expect   "restart: refuses a note without a Scheduled wakes checklist" 1 "$rc"
contains "  ...and says to redo the PAUSE"                       "redo its PAUSE" "$out"
note "${NOTE_TWO[@]}"; printf 'TASK\nno role header\n' > "$T/bare.txt"
out=$(rs --master acme-MASTER --header "$T/bare.txt" --note "$T/note.md"); rc=$?
expect   "restart: refuses a header without the role block"      1 "$rc"
out=$(rs --master acme-lead --header "$T/header.txt" --note "$T/note.md"); rc=$?
expect   "restart: refuses a --master that is not <project>-MASTER" 1 "$rc"
out=$(rs --master acme-MASTER --header "$T/header.txt" --note "$T/note.md" --brief "$T/header.txt"); rc=$?
expect   "restart: refuses --brief (it builds its own)"          1 "$rc"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
