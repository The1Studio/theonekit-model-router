# Approach: Spawned CC Session + CCS

## Problem Statement

Claude Code only supports Claude models (Anthropic). There is no official way to use other AI models (OpenAI GPT, Google Gemini, GLM, MiniMax, Kimi, Qwen, DeepSeek, etc.) as subagents within Claude Code while preserving the full CC ecosystem.

## Goals

- Per-subagent model selection (different models for different roles)
- Full Claude Code context inheritance (CLAUDE.md, skills, hooks, permissions)
- Zero Anthropic ban risk
- Multi-provider support (13+ providers)
- Custom provider support (any OpenAI-compatible endpoint)
- Configurable agent roles
- Safety controls

## Chosen Approach

**Spawn separate `claude -p` processes via CCS with different model providers.**

### How It Works

```
Claude Code main session (direct Anthropic, OAuth, SAFE)
│
│  User: "explore this codebase for auth patterns"
│  Claude: decides to delegate → runs delegate script or MCP tool
│
▼
delegate.sh / MCP server:
│  1. Look up role config: explorer-fast → CCS profile "gemini"
│  2. Spawn:
│     ccs gemini -p "find auth patterns..." \
│       --agent explorer-fast \
│       --max-turns 30 \
│       --permission-mode plan \
│       --max-budget-usd 0.50 \
│       --output-format json
│
▼
CCS (Claude Code Switch):
│  1. Start/connect CLIProxy (localhost:8317)
│  2. Set env: ANTHROPIC_BASE_URL=proxy, ANTHROPIC_MODEL=gemini-2.5-pro
│  3. Spawn: claude -p "..." --agent explorer-fast ...
│
▼
Spawned Claude Code session:
│  ├─ Loads CLAUDE.md (project + user)         ✅
│  ├─ Loads skills (from agent frontmatter)    ✅
│  ├─ Fires hooks (PreToolUse, PostToolUse)    ✅
│  ├─ Enforces permissions (plan = read-only)  ✅
│  ├─ Tools: only Read, Grep, Glob             ✅
│  ├─ Sends API to CCS proxy → Gemini API
│  ├─ Agent loop: tool calls → execute → repeat
│  └─ Returns JSON result
│
▼
Main session receives result, presents to user
```

## Why This Approach

### Evidence from Official Documentation

| Claim | Source | Quote |
|-------|--------|-------|
| API key bypasses OAuth in `-p` mode | [/en/authentication](https://code.claude.com/docs/en/authentication) | *"In non-interactive mode (`-p`), the key is always used when present."* |
| `-p` loads full context | [/en/headless](https://code.claude.com/docs/en/headless) | *"without `--bare`, `claude -p` loads the same context an interactive session would"* |
| `ANTHROPIC_BASE_URL` officially supported | [/en/llm-gateway](https://code.claude.com/docs/en/llm-gateway) | *"LLM gateways provide a centralized proxy layer"* |
| Custom model IDs skip validation | [/en/model-config](https://code.claude.com/docs/en/model-config) | *"Claude Code skips validation for the model ID set in `ANTHROPIC_CUSTOM_MODEL_OPTION`"* |

### Verified by Live Test

```
$ ccs codex -p "say hello" --max-turns 1 --output-format json

# Output confirms:
# - model: "gpt-5.3-codex" (routed to OpenAI)
# - tools: all 90+ tools loaded
# - mcp_servers: 5 servers connected
# - agents: 60+ agents loaded
# - skills: 50+ skills loaded
# - plugins: 44 plugins loaded
```

### Critical Difference from Existing Projects

All existing proxy projects (claude-code-router 32k★, claude-code-proxy 3.4k★, CCS itself) set `ANTHROPIC_BASE_URL` **globally** on the main session → Anthropic ban risk.

Our approach sets it **only on spawned subagent sessions** → main session never touches proxy → **zero ban risk**.

## Implementation Options

### Option A: Enhanced Skill + Script (~50 lines)

A Claude Code skill (markdown) instructs Claude how to delegate, plus a thin bash script that enforces safety flags and logs metrics.

**Pros:** Zero dependencies beyond CCS, ship immediately, easy to modify
**Cons:** ~90% deterministic (Claude interprets skill), unreliable metrics

### Option B: MCP Server (~700 lines)

A Bun+TypeScript MCP server exposing structured `delegate(role, task, model?)` tool.

**Pros:** 100% deterministic, structured metrics, programmatic API
**Cons:** More code, MCP registration required

### Recommended Path

Start with **Option A** (skill + script) to validate workflow. Upgrade to **Option B** (MCP) when needing parallel delegation, structured metrics, or deterministic behavior.
