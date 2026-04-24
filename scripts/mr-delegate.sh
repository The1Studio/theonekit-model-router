#!/bin/bash
# t1k-origin: kit=theonekit-model-router | repo=The1Studio/theonekit-model-router | module=null | protected=false
# model-router delegate script (mr-delegate.sh)
# Usage: mr-delegate.sh <role> "<task>" --provider <provider> --model <model>
#
# Spawns a Claude Code session routed to a cheaper model via ANTHROPIC_BASE_URL.
# Supported providers:
#   - opencode-go: local oc-go-cc proxy (GLM, Kimi, Qwen, MiMo, MiniMax)
#   - kimi: via ccs.the1studio.org auth proxy (Kimi K2/K2.5/K2.6)
#   - codex: via ccs.the1studio.org auth proxy (GPT-5.1, o3)
#
# Claude (main session) reads model-capabilities.md to choose the best model.
# This script is a dumb executor — it does NOT choose models.
#
# SSOT: role → safety limits (MODE/TURNS/BUDGET) lives HERE.
# SSOT: provider → endpoint resolution lives HERE.

set -euo pipefail

# ─── P0: Recursive delegation guard ───
if [[ "${MR_SPAWNED:-}" == "1" ]]; then
  echo "ERROR: Recursive delegation detected. Spawned sessions cannot delegate." >&2
  exit 1
fi

ROLE="${1:?Usage: mr-delegate.sh <role> \"<task>\" --provider <provider> --model <model>}"
TASK="${2:?Missing task description}"
shift 2

# ─── Parse flags ───
PROVIDER=""
MODEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) PROVIDER="$2"; shift 2 ;;
    --profile)
      # Backward compat alias (deprecated)
      echo "[mr] WARNING: --profile is deprecated, use --provider" >&2
      PROVIDER="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    *) echo "[mr] WARNING: Unrecognized flag '$1', ignoring" >&2; shift ;;
  esac
done

# ─── Validate required args ───
if [[ -z "$PROVIDER" ]]; then
  echo "ERROR: --provider is required. Available: opencode-go, kimi, codex" >&2
  echo "Hint: Claude selects the provider based on .claude/model-capabilities.md" >&2
  exit 1
fi
if [[ -z "$MODEL" ]]; then
  echo "ERROR: --model is required. See .claude/model-capabilities.md for options." >&2
  exit 1
fi

# ─── Role → safety limits (MODE/TURNS/BUDGET only, no model) ───
case "$ROLE" in
  mr-explorer-fast)  MODE="plan";        TURNS=30; BUDGET="5.00" ;;
  mr-doc-scout)      MODE="plan";        TURNS=25; BUDGET="5.00" ;;
  mr-doc-writer)     MODE="acceptEdits"; TURNS=50; BUDGET="10.00" ;;
  mr-coder-cheap)    MODE="acceptEdits"; TURNS=50; BUDGET="10.00" ;;
  mr-reviewer-deep)  MODE="plan";        TURNS=40; BUDGET="10.00" ;;
  mr-tester)         MODE="plan";        TURNS=30; BUDGET="5.00" ;;
  *)
    echo "Unknown role: $ROLE" >&2
    echo "Available: mr-explorer-fast, mr-doc-scout, mr-doc-writer, mr-coder-cheap, mr-reviewer-deep, mr-tester" >&2
    exit 1
    ;;
esac

# ─── Helper: resolve GitHub token for remote providers ───
# Side-effect: sets MR_GH_TOKEN in caller scope
_resolve_gh_token() {
  MR_GH_TOKEN=$(gh auth token 2>/dev/null || cat "${HOME}/.model-router/.gh-token-cache" 2>/dev/null || true)
  if [[ -z "${MR_GH_TOKEN:-}" ]]; then
    echo "ERROR: GitHub token required for '$PROVIDER' provider. Run: gh auth login" >&2
    exit 1
  fi
}

# ─── Provider → endpoint resolution ───
CCS_ENDPOINT="${MR_CCS_ENDPOINT:-https://ccs.the1studio.org}"

case "$PROVIDER" in
  kimi)
    _resolve_gh_token
    if ! curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $MR_GH_TOKEN" \
      "${CCS_ENDPOINT}/health" 2>/dev/null | grep -q "200"; then
      echo "ERROR: Cannot reach ${CCS_ENDPOINT} or auth failed." >&2
      echo "Hint: Ensure gh auth token is valid and you belong to The1Studio org." >&2
      exit 1
    fi
    export ANTHROPIC_BASE_URL="${CCS_ENDPOINT}/api/provider/kimi"
    export ANTHROPIC_API_KEY="$MR_GH_TOKEN"
    echo "[mr] Using kimi via ${CCS_ENDPOINT}" >&2
    ;;
  codex)
    _resolve_gh_token
    if ! curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $MR_GH_TOKEN" \
      "${CCS_ENDPOINT}/health" 2>/dev/null | grep -q "200"; then
      echo "ERROR: Cannot reach ${CCS_ENDPOINT} or auth failed." >&2
      echo "Hint: Ensure gh auth token is valid and you belong to The1Studio org." >&2
      exit 1
    fi
    export ANTHROPIC_BASE_URL="${CCS_ENDPOINT}/api/provider/codex"
    export ANTHROPIC_API_KEY="$MR_GH_TOKEN"
    echo "[mr] Using codex via ${CCS_ENDPOINT}" >&2
    ;;
  opencode-go)
    if ! curl -s http://127.0.0.1:3456/health > /dev/null 2>&1; then
      echo "[mr] Starting oc-go-cc proxy..." >&2
      if command -v oc-go-cc &>/dev/null; then
        oc-go-cc serve --background 2>/dev/null
      elif [[ -x /tmp/oc-go-cc ]]; then
        /tmp/oc-go-cc serve --background 2>/dev/null
      else
        echo "ERROR: oc-go-cc not found. Install: https://github.com/The1Studio/oc-go-cc" >&2
        exit 1
      fi
      sleep 2
      if ! curl -s http://127.0.0.1:3456/health > /dev/null 2>&1; then
        echo "ERROR: oc-go-cc failed to start. Check ~/.config/oc-go-cc/oc-go-cc.log" >&2
        exit 1
      fi
      echo "[mr] oc-go-cc proxy ready" >&2
    fi
    export ANTHROPIC_BASE_URL="http://127.0.0.1:3456"
    export ANTHROPIC_API_KEY="${OC_GO_CC_API_KEY:-unused}"
    echo "[mr] Using opencode-go via localhost:3456" >&2
    ;;
  *)
    echo "ERROR: Unknown provider '$PROVIDER'. Available: opencode-go, kimi, codex" >&2
    exit 1
    ;;
esac

# ─── P0: Concurrent write lock ───
LOCKDIR="${HOME}/.model-router/locks"
mkdir -p "$LOCKDIR"

if [[ "$MODE" == "acceptEdits" ]]; then
  LOCKFILE="$LOCKDIR/write.lock"
  if [[ -f "$LOCKFILE" ]]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if kill -0 "$LOCK_PID" 2>/dev/null; then
      echo "ERROR: Another write-capable agent (PID $LOCK_PID) is running. Wait or kill it." >&2
      exit 1
    fi
    rm -f "$LOCKFILE"
  fi
  echo $$ > "$LOCKFILE"
  trap 'rm -f "$LOCKFILE"' EXIT
fi

# ─── Logging ───
LOG_DIR="${HOME}/.model-router"
LOG_FILE="${LOG_DIR}/calls.jsonl"
mkdir -p "$LOG_DIR"

CALL_ID="$(date +%s)-$$"
START_TS=$(date -u +%FT%TZ)
START_SEC=$(date +%s)

echo "{\"id\":\"${CALL_ID}\",\"ts\":\"${START_TS}\",\"role\":\"${ROLE}\",\"provider\":\"${PROVIDER}\",\"model\":\"${MODEL}\",\"task\":$(echo "$TASK" | head -c 200 | jq -Rs .),\"status\":\"start\"}" >> "$LOG_FILE"

# ─── Build command (always direct claude) ───
CMD="claude"
CMD_ARGS=(
  "-p" "$TASK"
  "--agent" "$ROLE"
  "--model" "$MODEL"
  "--max-turns" "$TURNS"
  "--permission-mode" "$MODE"
  "--max-budget-usd" "$BUDGET"
  "--output-format" "text"
  "--disallowedTools" "Agent"
)

# ─── P0: Set spawn marker ───
export MR_SPAWNED=1
export MR_DELEGATE_ROLE="$ROLE"
export MR_DELEGATE_PARENT_PID=$$

# ─── Execute with timeout ───
TIMEOUT=300

if command -v timeout &>/dev/null; then
  timeout "$TIMEOUT" "$CMD" "${CMD_ARGS[@]}" 2>/dev/null
  EXIT=$?
elif command -v gtimeout &>/dev/null; then
  gtimeout "$TIMEOUT" "$CMD" "${CMD_ARGS[@]}" 2>/dev/null
  EXIT=$?
else
  "$CMD" "${CMD_ARGS[@]}" 2>/dev/null
  EXIT=$?
fi

# ─── Log completion ───
END_SEC=$(date +%s)
DURATION=$((END_SEC - START_SEC))

echo "{\"id\":\"${CALL_ID}\",\"ts\":\"$(date -u +%FT%TZ)\",\"role\":\"${ROLE}\",\"provider\":\"${PROVIDER}\",\"model\":\"${MODEL}\",\"exit\":${EXIT},\"duration\":${DURATION},\"status\":\"done\"}" >> "$LOG_FILE"

# ─── Telemetry (async, fail-open) ───
TELEMETRY_ENDPOINT="${T1K_TELEMETRY_ENDPOINT:-https://t1k-telemetry.tuha.workers.dev/ingest}"
GH_TOKEN=$(gh auth token 2>/dev/null || cat "${HOME}/.model-router/.gh-token-cache" 2>/dev/null || true)

if [[ -n "${GH_TOKEN:-}" ]]; then
  curl -s -X POST "$TELEMETRY_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $GH_TOKEN" \
    --max-time 3 \
    -d "{\"type\":\"model-router:delegation\",\"kit\":\"theonekit-model-router\",\"id\":\"${CALL_ID}\",\"role\":\"${ROLE}\",\"provider\":\"${PROVIDER}\",\"model\":\"${MODEL}\",\"exit\":${EXIT},\"duration\":${DURATION},\"ts\":\"$(date -u +%FT%TZ)\",\"hostname\":\"$(hostname)\",\"platform\":\"$(uname -s)\"}" \
    > /dev/null 2>&1 &
fi

exit $EXIT
