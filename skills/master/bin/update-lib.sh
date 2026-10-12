# update-lib.sh: helpers shared by check-update and upgrade. Sourced, never run.
# Part of the project-master plugin. Works with bash 3.2 (macOS) and later.
#
# Environment overrides (mainly for tests):
#   PROJECT_MASTER_ROOT         plugin root holding .claude-plugin/plugin.json
#   PROJECT_MASTER_STATE_DIR    state dir (default ~/.claude/project-master)
#   PROJECT_MASTER_REMOTE_REPO  git URL whose tags are listed
#   PROJECT_MASTER_RAW_BASE     raw file base; files are read at <base>/<ref>/<path>
#   PROJECT_MASTER_NOW          "now" as epoch seconds

PM_SOURCE="cheeseman-sketch/project-master"        # marketplace source passed to the claude CLI
PM_MARKETPLACE="project-master"                    # marketplace name
PM_PLUGIN="project-master@project-master"          # plugin id
PM_REMOTE_REPO="${PROJECT_MASTER_REMOTE_REPO:-https://github.com/$PM_SOURCE}"
PM_RAW_BASE="${PROJECT_MASTER_RAW_BASE:-https://raw.githubusercontent.com/$PM_SOURCE}"
PM_STATE_DIR="${PROJECT_MASTER_STATE_DIR:-$HOME/.claude/project-master}"
PM_TIMEOUT=5

pm_now() { printf '%s\n' "${PROJECT_MASTER_NOW:-$(date +%s)}"; }

# Plugin root: env override, else three levels up from this file (skills/master/bin),
# else $CLAUDE_PLUGIN_ROOT, else ../.. from $CLAUDE_SKILL_DIR.
pm_root() {
  local here cand
  if [ -n "${PROJECT_MASTER_ROOT:-}" ]; then printf '%s\n' "$PROJECT_MASTER_ROOT"; return 0; fi
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  for cand in "$here/../../.." "${CLAUDE_PLUGIN_ROOT:-}" "${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}"; do
    if [ -n "$cand" ] && [ -f "$cand/.claude-plugin/plugin.json" ]; then
      (cd "$cand" && pwd -P); return 0
    fi
  done
  return 1
}

pm_is_semver() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }

# Installed version from the plugin's own manifest.
pm_installed_version() {
  local root v
  root="$(pm_root)" || return 1
  v="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -n 1)"
  pm_is_semver "$v" || return 1
  printf '%s\n' "$v"
}

# pm_vercmp a b -> prints -1, 0 or 1. Both must be X.Y.Z.
pm_vercmp() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<EOF
$1
EOF
  IFS=. read -r b1 b2 b3 <<EOF
$2
EOF
  for pair in "$a1 $b1" "$a2 $b2" "$a3 $b3"; do
    set -- $pair
    if [ "$((10#$1))" -lt "$((10#$2))" ]; then echo -1; return 0; fi
    if [ "$((10#$1))" -gt "$((10#$2))" ]; then echo 1; return 0; fi
  done
  echo 0
}

# Run a command with a hard timeout (no coreutils `timeout` on macOS).
# stdout goes to the file named in $1; the exit status is the command's, or 124 on timeout.
pm_run_timeout() {
  local out="$1" pid watcher rc; shift
  "$@" >"$out" 2>/dev/null &
  pid=$!
  ( sleep "$PM_TIMEOUT"; kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  watcher=$!
  rc=0; wait "$pid" 2>/dev/null || rc=$?
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  [ "$rc" -eq 143 ] && rc=124
  return "$rc"
}

# Strip any user:token@ from a URL before it is printed or cached.
pm_display_url() { printf '%s' "$1" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#'; }

# Newest X.Y.Z tag (as "X.Y.Z") from `git ls-remote`. No auth, no prompts.
# Returns 2 on a timeout (the caller then skips the fallback, keeping the total wait at ~5 s).
pm_latest_from_tags() {
  local tmp rc v
  tmp="$(mktemp "${TMPDIR:-/tmp}/pm-tags.XXXXXX")"
  rc=0
  pm_run_timeout "$tmp" env GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false \
    git -c credential.helper= -c core.askPass=/bin/false ls-remote --tags --refs "$PM_REMOTE_REPO" || rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$tmp"; [ "$rc" -eq 124 ] && return 2; return 1; fi
  v="$(sed -n 's#.*refs/tags/v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$#\1#p' "$tmp" \
        | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
  rm -f "$tmp"
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

# Fallback: version field of plugin.json on the default branch.
pm_latest_from_raw() {
  local tmp v
  command -v curl >/dev/null 2>&1 || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/pm-raw.XXXXXX")"
  if ! pm_run_timeout "$tmp" curl -sfL --max-time "$PM_TIMEOUT" "$PM_RAW_BASE/main/.claude-plugin/plugin.json"; then
    rm -f "$tmp"; return 1
  fi
  v="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp" | head -n 1)"
  rm -f "$tmp"
  pm_is_semver "$v" || return 1
  printf '%s\n' "$v"
}

# Remove control characters (terminal escapes) from untrusted text; keep tab and newline.
pm_sanitize() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }

# pm_changelog_sections <file> <from> <to>: sections with from < version <= to, newest first as written.
pm_changelog_sections() {
  local file="$1" from="$2" to="$3" line ver keep=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "## "*)
        ver="$(printf '%s\n' "${line#\#\# }" | sed -n 's/^v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
        keep=0
        if [ -n "$ver" ] && [ "$(pm_vercmp "$ver" "$from")" = 1 ] && [ "$(pm_vercmp "$ver" "$to")" != 1 ]; then
          keep=1
        fi ;;
      "# "*) keep=0 ;;
    esac
    [ "$keep" = 1 ] && printf '%s\n' "$line"
  done < "$file"
  return 0
}
