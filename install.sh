#!/bin/bash
# model-router installer
# Usage: bash install.sh [--force]

set -euo pipefail

echo "=== model-router installer ==="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[X]${NC} $1"; }

FORCE="${1:-}"

# ─── Check prerequisites ───
echo "Checking prerequisites..."

if command -v claude &>/dev/null; then
  ok "Claude Code found ($(claude --version 2>/dev/null | head -1 || echo 'unknown'))"
else
  fail "Claude Code not found. Install: https://claude.ai/code"
  exit 1
fi

if command -v ccs &>/dev/null; then
  ok "CCS found ($(ccs --version 2>/dev/null | head -1 || echo 'unknown'))"
else
  fail "CCS not found. Install: npm install -g @kaitranntt/ccs"
  exit 1
fi

if command -v oc-go-cc &>/dev/null || [[ -x /tmp/oc-go-cc ]]; then
  ok "oc-go-cc found"
else
  warn "oc-go-cc not found. Installing..."
  ARCH=$(uname -m)
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]] && ARCH="arm64" || ARCH="amd64"
  curl -L -o /tmp/oc-go-cc "https://github.com/The1Studio/oc-go-cc/releases/latest/download/oc-go-cc_${OS}-${ARCH}" 2>/dev/null
  chmod +x /tmp/oc-go-cc
  ok "oc-go-cc installed to /tmp/oc-go-cc"
fi

command -v jq &>/dev/null && ok "jq found" || warn "jq not found (optional). Install: brew install jq"

echo ""

# ─── Determine install source ───
if [[ -f "scripts/mr-delegate.sh" ]]; then
  SRC="$(pwd)"
  ok "Running from repo: $SRC"
else
  SRC="${HOME}/.model-router/repo"
  if [[ -d "$SRC/.git" ]]; then
    cd "$SRC" && git pull --quiet
    ok "Updated: $SRC"
  else
    mkdir -p "$(dirname "$SRC")"
    git clone --quiet https://github.com/The1Studio/model-router.git "$SRC"
    ok "Cloned: $SRC"
  fi
  cd "$SRC"
fi

# ─── Install agents ───
echo ""
echo "Installing agent definitions..."
AGENTS_DIR=".claude/agents"
mkdir -p "$AGENTS_DIR"
COUNT=0
for f in "$SRC/.claude/agents/"mr-*.md; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  if [[ -f "$AGENTS_DIR/$name" ]] && [[ "$FORCE" != "--force" ]]; then
    warn "$name exists, skipping"
  else
    cp "$f" "$AGENTS_DIR/$name"
    ok "Installed $name"
    COUNT=$((COUNT + 1))
  fi
done
echo "  $COUNT agent(s) installed"

# ─── Install skill ───
echo ""
echo "Installing skill..."
SKILL_DIR=".claude/skills/model-router"
mkdir -p "$SKILL_DIR"
if [[ -f "$SKILL_DIR/SKILL.md" ]] && [[ "$FORCE" != "--force" ]]; then
  warn "Skill exists, skipping"
else
  cp "$SRC/.claude/skills/model-router/SKILL.md" "$SKILL_DIR/SKILL.md"
  ok "Installed skill"
fi

# ─── Install script ───
echo ""
echo "Installing delegate script..."
mkdir -p "scripts"
if [[ -f "scripts/mr-delegate.sh" ]] && [[ "$FORCE" != "--force" ]]; then
  warn "Script exists, skipping"
else
  cp "$SRC/scripts/mr-delegate.sh" "scripts/mr-delegate.sh"
  chmod +x "scripts/mr-delegate.sh"
  ok "Installed scripts/mr-delegate.sh"
fi

# ─── Setup oc-go-cc config ───
echo ""
echo "Setting up oc-go-cc..."
if [[ ! -f "$HOME/.config/oc-go-cc/config.json" ]]; then
  if command -v oc-go-cc &>/dev/null; then
    oc-go-cc init 2>/dev/null
  elif [[ -x /tmp/oc-go-cc ]]; then
    /tmp/oc-go-cc init 2>/dev/null
  fi
  ok "Created oc-go-cc config"
else
  ok "oc-go-cc config exists"
fi

if [[ -z "${OC_GO_CC_API_KEY:-}" ]]; then
  warn "OC_GO_CC_API_KEY not set. Add to your shell profile:"
  echo "  export OC_GO_CC_API_KEY=sk-your-opencode-go-key"
fi

# ─── Setup CCS profile ───
echo ""
echo "Setting up CCS opencode-go profile..."
CCS_SETTINGS="$HOME/.ccs/opencode-go.settings.json"
if [[ -f "$CCS_SETTINGS" ]]; then
  ok "CCS opencode-go profile exists"
else
  cat > "$CCS_SETTINGS" << 'SETTINGS'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_AUTH_TOKEN": "unused",
    "ANTHROPIC_MODEL": "kimi-k2.6",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.1",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "kimi-k2.6",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3.5-plus"
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

  # Register in CCS config if not already
  if ! grep -q "opencode-go" "$HOME/.ccs/config.yaml" 2>/dev/null; then
    if grep -q "^profiles: {}" "$HOME/.ccs/config.yaml" 2>/dev/null; then
      sed -i.bak "s|^profiles: {}|profiles:\n  opencode-go:\n    type: api\n    settings: ~/.ccs/opencode-go.settings.json|" "$HOME/.ccs/config.yaml"
      rm -f "$HOME/.ccs/config.yaml.bak"
    fi
    ok "Registered in CCS config"
  fi
fi

# ─── Create log dir ───
mkdir -p "${HOME}/.model-router"
ok "Log directory: ~/.model-router/"

# ─── Summary ───
echo ""
echo "=== Installation complete ==="
echo ""
echo "Usage:"
echo "  bash scripts/mr-delegate.sh mr-explorer-fast \"find all auth files\""
echo "  bash scripts/mr-delegate.sh mr-coder-cheap \"add input validation\""
echo "  bash scripts/mr-delegate.sh mr-reviewer-deep \"review src/auth/ for security\""
echo ""
echo "Before first use:"
echo "  1. Set API key: export OC_GO_CC_API_KEY=sk-your-key"
echo "  2. Start proxy: oc-go-cc serve --background"
echo "  3. Or let mr-delegate.sh auto-start the proxy"
echo ""
echo "Docs: https://github.com/The1Studio/model-router/wiki"
