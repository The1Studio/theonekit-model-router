#!/bin/bash
# model-router delegate script (mr-delegate.sh)
# Usage: mr-delegate.sh <role> "<task>" [--profile <override>] [--model <override>]
#
# Spawns a CCS session via oc-go-cc proxy with safety flags enforced.
# All CC context (CLAUDE.md, skills, hooks, permissions) inherited natively.
#
# SSOT: role → profile → model → budget mapping lives HERE.

set -euo pipefail

# ─── P0: Recursive delegation guard ───
if [[ "${MR_SPAWNED:-}" == "1" ]]; then
  echo "ERROR: Recursive delegation detected. Spawned sessions cannot delegate." >&2
  exit 1
fi

ROLE="${1:?Usage: mr-delegate.sh <role> \"<task>\" [--profile <p>] [--model <m>]}"
TASK="${2:?Missing task description}"
shift 2

# Parse optional flags
OVERRIDE_PROFILE=""
OVERRIDE_MODEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) OVERRIDE_PROFILE="$2"; shift 2 ;;
    --model) OVERRIDE_MODEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ─── Layer 3: Role → profile → model → budget (SSOT) ───
case "$ROLE" in
  mr-explorer-fast)
    PROFILE="${OVERRIDE_PROFILE:-opencode-go}"
    MODEL="${OVERRIDE_MODEL:-qwen3.5-plus}"
    MODE="plan"
    TURNS=30
    BUDGET="5.00"
    ;;
  mr-doc-scout)
    PROFILE="${OVERRIDE_PROFILE:-opencode-go}"
    MODEL="${OVERRIDE_MODEL:-kimi-k2.5}"
    MODE="plan"
    TURNS=25
    BUDGET="5.00"
    ;;
  mr-doc-writer)
    PROFILE="${OVERRIDE_PROFILE:-opencode-go}"
    MODEL="${OVERRIDE_MODEL:-kimi-k2.6}"
    MODE="acceptEdits"
    TURNS=50
    BUDGET="10.00"
    ;;
  mr-coder-cheap)
    PROFILE="${OVERRIDE_PROFILE:-opencode-go}"
    MODEL="${OVERRIDE_MODEL:-kimi-k2.6}"
    MODE="acceptEdits"
    TURNS=50
    BUDGET="10.00"
    ;;
  mr-reviewer-deep)
    PROFILE="${OVERRIDE_PROFILE:-opencode-go}"
    MODEL="${OVERRIDE_MODEL:-glm-5.1}"
    MODE="plan"
    TURNS=40
    BUDGET="10.00"
    ;;
  mr-tester)
    PROFILE="${OVERRIDE_PROFILE:-opencode-go}"
    MODEL="${OVERRIDE_MODEL:-qwen3.5-plus}"
    MODE="plan"
    TURNS=30
    BUDGET="5.00"
    ;;
  *)
    echo "Unknown role: $ROLE" >&2
    echo "Available: mr-explorer-fast, mr-doc-scout, mr-doc-writer, mr-coder-cheap, mr-reviewer-deep, mr-tester" >&2
    exit 1
    ;;
esac

# ─── P0: Auto-start oc-go-cc if needed ───
if [[ "$PROFILE" == "opencode-go" ]]; then
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
fi

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

echo "{\"id\":\"${CALL_ID}\",\"ts\":\"${START_TS}\",\"role\":\"${ROLE}\",\"profile\":\"${PROFILE}\",\"model\":\"${MODEL}\",\"task\":$(echo "$TASK" | head -c 200 | jq -Rs .),\"status\":\"start\"}" >> "$LOG_FILE"

# ─── Build CCS command ───
CCS_ARGS=(
  "$PROFILE"
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
  timeout "$TIMEOUT" ccs "${CCS_ARGS[@]}" 2>/dev/null
  EXIT=$?
elif command -v gtimeout &>/dev/null; then
  gtimeout "$TIMEOUT" ccs "${CCS_ARGS[@]}" 2>/dev/null
  EXIT=$?
else
  ccs "${CCS_ARGS[@]}" 2>/dev/null
  EXIT=$?
fi

# ─── Log completion ───
END_SEC=$(date +%s)
DURATION=$((END_SEC - START_SEC))

echo "{\"id\":\"${CALL_ID}\",\"ts\":\"$(date -u +%FT%TZ)\",\"role\":\"${ROLE}\",\"profile\":\"${PROFILE}\",\"model\":\"${MODEL}\",\"exit\":${EXIT},\"duration\":${DURATION},\"status\":\"done\"}" >> "$LOG_FILE"

exit $EXIT
