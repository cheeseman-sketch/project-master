#!/usr/bin/env bash
# Tests for skills/master/bin/check-update and skills/master/bin/upgrade.
# Run: bash tests/update-check.test.sh
# Uses a local bare git repo as the fake remote and a temp state dir. No network, and `upgrade apply` only
# ever runs in dry-run mode.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
BIN="$HERE/../skills/master/bin"
T="$(mktemp -d "${TMPDIR:-/tmp}/pm-update-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL - $1"; echo "       expected: [$2]"; echo "       got:      [$3]"; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

# --- fake remote: bare repo with tags v0.2.4 and v0.2.5 ---------------------------------------------------
CHANGELOG_TEXT='# Changelog

## 0.2.5

Update check and guided upgrade.

- New check-update script.

## 0.2.4

- Older change.
'
work="$T/work"; mkdir -p "$work/.claude-plugin"
git -C "$work" init -q
git -C "$work" config user.email t@example.invalid; git -C "$work" config user.name test
printf '%s' "$CHANGELOG_TEXT" | sed '/^## 0.2.5/,/^## 0.2.4/{/^## 0.2.4/!d;}' > "$work/CHANGELOG.md"
printf '{ "name": "project-master", "version": "0.2.4" }\n' > "$work/.claude-plugin/plugin.json"
git -C "$work" add -A; git -C "$work" commit -qm v0.2.4; git -C "$work" tag v0.2.4
printf '%s' "$CHANGELOG_TEXT" > "$work/CHANGELOG.md"
printf '{ "name": "project-master", "version": "0.2.5" }\n' > "$work/.claude-plugin/plugin.json"
git -C "$work" add -A; git -C "$work" commit -qm v0.2.5; git -C "$work" tag v0.2.5
git -C "$work" tag not-a-version
git clone -q --bare "$work" "$T/remote.git"

# raw-file layout for the changelog fetch (<base>/<ref>/<path>), served over file://
mkdir -p "$T/raw/v0.2.5"; git -C "$T/remote.git" show v0.2.5:CHANGELOG.md > "$T/raw/v0.2.5/CHANGELOG.md"

# --- fake installed plugin ---------------------------------------------------------------------------------
install_version() {
  mkdir -p "$T/plugin/.claude-plugin"
  printf '{\n  "name": "project-master",\n  "version": "%s"\n}\n' "$1" > "$T/plugin/.claude-plugin/plugin.json"
  printf '%s' "$CHANGELOG_TEXT" > "$T/plugin/CHANGELOG.md"
}

NOW=1800000000
reset_state() { rm -rf "$T/state"; }
check() { # extra env as args
  env PROJECT_MASTER_ROOT="$T/plugin" PROJECT_MASTER_STATE_DIR="$T/state" \
      PROJECT_MASTER_REMOTE_REPO="$T/remote.git" PROJECT_MASTER_RAW_BASE="file://$T/no-such-raw" \
      PROJECT_MASTER_NOW="$NOW" PROJECT_MASTER_UPDATE_CHECK=on "$@" bash "$BIN/check-update"
}
upg() {
  env PROJECT_MASTER_ROOT="$T/plugin" PROJECT_MASTER_STATE_DIR="$T/state" \
      PROJECT_MASTER_REMOTE_REPO="$T/remote.git" PROJECT_MASTER_RAW_BASE="file://$T/raw" \
      PROJECT_MASTER_NOW="$NOW" bash "$BIN/upgrade" "$@"
}
UNREACHABLE="$T/no-such-remote.git"

# 1. older installed -> UPGRADE_AVAILABLE
install_version 0.2.4; reset_state
expect "older installed version -> UPGRADE_AVAILABLE" "UPGRADE_AVAILABLE 0.2.4 0.2.5" "$(check)"

# 2. equal -> silent
install_version 0.2.5; reset_state
expect "equal version -> silent" "" "$(check)"

# 3. cached result within 24h -> no network (remote unreachable, answer still from cache)
install_version 0.2.4; reset_state
check >/dev/null
expect "cached result used within TTL (unreachable remote)" "UPGRADE_AVAILABLE 0.2.4 0.2.5" \
  "$(check PROJECT_MASTER_REMOTE_REPO="$UNREACHABLE")"
expect "cache expires after 24h -> network again (unreachable -> CHECK_FAILED)" "CHECK_FAILED" \
  "$(check PROJECT_MASTER_REMOTE_REPO="$UNREACHABLE" PROJECT_MASTER_NOW=$((NOW + 86401)) | cut -d' ' -f1)"

# 4. unreachable remote -> CHECK_FAILED, cached short (1h), never as up to date
install_version 0.2.4; reset_state
out="$(check PROJECT_MASTER_REMOTE_REPO="$UNREACHABLE")"
expect "unreachable remote -> CHECK_FAILED" "CHECK_FAILED" "${out%% *}"
expect "failure is cached as FAIL" "FAIL" "$(cut -d' ' -f2 "$T/state/last-check")"
expect "cached failure replayed within 1h (even if the remote is back)" "CHECK_FAILED" "$(check | cut -d' ' -f1)"
expect "failure cache expires after 1h -> real check" "UPGRADE_AVAILABLE 0.2.4 0.2.5" \
  "$(check PROJECT_MASTER_NOW=$((NOW + 3601)))"

# 5. snooze -> silent until it expires; a newer version is not covered
install_version 0.2.4; reset_state
check >/dev/null
upg snooze >/dev/null
expect "snooze records the latest version" "0.2.5" "$(cut -d' ' -f1 "$T/state/snoozed")"
expect "snoozed -> silent" "" "$(check)"
expect "snoozed -> still silent after 6 days" "" "$(check PROJECT_MASTER_NOW=$((NOW + 6 * 86400)))"
expect "snooze expires after 7 days" "UPGRADE_AVAILABLE 0.2.4 0.2.5" \
  "$(check PROJECT_MASTER_NOW=$((NOW + 7 * 86400 + 1)))"
printf '0.2.3 %s\n' "$NOW" > "$T/state/snoozed"
expect "snooze of an older version does not hide a newer one" "UPGRADE_AVAILABLE 0.2.4 0.2.5" \
  "$(check PROJECT_MASTER_NOW=$((NOW + 1)))"

# 6. disabled -> silent (file and env)
install_version 0.2.4; reset_state
upg disable >/dev/null
expect "disabled file -> silent" "" "$(check)"
upg enable >/dev/null
expect "enable -> offered again" "UPGRADE_AVAILABLE 0.2.4 0.2.5" "$(check)"
expect "env PROJECT_MASTER_UPDATE_CHECK=off -> silent" "" "$(check PROJECT_MASTER_UPDATE_CHECK=off)"

# 7. JUST_UPGRADED marker -> printed once (only once the new version is running)
install_version 0.2.4; reset_state; mkdir -p "$T/state"
printf '0.2.4 0.2.5\n' > "$T/state/just-upgraded"
expect "marker not shown before restart (old version still running)" "UPGRADE_AVAILABLE 0.2.4 0.2.5" "$(check)"
install_version 0.2.5
expect "marker printed after restart" "JUST_UPGRADED 0.2.4 0.2.5" "$(check)"
expect "marker printed only once" "" "$(check)"
expect "summary line for the new version" "Update check and guided upgrade." "$(upg summary 0.2.5)"

# 8. upgrade changes 0.2.4 0.2.5 -> only the 0.2.5 section (read from the tag's changelog over file://)
out="$(upg changes 0.2.4 0.2.5)"
if printf '%s\n' "$out" | grep -q '^## 0.2.5' && printf '%s\n' "$out" | grep -q 'New check-update script' \
   && ! printf '%s\n' "$out" | grep -q -e '0.2.4$' -e 'Older change' -e '^# Changelog'; then
  ok "changes 0.2.4 0.2.5 prints only the 0.2.5 section"
else
  bad "changes 0.2.4 0.2.5 prints only the 0.2.5 section" "## 0.2.5 section only" "$out"
fi
printf '## 0.2.5\n\n- evil \033]0;title\007 text\n' > "$T/evil.md"
out="$(PROJECT_MASTER_CHANGELOG_FILE="$T/evil.md" upg changes 0.2.4 0.2.5)"
if printf '%s' "$out" | LC_ALL=C grep -q "$(printf '\033')"; then
  bad "control characters are stripped from release notes" "no ESC byte" "$out"
else ok "control characters are stripped from release notes"; fi

# 9. upgrade apply in dry-run -> exact commands, nothing run, no marker written
install_version 0.2.4; reset_state
out="$(PROJECT_MASTER_DRY_RUN=1 upg apply 0.2.5 | grep '^+ ')"
want='+ claude plugin marketplace remove project-master
+ claude plugin marketplace add cheeseman-sketch/project-master#v0.2.5 --scope user
+ claude plugin install project-master@project-master --scope user'
expect "apply (dry run) prints the exact CLI sequence" "$want" "$out"
expect "apply (dry run) writes no marker" "no" "$([ -e "$T/state/just-upgraded" ] && echo yes || echo no)"
expect "apply refuses a version that is not newer" "1" \
  "$(PROJECT_MASTER_DRY_RUN=1 upg apply 0.2.4 >/dev/null 2>&1; echo $?)"
expect "apply refuses a non-version argument" "1" \
  "$(PROJECT_MASTER_DRY_RUN=1 upg apply '0.2.5;rm' >/dev/null 2>&1; echo $?)"

# 10. robustness: unreadable manifest -> CHECK_FAILED, exit 0
reset_state
out="$(env PROJECT_MASTER_ROOT="$T/nowhere" PROJECT_MASTER_STATE_DIR="$T/state" bash "$BIN/check-update"; echo "rc=$?")"
expect "missing manifest -> CHECK_FAILED and exit 0" "CHECK_FAILED rc=0" "$(printf '%s' "$out" | sed -n '1s/ .*//p;$p' | paste -sd' ' -)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
