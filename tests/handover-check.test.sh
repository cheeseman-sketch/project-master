#!/usr/bin/env bash
# Tests for hooks/handover-check (SessionStart compact|resume hook).
# Run: bash tests/handover-check.test.sh
# Builds fake transcripts in a temp dir; the clock is pinned with HANDOVER_CHECK_NOW.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="$HERE/../hooks/handover-check"
T="$(mktemp -d "${TMPDIR:-/tmp}/pm-handover-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL - $1"; echo "       expected: [$2]"; echo "       got:      [$3]"; }
expect()   { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
contains() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "*$2*" "$3" ;; esac; }

START='2026-10-21T10:01:30.142Z'
SAME_DAY_NOW=$(( $(date -j -u -f '%Y-%m-%dT%H:%M:%S' '2026-10-21T10:01:30' +%s 2>/dev/null \
  || date -u -d "$START" +%s) + 3600 ))
NINE_DAYS_NOW=$(( SAME_DAY_NOW + 9 * 86400 ))

line_first()    { printf '{"type":"user","message":{"role":"user","content":"hi"},"timestamp":"%s"}\n' "$START"; }
line_boundary() { printf '{"parentUuid":null,"type":"system","subtype":"compact_boundary","content":"Conversation compacted","timestamp":"2026-10-21T18:50:43.084Z"}\n'; }
line_after()    { printf '{"type":"user","message":{"role":"user","content":"more"},"timestamp":"2026-10-21T11:00:00.000Z"}\n'; }
line_master_cmd() { printf '%s\n' '{"type":"user","message":{"role":"user","content":"<command-message>project-master:master</command-message>\n<command-name>/project-master:master</command-name>\n<command-args>start</command-args>"},"timestamp":"2026-10-21T10:02:00.000Z"}'; }
line_master_skill() { printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"master","args":"acme start"}}]}}'; }
# A worker that grepped a MASTER transcript: the same text, JSON-escaped inside a tool result.
line_quoted_master() { printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"{\"role\":\"user\",\"content\":\"<command-message>project-master:master</command-message>\\n<command-name>/project-master:master</command-name>\" \"name\":\"Skill\",\"input\":{\"skill\":\"master\"}"}]}}'; }

# mk <name> <title or -> <lines...>: writes $T/<name>.jsonl and, unless title is "-", custom-title.json
mk() {
  local name="$1" title="$2"; shift 2
  local f="$T/$name.jsonl"; : > "$f"
  for gen in "$@"; do "$gen" >> "$f"; done
  if [ "$title" != "-" ]; then mkdir -p "$T/$name"; printf '{"customTitle":"%s"}' "$title" > "$T/$name/custom-title.json"; fi
  echo "$f"
}
run() { printf '{"session_id":"x","transcript_path":"%s","cwd":"/tmp","hook_event_name":"SessionStart","source":"%s"}' "$1" "${2:-compact}" \
  | HANDOVER_CHECK_NOW="${3:-$SAME_DAY_NOW}" bash "$HOOK"; }

# --- fires ----------------------------------------------------------------------------------------------
f=$(mk master2 acme-MASTER line_first line_boundary line_boundary)
out=$(run "$f")
contains "MASTER by title, 2 compactions: fires"            '"additionalContext":"MASTER handover check: compaction 2' "$out"
contains "  ...and says to tell the owner now"               'Tell the owner now and recommend a handover' "$out"
contains "  ...and names the start date"                     'since 2026-10-21' "$out"
echo "$out" | (command -v jq >/dev/null && jq -e .hookSpecificOutput.additionalContext >/dev/null || cat >/dev/null) \
  && ok "  ...and prints valid JSON" || bad "  ...and prints valid JSON" "valid" "$out"

f=$(mk master11 acme-MASTER line_first line_boundary line_boundary line_boundary line_boundary line_boundary \
  line_boundary line_boundary line_boundary line_boundary line_boundary line_boundary)
contains "11 compactions over 9 days: counts and age"        'compaction 11, session running 9 days (since 2026-10-21)' "$(run "$f" compact "$NINE_DAYS_NOW")"

f=$(mk cmd2 - line_first line_master_cmd line_boundary line_boundary)
contains "no title, /project-master:master invoked: fires"   'compaction 2' "$(run "$f")"

f=$(mk skill2 - line_first line_master_skill line_boundary line_boundary)
contains "no title, Skill tool master invoked: fires"         'compaction 2' "$(run "$f")"

# The harness writes a compaction's boundary only AFTER the compact hook has run, so on source=compact the
# hook counts the compaction in progress too (unless its boundary is already at the end of the file).
f=$(mk inprogress acme-MASTER line_first line_boundary line_after line_after line_after line_after)
contains "compact, 1 earlier boundary not at tail: counts 2"  'compaction 2, session' "$(run "$f" compact)"
contains "resume, same file: counts 1 (no compaction running)" 'compaction 1, session' "$(run "$f" resume)"
f=$(mk firstcompact acme-MASTER line_first line_after line_after line_after line_after)
contains "first compact, no boundary written yet: counts 1"   'compaction 1, session' "$(run "$f" compact)"
f=$(mk nocompact acme-MASTER line_first line_after line_after line_after)
expect "resume, never compacted: silent"                      "" "$(run "$f" resume)"

f=$(mk oldday acme-MASTER line_first line_boundary)
contains "1 compaction but started an earlier day: due"       'Tell the owner now' "$(run "$f" compact "$NINE_DAYS_NOW")"

f=$(mk resumed acme-MASTER line_first line_boundary line_boundary)
contains "resume source is noted"                             '(Session resumed.)' "$(run "$f" resume)"

f=$(mk one acme-MASTER line_first line_boundary)
contains "1 compaction same day: soft reminder, not due"      'Not due yet' "$(run "$f")"

# --- silent ---------------------------------------------------------------------------------------------
f=$(mk worker acme-share-feature line_first line_boundary line_boundary line_boundary)
expect "non-MASTER title, 3 compactions: silent"              "" "$(run "$f")"

f=$(mk quoted acme-master-fix line_first line_quoted_master line_boundary line_boundary)
expect "worker quoting master lines in tool output: silent"   "" "$(run "$f")"

f=$(mk lower acme-master line_first line_boundary line_boundary)
expect "title ending lowercase -master is not MASTER: silent" "" "$(run "$f")"

f=$(mk fresh acme-MASTER line_first)
expect "MASTER resumed, no compaction, same day: silent"      "" "$(run "$f" resume)"

expect "missing transcript: silent"                           "" "$(run "$T/nope.jsonl")"
expect "garbage payload: silent"                              "" "$(printf 'not json' | bash "$HOOK")"
printf 'not json' | bash "$HOOK" >/dev/null; expect "garbage payload: exit 0" "0" "$?"
expect "empty payload: silent"                                "" "$(bash "$HOOK" < /dev/null)"

# --- plugin wiring ---------------------------------------------------------------------------------------
HJ="$HERE/../hooks/hooks.json"
if command -v jq >/dev/null; then
  expect "hooks.json wires SessionStart compact|resume" "compact|resume" "$(jq -r '.hooks.SessionStart[0].matcher' "$HJ")"
else
  contains "hooks.json wires SessionStart compact|resume" '"matcher": "compact|resume"' "$(cat "$HJ")"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
