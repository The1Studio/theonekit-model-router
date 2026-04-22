#!/bin/bash
# t1k-origin: kit=theonekit-model-router | repo=The1Studio/theonekit-model-router | module=null | protected=false
# post-install.sh — runs after `t1k modules add model-router`
# Auto-installs CCS, oc-go-cc, creates CCS profile, inits oc-go-cc config.
# Idempotent — safe to re-run.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[X]${NC} $1"; }

echo ""
echo "=== model-router post-install ==="
echo ""

# ─── 1. CCS ───
if command -v ccs &>/dev/null; then
  ok "CCS already installed ($(ccs --version 2>/dev/null | head -1))"
else
  echo "Installing CCS..."
  if command -v npm &>/dev/null; then
    npm install -g @kaitranntt/ccs 2>/dev/null
    ok "CCS installed"
  else
    fail "npm not found. Install CCS manually: npm install -g @kaitranntt/ccs"
    exit 1
  fi
fi

# ─── 2. oc-go-cc ───
OC_BIN=""
if command -v oc-go-cc &>/dev/null; then
  OC_BIN="oc-go-cc"
  ok "oc-go-cc already installed ($(oc-go-cc --version 2>/dev/null))"
elif [[ -x /tmp/oc-go-cc ]]; then
  OC_BIN="/tmp/oc-go-cc"
  ok "oc-go-cc found at /tmp/oc-go-cc"
else
  echo "Installing oc-go-cc..."
  ARCH=$(uname -m)
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]] && ARCH="arm64" || ARCH="amd64"

  INSTALL_DIR="${HOME}/.local/bin"
  mkdir -p "$INSTALL_DIR"

  if curl -fsSL -o "${INSTALL_DIR}/oc-go-cc" \
    "https://github.com/The1Studio/oc-go-cc/releases/latest/download/oc-go-cc_${OS}-${ARCH}" 2>/dev/null; then
    chmod +x "${INSTALL_DIR}/oc-go-cc"
    OC_BIN="${INSTALL_DIR}/oc-go-cc"
    ok "oc-go-cc installed to ${INSTALL_DIR}/oc-go-cc"

    # Add to PATH hint if not in PATH
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
      warn "Add to PATH: export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
  else
    fail "Failed to download oc-go-cc. Install manually: https://github.com/The1Studio/oc-go-cc"
    exit 1
  fi
fi

# ─── 3. oc-go-cc config ───
if [[ ! -f "${HOME}/.config/oc-go-cc/config.json" ]]; then
  $OC_BIN init 2>/dev/null
  ok "oc-go-cc config created"
else
  ok "oc-go-cc config exists"
fi

# ─── 4. API key check ───
OC_CONFIG="${HOME}/.config/oc-go-cc/config.json"
API_KEY_PERSISTED=0

# Check if API key is already in config file
if [[ -f "$OC_CONFIG" ]]; then
  if python3 -c "import json; d=json.load(open('$OC_CONFIG')); assert d.get('api_key','')" 2>/dev/null; then
    API_KEY_PERSISTED=1
    ok "API key persisted in config"
  fi
fi

if [[ "$API_KEY_PERSISTED" == "0" && -z "${OC_GO_CC_API_KEY:-}" ]]; then
  warn "OpenCode Go API key not configured."
  echo "  Get your key: https://opencode.ai/go"
  echo ""
  read -rp "  API Key (press Enter to skip): " API_KEY
  if [[ -n "$API_KEY" ]]; then
    # Persist into oc-go-cc config.json
    if [[ -f "$OC_CONFIG" ]]; then
      python3 -c "
import json
with open('$OC_CONFIG') as f: d = json.load(f)
d['api_key'] = '$API_KEY'
with open('$OC_CONFIG', 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null && ok "API key saved to $OC_CONFIG" || {
        export OC_GO_CC_API_KEY="$API_KEY"
        warn "Could not save to config. Set env: export OC_GO_CC_API_KEY=$API_KEY"
      }
    else
      export OC_GO_CC_API_KEY="$API_KEY"
      warn "Config missing. Set env: export OC_GO_CC_API_KEY=$API_KEY"
    fi
  fi
elif [[ "$API_KEY_PERSISTED" == "0" && -n "${OC_GO_CC_API_KEY:-}" ]]; then
  # Env var set but not persisted — save it
  if [[ -f "$OC_CONFIG" ]]; then
    python3 -c "
import json
with open('$OC_CONFIG') as f: d = json.load(f)
d['api_key'] = '${OC_GO_CC_API_KEY}'
with open('$OC_CONFIG', 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null && ok "API key persisted from env to config"
  fi
fi

# ─── 5. CCS opencode-go profile ───
CCS_SETTINGS="${HOME}/.ccs/opencode-go.settings.json"
if [[ -f "$CCS_SETTINGS" ]]; then
  ok "CCS opencode-go profile exists"
else
  mkdir -p "${HOME}/.ccs"
  cat > "$CCS_SETTINGS" << 'SETTINGS'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_AUTH_TOKEN": "unused"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "WebSearch",
        "hooks": [
          {
            "type": "command",
            "command": "node \"$HOME/.ccs/hooks/websearch-transformer.cjs\"",
            "timeout": 85
          }
        ]
      }
    ]
  }
}
SETTINGS
  ok "Created CCS opencode-go profile"

  # Register in CCS config
  CCS_CONFIG="${HOME}/.ccs/config.yaml"
  if [[ -f "$CCS_CONFIG" ]]; then
    if ! grep -q "opencode-go" "$CCS_CONFIG" 2>/dev/null; then
      if grep -q "^profiles: {}" "$CCS_CONFIG" 2>/dev/null; then
        sed -i.bak "s|^profiles: {}|profiles:\n  opencode-go:\n    type: api\n    settings: ~/.ccs/opencode-go.settings.json|" "$CCS_CONFIG"
        rm -f "${CCS_CONFIG}.bak"
      fi
      ok "Registered opencode-go in CCS config"
    fi
  fi
fi

# ─── 6. Start proxy ───
if curl -s http://127.0.0.1:3456/health > /dev/null 2>&1; then
  ok "oc-go-cc proxy already running"
elif [[ -n "${OC_GO_CC_API_KEY:-}" ]]; then
  $OC_BIN serve --background 2>/dev/null
  sleep 2
  if curl -s http://127.0.0.1:3456/health > /dev/null 2>&1; then
    ok "oc-go-cc proxy started"
  else
    warn "oc-go-cc proxy failed to start. Check: ~/.config/oc-go-cc/oc-go-cc.log"
  fi
else
  warn "Skipping proxy start (no API key). Set OC_GO_CC_API_KEY first."
fi

# ─── 7. Log directory ───
mkdir -p "${HOME}/.model-router"
ok "Log directory: ~/.model-router/"

# ─── 8. Remote CLIProxy (ccs.the1studio.org) ───
CCS_CONFIG="${HOME}/.ccs/config.yaml"
MR_CCS_ENDPOINT="ccs.the1studio.org"

if command -v gh &>/dev/null && gh auth token &>/dev/null; then
  MR_GH_TOKEN=$(gh auth token 2>/dev/null)
  ok "GitHub CLI authenticated"

  # Auto-configure remote CLIProxy if not already set
  if [[ -f "$CCS_CONFIG" ]]; then
    REMOTE_ENABLED=$(grep -A1 "remote:" "$CCS_CONFIG" 2>/dev/null | grep "enabled:" | head -1 | grep -c "true" || true)
    REMOTE_HOST=$(grep -A3 "remote:" "$CCS_CONFIG" 2>/dev/null | grep "host:" | head -1 | grep -c "$MR_CCS_ENDPOINT" || true)

    if [[ "$REMOTE_HOST" == "1" && "$REMOTE_ENABLED" == "1" ]]; then
      ok "Remote CLIProxy already configured ($MR_CCS_ENDPOINT)"
    else
      echo "  Configuring remote CLIProxy → $MR_CCS_ENDPOINT ..."
      # Enable remote, set host, protocol, auth_token
      sed -i.bak -e "/cliproxy_server:/,/fallback:/ {
        s|enabled: false|enabled: true|
        s|host: \"\"|host: \"$MR_CCS_ENDPOINT\"|
        s|protocol: http$|protocol: https|
        s|auth_token: \"\"|auth_token: \"$MR_GH_TOKEN\"|
      }" "$CCS_CONFIG"
      rm -f "${CCS_CONFIG}.bak"

      # Verify
      if grep -q "$MR_CCS_ENDPOINT" "$CCS_CONFIG" 2>/dev/null; then
        ok "Remote CLIProxy configured → https://$MR_CCS_ENDPOINT"
        echo "  Providers available: $(curl -s --max-time 5 -H "Authorization: Bearer $MR_GH_TOKEN" "https://$MR_CCS_ENDPOINT/providers" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(p['name'] for p in d.get('providers',[]) if p.get('status')=='authenticated'))" 2>/dev/null || echo "check manually")"
      else
        warn "Could not configure remote CLIProxy. Set manually in ~/.ccs/config.yaml"
      fi
    fi
  else
    warn "CCS config not found. Run: ccs --version (to initialize)"
  fi
else
  warn "gh not authenticated. Run: gh auth login"
  echo "  Needed for CCS CLIProxy providers (kimi, codex, etc.) via $MR_CCS_ENDPOINT"
fi

echo ""
echo "=== model-router ready ==="
echo ""
echo "Quick test:"
echo "  bash scripts/mr-delegate.sh mr-explorer-fast \"list files in this project\""
echo ""
echo "Providers:"
echo "  OpenCode Go (local):  --profile opencode-go (default)"
echo "  CCS remote:           --profile kimi --model kimi-k2.6"
echo "  Check remote:         curl -sH \"Authorization: Bearer \$(gh auth token)\" https://$MR_CCS_ENDPOINT/providers | jq"
echo ""
