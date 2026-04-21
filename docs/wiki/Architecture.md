# Architecture

## System Overview

```
┌──────────────────────────────────────────────────────────────┐
│  Claude Code Main Session                                     │
│  (Direct to api.anthropic.com, OAuth, SAFE)                   │
│                                                                │
│  Skills: model-router skill loaded in context                 │
│  OR: MCP tool delegate(role, task, model?) available          │
│                                                                │
│  Claude decides to delegate → invokes script or MCP tool      │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  Delegation Layer                                             │
│                                                                │
│  Option A: scripts/delegate.sh                                │
│    - Role → CCS profile mapping (case statement)              │
│    - Constructs ccs command with safety flags                 │
│    - JSONL logging                                            │
│                                                                │
│  Option B: model-router MCP server (Bun + TS)                │
│    ┌─────────────────────────────────────────────┐           │
│    │  MCP Tools: delegate, list_roles, get_usage │           │
│    ├─────────────────────────────────────────────┤           │
│    │  Agent Registry (config/agents.yaml)        │           │
│    ├─────────────────────────────────────────────┤           │
│    │  CCS Spawner (spawn + parse stream-json)    │           │
│    ├─────────────────────────────────────────────┤           │
│    │  Safety (timeout + loop detection)          │           │
│    ├─────────────────────────────────────────────┤           │
│    │  Metrics (SQLite + HTTP /metrics)           │           │
│    └─────────────────────────────────────────────┘           │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  CCS (Claude Code Switch, v7.72+)                             │
│                                                                │
│  ┌──────────────────────────────────────────────┐           │
│  │  Profile Resolution                           │           │
│  │  gemini → CLIProxy OAuth (Google)             │           │
│  │  codex → CLIProxy OAuth (ChatGPT Plus)        │           │
│  │  kimi → CLIProxy OAuth (Moonshot)             │           │
│  │  glm → API key (Zhipu)                        │           │
│  │  ollama → API key (localhost)                  │           │
│  │  custom → API key (any OpenAI-compatible)     │           │
│  └──────────────────────────────────────────────┘           │
│                                                                │
│  ┌──────────────────────────────────────────────┐           │
│  │  CLIProxy Plus (Go binary, singleton :8317)   │           │
│  │  Translates: Anthropic Messages ↔ Provider    │           │
│  │  Shared across all concurrent sessions        │           │
│  └──────────────────────────────────────────────┘           │
│                                                                │
│  Flag passthrough: --agent, --max-turns,                     │
│  --permission-mode, --max-budget-usd, --output-format        │
│  → all forwarded to claude binary unchanged                  │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  Spawned Claude Code Session (separate process)               │
│                                                                │
│  env: ANTHROPIC_BASE_URL=localhost:8317                       │
│       ANTHROPIC_MODEL=gemini-2.5-pro (or gpt-5.3, glm-5.1)  │
│       ANTHROPIC_API_KEY=ccs-internal-managed                  │
│                                                                │
│  Loads natively:                                              │
│  ├─ CLAUDE.md (project + user)                               │
│  ├─ .claude/agents/explorer-fast.md (tools, permissions)     │
│  ├─ Skills (listed in agent frontmatter)                     │
│  ├─ Hooks (from agent frontmatter + settings.json)           │
│  ├─ Permissions (from settings.json)                         │
│  ├─ MCP servers (from agent mcpServers or session config)    │
│  └─ Plugins (from ~/.claude/plugins/)                        │
│                                                                │
│  Agent loop: prompt → model → tool_use → execute → repeat    │
│  Returns: stream-json or json result                         │
└──────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Agent Definitions (.claude/agents/*.md)

Native Claude Code agent files defining per-role behavior:

```markdown
---
name: explorer-fast
description: Quick codebase exploration using external model
tools: [Read, Grep, Glob]
permissionMode: plan
maxTurns: 30
---
You are a fast code explorer. Search efficiently, report findings concisely.
```

### 2. Role → Profile Mapping

Maps agent roles to CCS profiles:

```yaml
# config/agents.yaml
agents:
  explorer-fast:
    ccsProfile: gemini
    agentDef: explorer-fast
    maxTurns: 30
    maxBudgetUsd: 0.50
    timeout: 300

  coder-cheap:
    ccsProfile: codex
    agentDef: coder-cheap
    maxTurns: 50
    maxBudgetUsd: 2.00
    timeout: 600
```

### 3. CCS Profile Types

| Type | Auth | Examples |
|------|------|----------|
| CLIProxy OAuth | Browser OAuth, tokens cached | gemini, codex, kimi, qwen, kiro, ghcp |
| API key | Key in .settings.json | glm, deepseek, openrouter, ollama |
| Account | Claude subscription, isolated config | work, personal |

### 4. Data Flow (single delegation)

```
1. Main Claude → delegate("explorer-fast", "find auth files")
2. Lookup: explorer-fast → ccsProfile=gemini, maxTurns=30, mode=plan
3. Spawn: ccs gemini -p "find auth files" --agent explorer-fast --max-turns 30 --permission-mode plan --output-format json
4. CCS: connect CLIProxy, set env, spawn claude -p with proxy env
5. Claude loads: CLAUDE.md, agent def (tools: R/G/G, mode: plan), hooks
6. Claude sends: POST /v1/messages {model: "gemini-2.5-pro"} → CLIProxy
7. CLIProxy: translate Anthropic→Gemini, forward to Google API
8. Gemini responds → CLIProxy translates back → Claude processes
9. Claude executes tool calls (Read/Grep/Glob), loops until done
10. Claude returns JSON result → CCS exits → delegation layer captures
11. Result returned to main session
```

## Context Inheritance Matrix

| Context | Native CC Subagent | Pure MCP | Spawned CC + CCS |
|---------|-------------------|----------|-------------------|
| CLAUDE.md | Auto | Must self-load | **Auto (100%)** |
| Skills | Auto (if listed) | Must self-load | **Auto (100%)** |
| Hooks fire | Auto | No | **Auto (100%)** |
| Permissions | Auto | Must reimplement | **Auto (100%)** |
| Tool restrictions | Auto | Own impl | **Auto (100%)** |
| Agent memory | Auto | Own impl | **Auto (100%)** |
| Parent MCP tools | Auto | No | **No** (separate process) |
| cwd | Auto | Via env | **Auto (100%)** |

Only gap: parent's MCP tools are not accessible (separate process). Mitigate with per-agent `mcpServers` in frontmatter.
