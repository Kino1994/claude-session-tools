#!/usr/bin/env bash
# Ask a past session a question without modifying it (ephemeral fork, not saved).
# Usage: probe.sh <session-id> ["question"] [--persist]   (--persist saves the fork as a new session)
#
# Hardening: the probe has no tools, no MCP servers and no hooks, so it can only reason over the
# transcript. A past session may contain hostile content (web pages, issues...) and replaying it
# must not be able to read files or reach the network.
set -euo pipefail
ID="${1:?Missing session id}"; Q="${2:-Summarize in 5 lines where this session left off and what was still pending.}"
[[ "$ID" =~ ^[0-9a-fA-F-]{8,64}$ ]] || { echo "Invalid session id: $ID"; exit 1; }
F=$(ls ~/.claude/projects/*/"$ID".jsonl 2>/dev/null | xargs -r ls -t | head -1)
[[ -z "$F" ]] && { echo "Session $ID not found"; exit 1; }
DIR=$(python3 - "$F" <<'PY'
import json, re, os, sys
f = sys.argv[1]; pd = os.path.basename(os.path.dirname(f)); first = None
for l in open(f, errors='ignore'):
    try: c = json.loads(l).get('cwd')
    except Exception: continue
    if c:
        first = first or c
        if re.sub(r'[^A-Za-z0-9]', '-', c) == pd: print(c); sys.exit()
print(first or os.path.expanduser('~'))
PY
)
[[ -d "$DIR" ]] || { echo "Session folder $DIR no longer exists"; exit 1; }
EXTRA=(--no-session-persistence); [[ "${3:-}" == "--persist" ]] && EXTRA=()
cd "$DIR" && claude -p --resume "$ID" --fork-session "${EXTRA[@]}" \
  --tools "" --strict-mcp-config --settings '{"disableAllHooks": true}' \
  --permission-mode plan "$Q"
