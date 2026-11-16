#!/usr/bin/env bash
# Start a background Claude Code session on this machine with Remote Control,
# so it can be used from the phone / claude.ai.
# Usage: launch.sh <folder> ["initial prompt"] [--name NAME] [--bypass] [--force]
#
# Environment:
#   SESSION_TOOLS_ALLOWED_ROOTS  colon-separated folders new sessions may run under (default: $HOME)
#   SESSION_TOOLS_MAX_DEPTH      how many levels of spawned-by-new-session are allowed (default: 1,
#                                i.e. a session started by this script cannot start another one)
set -euo pipefail
DIR="$(realpath -m "${1:?Missing folder}")"; shift
PROMPT=""; NAME=""; FORCE=0; BYPASS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:?--name needs a value}"; shift 2;;
    --force) FORCE=1; shift;;
    --bypass) BYPASS=1; shift;;
    *) PROMPT="$1"; shift;;
  esac
done
NAME="${NAME:-$(basename "$DIR")}"

# 1. No chains: a session spawned by this script carries SESSION_TOOLS_DEPTH.
DEPTH="${SESSION_TOOLS_DEPTH:-0}"; MAX_DEPTH="${SESSION_TOOLS_MAX_DEPTH:-1}"
if (( DEPTH >= MAX_DEPTH )); then
  echo "ABORT: this session was itself started by new-session (depth $DEPTH, max $MAX_DEPTH)."
  echo "Start new sessions from a session you opened yourself, or raise SESSION_TOOLS_MAX_DEPTH."
  exit 4
fi

# 2. Allowed roots (resolved, so symlinks can't escape).
ROOTS="${SESSION_TOOLS_ALLOWED_ROOTS:-$HOME}"; OK_ROOT=0
IFS=':' read -ra RLIST <<< "$ROOTS"
for r in "${RLIST[@]}"; do
  [[ -z "$r" ]] && continue
  r="$(realpath -m "${r/#\~/$HOME}")"
  case "$DIR/" in "$r"/*) OK_ROOT=1; break;; esac
done
(( OK_ROOT )) || { echo "ABORT: $DIR is outside the allowed roots ($ROOTS)"; exit 2; }
mkdir -p "$DIR"

# 3. Review project-supplied Claude config before granting trust (only when not trusted yet).
ALREADY_TRUSTED=$(python3 - "$DIR" <<'PY'
import json, os, sys
f = os.path.expanduser('~/.claude.json')
try: c = json.load(open(f))
except Exception: c = {}
print(1 if c.get('projects', {}).get(sys.argv[1], {}).get('hasTrustDialogAccepted') else 0)
PY
)
if [[ $ALREADY_TRUSTED -eq 0 && $FORCE -eq 0 ]]; then
  # Code-executing or permission-changing config, then instruction files (prompt-injection surface).
  RISKY=$(cd "$DIR" && ls -d .claude/settings.json .claude/settings.local.json .claude/hooks .mcp.json \
           .claude/agents .claude/skills .claude/commands .claude/CLAUDE.md CLAUDE.md CLAUDE.local.md 2>/dev/null || true)
  if [[ -n "$RISKY" ]]; then
    echo "REVIEW: $DIR is not trusted yet and ships Claude config that would load once it is:"
    echo "$RISKY" | sed 's/^/  - /'
    echo "Trust is permanent for this path: later changes (e.g. git pull) load without review."
    echo "Show these to the user and relaunch with --force only after they confirm."
    exit 3
  fi
fi

# 4. Grant trust (`claude --bg` refuses untrusted folders).
# NOTE: ~/.claude.json is an internal, undocumented file. A backup is kept; file mode is preserved.
python3 - "$DIR" <<'PY'
import json, sys, os, shutil, stat
f = os.path.expanduser('~/.claude.json'); d = sys.argv[1]
mode = stat.S_IMODE(os.stat(f).st_mode) if os.path.exists(f) else 0o600
c = json.load(open(f)) if os.path.exists(f) else {}
p = c.setdefault('projects', {}).setdefault(d, {})
if p.get('hasTrustDialogAccepted') and p.get('hasCompletedProjectOnboarding'): sys.exit()
if os.path.exists(f):
    shutil.copy2(f, f + '.bak'); os.chmod(f + '.bak', mode)
p['hasTrustDialogAccepted'] = True; p['hasCompletedProjectOnboarding'] = True
fd = os.open(f + '.tmp', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
with os.fdopen(fd, 'w') as fh: json.dump(c, fh, indent=2)
os.chmod(f + '.tmp', mode)
os.replace(f + '.tmp', f)
PY

# 5. Launch.
cd "$DIR"
ARGS=(--bg --remote-control "$NAME")
[[ $BYPASS -eq 1 ]] && ARGS+=(--permission-mode bypassPermissions)
[[ -n "$PROMPT" ]] && ARGS+=("$PROMPT")
OUT=$(SESSION_TOOLS_DEPTH=$((DEPTH + 1)) claude "${ARGS[@]}" 2>&1)
ID=$(echo "$OUT" | grep -oE 'backgrounded · [[:alnum:]]+' | awk '{print $3}' || true)
[[ -z "$ID" ]] && { echo "FAILED to launch:"; echo "$OUT"; exit 1; }

# Wait for Remote Control to publish the session URL
URL=""
for _ in $(seq 1 20); do
  URL=$(claude logs "$ID" 2>/dev/null | grep -oE 'https://claude\.ai/code/session_[[:alnum:]_]+' | head -1 || true)
  [[ -n "$URL" ]] && break; sleep 1
done
echo "OK id=$ID name=$NAME folder=$DIR depth=$((DEPTH + 1))"
echo "Remote Control: ${URL:-(still connecting; it will show up in the app session list as '$NAME')}"
echo "On this machine: claude attach $ID | claude logs $ID | claude stop $ID"
