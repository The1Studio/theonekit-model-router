#!/bin/bash
# post-install.sh — runs after `t1k modules install model-router`
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
if [[ -z "${OC_GO_CC_API_KEY:-}" ]]; then
  warn "OC_GO_CC_API_KEY not set."
  echo "  Get your key: https://opencode.ai/go"
  echo "  Then add to shell profile:"
  echo "    export OC_GO_CC_API_KEY=sk-your-key-here"
  echo ""
  echo "  Or set it now (temporary):"
  read -rp "  API Key (press Enter to skip): " API_KEY
  if [[ -n "$API_KEY" ]]; then
    export OC_GO_CC_API_KEY="$API_KEY"
    ok "API key set for this session"
    echo "  To persist, add to ~/.zshrc or ~/.bashrc:"
    echo "    export OC_GO_CC_API_KEY=$API_KEY"
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

echo ""
echo "=== model-router ready ==="
echo ""
echo "Quick test:"
echo "  bash scripts/mr-delegate.sh mr-explorer-fast \"list files in this project\""
echo ""
