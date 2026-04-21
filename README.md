# model-router

Multi-model subagent system for Claude Code — delegate tasks to any AI model (GPT, Gemini, GLM, Kimi, Qwen, DeepSeek, etc.) as subagents with full Claude Code context inheritance.

## Problem

Claude Code only supports Claude models natively. There's no official way to use other AI models as subagents while preserving the full Claude Code ecosystem (CLAUDE.md, skills, hooks, permissions, tools).

## Solution

**Spawned CC Session + CCS** — spawn separate `claude -p` processes via [CCS](https://github.com/kaitranntt/ccs) with different model providers. Each spawned session inherits 100% of Claude Code's context (CLAUDE.md, skills, hooks, permissions) while routing API calls to any provider.

### How it works

```
Claude Code main session (direct Anthropic, safe)
│
│  Delegate task to cheaper/specialized model
│  via skill or MCP tool
▼
CCS spawns separate claude -p session:
├─ ANTHROPIC_BASE_URL → CCS local proxy
├─ ANTHROPIC_MODEL → target model (GLM, GPT, Gemini, ...)
├─ Loads CLAUDE.md, skills, hooks, permissions ✅
├─ Agent loop runs with non-Claude model
└─ Returns result to main session
```

### Key properties

- **100% CC context inheritance** — CLAUDE.md, skills, hooks, permissions, agents all loaded natively
- **Zero Anthropic ban risk** — main session untouched, spawned sessions never contact Anthropic
- **13+ providers** — via CCS profiles (Gemini, Codex, Kimi, Qwen, GLM, OpenRouter, Ollama, etc.)
- **Per-subagent model selection** — each role maps to a different CCS profile/model
- **8-layer safety model** — tool whitelist, permission mode, hooks, max-turns, budget cap, timeout, loop detection
- **Minimal code** — ~700 lines (MCP) or ~50 lines (skill + script)

## Documentation

See the [Wiki](../../wiki) for comprehensive documentation:

- [Approach](../../wiki/Approach) — chosen approach with evidence
- [Architecture](../../wiki/Architecture) — system design
- [Pros & Cons](../../wiki/Pros-and-Cons) — tradeoff analysis
- [Implementation Plan](../../wiki/Implementation-Plan) — phased roadmap
- [Rejected Approaches](../../wiki/Rejected-Approaches) — 9 alternatives evaluated
- [References](../../wiki/References) — sources and prior art

## Quick Start

### Option A: Skill + Script (simplest, ship today)

```bash
# 1. Ensure CCS is installed with providers configured
ccs config

# 2. Copy agent definitions
cp -r config/agents/ .claude/agents/

# 3. Copy skill
cp -r config/skill/ .claude/skills/model-router/

# 4. Use in Claude Code
# Claude will auto-delegate based on skill description, or:
# "delegate exploring this codebase to a cheap model"
```

### Option B: MCP Server (structured, metrics)

```bash
# 1. Install
bun install

# 2. Register MCP server
# Add to .claude/settings.local.json:
# { "mcpServers": { "model-router": { "type": "stdio", "command": "bun", "args": ["run", "src/index.ts"] } } }

# 3. Use in Claude Code
# Claude sees delegate() tool and can call it automatically
```

## Requirements

- [Claude Code](https://claude.ai/code) (v2.1.63+)
- [CCS](https://github.com/kaitranntt/ccs) (v7.50+) with at least one provider configured
- [Bun](https://bun.sh) (for MCP server option)

## License

MIT
