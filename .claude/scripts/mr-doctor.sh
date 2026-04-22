#!/bin/bash
# t1k-origin: kit=theonekit-model-router | repo=The1Studio/theonekit-model-router | module=null | protected=false
# mr-doctor.sh — health check for model-router prerequisites
# Usage: bash scripts/mr-doctor.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

check_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
check_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARN=$((WARN + 1)); }
check_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }

echo "=== model-router doctor ==="
echo ""

# 1. Claude Code
if command -v claude &>/dev/null; then
  check_pass "Claude Code installed ($(claude --version 2>/dev/null | head -1))"
else
  check_fail "Claude Code not found"
fi

# 2. CCS
if command -v ccs &>/dev/null; then
  check_pass "CCS installed ($(ccs --version 2>/dev/null | head -1))"
else
  check_fail "CCS not found — npm install -g @kaitranntt/ccs"
fi

# 3. oc-go-cc
if command -v oc-go-cc &>/dev/null; then
  check_pass "oc-go-cc installed ($(oc-go-cc --version 2>/dev/null))"
elif [[ -x /tmp/oc-go-cc ]]; then
  check_warn "oc-go-cc found at /tmp/oc-go-cc (not in PATH)"
elif [[ -x "${HOME}/.local/bin/oc-go-cc" ]]; then
  check_warn "oc-go-cc found at ~/.local/bin/oc-go-cc (not in PATH)"
else
  check_fail "oc-go-cc not found — download from https://github.com/The1Studio/oc-go-cc"
fi

# 4. API key
if [[ -n "${OC_GO_CC_API_KEY:-}" ]]; then
  check_pass "OC_GO_CC_API_KEY set"
else
  check_warn "OC_GO_CC_API_KEY not set — export OC_GO_CC_API_KEY=sk-your-key"
fi

# 5. oc-go-cc config
if [[ -f "${HOME}/.config/oc-go-cc/config.json" ]]; then
  check_pass "oc-go-cc config exists"
else
  check_fail "oc-go-cc config missing — run: oc-go-cc init"
fi

# 6. CCS profile
if [[ -f "${HOME}/.ccs/opencode-go.settings.json" ]]; then
  check_pass "CCS opencode-go profile exists"
else
  check_fail "CCS opencode-go profile missing — run: bash scripts/post-install.sh"
fi

# 7. Proxy health
if curl -s http://127.0.0.1:3456/health > /dev/null 2>&1; then
  HEALTH=$(curl -s http://127.0.0.1:3456/health | python3 -c "import sys,json;d=json.load(sys.stdin);print(f\"status={d['status']}, requests={d['metrics']['requests_received']}\")" 2>/dev/null || echo "ok")
  check_pass "oc-go-cc proxy running ($HEALTH)"
else
  check_warn "oc-go-cc proxy not running — start: oc-go-cc serve --background"
fi

# 8. Agent defs
AGENT_COUNT=$(ls .claude/agents/mr-*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$AGENT_COUNT" -ge 6 ]]; then
  check_pass "Agent definitions: $AGENT_COUNT agents"
else
  check_fail "Agent definitions: only $AGENT_COUNT found (expected 6)"
fi

# 9. Skill
if [[ -f ".claude/skills/mr-delegate/SKILL.md" ]]; then
  check_pass "Skill mr-delegate installed"
else
  check_fail "Skill mr-delegate missing"
fi

# 10. Delegate script
if [[ -x "scripts/mr-delegate.sh" ]]; then
  check_pass "mr-delegate.sh executable"
else
  check_fail "mr-delegate.sh missing or not executable"
fi

# 11. T1K module manifest
if [[ -f ".claude/t1k-modules.json" ]]; then
  check_pass "T1K module manifest present"
else
  check_warn "T1K module manifest missing (standalone mode)"
fi

# 12. Log directory
if [[ -d "${HOME}/.model-router" ]]; then
  CALL_COUNT=$(wc -l < "${HOME}/.model-router/calls.jsonl" 2>/dev/null || echo "0")
  check_pass "Log directory exists ($CALL_COUNT log entries)"
else
  check_warn "Log directory missing — will be created on first delegation"
fi

# Summary
echo ""
echo "=== Results: ${PASS} pass, ${WARN} warn, ${FAIL} fail ==="

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Fix failures: bash scripts/post-install.sh"
  exit 1
fi
