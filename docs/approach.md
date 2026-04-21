# model-router — Approach Document

> **Status:** Research complete, awaiting Phase 0 approval
> **Date:** 2026-04-17
> **Author:** h3nr1.d14z + Claude

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Goals & Constraints](#2-goals--constraints)
3. [Approaches Evaluated](#3-approaches-evaluated)
4. [Chosen Approach: Spawned CC Session + Local Proxy](#4-chosen-approach-spawned-cc-session--local-proxy)
5. [Architecture](#5-architecture)
6. [How It Works — Step by Step](#6-how-it-works--step-by-step)
7. [Evidence & Verification](#7-evidence--verification)
8. [Safety Model (8 Layers)](#8-safety-model-8-layers)
9. [Context Inheritance Matrix](#9-context-inheritance-matrix)
10. [Config Surface](#10-config-surface)
11. [Provider System (3 Tiers)](#11-provider-system-3-tiers)
12. [Patterns Borrowed from Competitors](#12-patterns-borrowed-from-competitors)
13. [Known Caveats & Mitigations](#13-known-caveats--mitigations)
14. [Implementation Plan (Phases)](#14-implementation-plan-phases)
15. [Rejected Approaches — Why](#15-rejected-approaches--why)
16. [References & Sources](#16-references--sources)

---

## 1. Problem Statement

Claude Code is an excellent agentic CLI, but it only supports Claude models (Anthropic). There is no official way to use other AI models (OpenAI GPT, Google Gemini, GLM, MiniMax, Kimi, Qwen, DeepSeek, etc.) as subagents within Claude Code while preserving the full Claude Code ecosystem (CLAUDE.md, skills, hooks, permissions, tools).

**Goal:** Build a system that allows Claude Code to delegate tasks to any AI model as a subagent, with full context inheritance and zero ban risk.

---

## 2. Goals & Constraints

### Must have
- Per-subagent model selection (different models for different roles)
- Full Claude Code context inheritance (CLAUDE.md, skills, hooks, permissions)
- Zero Anthropic ban risk (main session untouched)
- Multi-provider support (OpenCode Go, OpenAI, Gemini, GLM, MiniMax, Kimi, custom)
- Custom provider support (any OpenAI-compatible endpoint, plugin adapters)
- Configurable agent roles (system prompt, tools, permissions per-role)
- Safety: permission control, infinite loop prevention, cost caps

### Nice to have
- Subscription leverage (ChatGPT Plus via Codex CLI, OpenCode Go, Gemini free)
- Streaming output back to user
- Persistent memory per-agent
- Metrics/analytics (SQLite + HTTP endpoint)
- CLI adapter fallback for subscription-based providers

### Constraints
- Cannot modify Claude Code binary or use unofficial patches
- Cannot set `ANTHROPIC_BASE_URL` on main session (ban risk)
- Must use only official Claude Code APIs and env vars
- OSS-friendly (clean architecture, documented, publishable)

---

## 3. Approaches Evaluated

Nine approaches were researched over multiple rounds. Summary:

| # | Approach | Verdict | Key reason |
|---|---|---|---|
| 1 | CLI Wrapper (slash commands) | Rejected | No CC context, CLI version fragility, config interference |
| 2 | Anthropic API Proxy (global) | **Rejected** | Anthropic bans OAuth login through proxy — high ban risk |
| 3 | Gateway + Thin MCP (LiteLLM) | Rejected | No agent loop (1-shot only), not a real subagent |
| 4 | Pure MCP Backend (mini-agent loop) | Partial | Zero risk but ~0% hooks, ~70% permissions, requires reimplementation |
| 5 | Facade Native Agent + MCP | Rejected | Extra haiku cost, inner layer still no context |
| 6 | MCP + claude-compat Library | Rejected | High build effort, fragile sync with CC updates |
| 7 | External Runtime via Agent SDK | Rejected | SDK only accepts Claude models — fails primary goal |
| 8 | Codex Plugin Fork | Rejected | Bound to CLI, per-CLI parser fragility |
| 9 | Tmux Session per Subagent | Rejected | Heavy startup, IPC via tmux scrape, poor programmatic control |
| **10** | **Spawned CC Session + Local Proxy** | **Chosen** | **100% context, zero ban risk, official APIs only** |

See [Section 15](#15-rejected-approaches--why) for detailed rejection rationale.

---

## 4. Chosen Approach: Spawned CC Session + Local Proxy

### Core Insight

Instead of hacking Claude Code or intercepting its API calls globally, we:

1. Keep the **main Claude Code session direct to Anthropic** (no proxy, no env override, OAuth works normally)
2. Expose an **MCP tool** (`delegate`) that the main session can call
3. When called, the MCP server **spawns a separate `claude -p` process** with:
   - `ANTHROPIC_BASE_URL` pointing to a local proxy
   - `ANTHROPIC_API_KEY` set to a dummy key (proxy accepts any)
   - `ANTHROPIC_MODEL` set to the desired non-Claude model
4. The spawned CC process loads **all native CC context** (CLAUDE.md, skills, hooks, permissions)
5. The local proxy **translates** Anthropic Messages API → OpenAI Chat Completions API and **routes** to the target provider
6. The spawned CC process **never contacts Anthropic** → zero ban risk

### Why This Works

- `ANTHROPIC_API_KEY` bypasses OAuth: *"In non-interactive mode (`-p`), the key is always used when present."* (official docs)
- `claude -p` loads full context: *"without `--bare`, `claude -p` loads the same context an interactive session would"* (official docs)
- `--agent`, `--max-turns`, `--permission-mode`, `--allowedTools` all work in headless mode (verified via `claude --help`)
- Multiple open-source projects confirm the pattern works: `1rgs/claude-code-proxy`, `fuergaosi233/claude-code-proxy`, LiteLLM official docs

---

## 5. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Claude Code Main Session                                     │
│  (Direct to api.anthropic.com, OAuth, SAFE)                   │
│                                                                │
│  User: "explore this codebase for auth patterns"              │
│  Claude: delegates → MCP tool call                            │
│                                                                │
│  mcp__model-router__delegate(                                 │
│    role: "explorer-fast",                                     │
│    task: "find all auth patterns in the codebase",            │
│    model: "glm-5.1"                                           │
│  )                                                             │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  model-router (Bun + TypeScript, MCP stdio server)            │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  MCP Tool Registry                                    │    │
│  │  • delegate(role, task, [model]) — main tool          │    │
│  │  • list_roles() — available agent roles               │    │
│  │  • get_usage() — metrics summary                      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Agent Registry (config/agents.yaml + agents/*.md)    │    │
│  │  Loads role definitions: tools, permissions, hooks,   │    │
│  │  skills, maxTurns, timeout, defaultModel              │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Session Spawner                                      │    │
│  │  • Spawn `claude -p` with custom env vars             │    │
│  │  • Parse stream-json output                           │    │
│  │  • Timeout + cleanup (SIGTERM → grace → SIGKILL)      │    │
│  │  • Keep-alive pool (reuse sessions, Phase 2)          │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Local Proxy (HTTP, localhost:PORT)                    │    │
│  │  • Receive Anthropic Messages API request             │    │
│  │  • Read `model` field from request body               │    │
│  │  • Translate: Anthropic Messages ↔ OpenAI CC format   │    │
│  │  • Route to target provider                           │    │
│  │  • Translate response back to Anthropic format        │    │
│  │  • Stream SSE events                                  │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Provider Registry (config/providers.yaml)            │    │
│  │                                                       │    │
│  │  Tier 1: Built-in API adapters                        │    │
│  │    opencode-go, openai, gemini, zhipu, deepseek, etc. │    │
│  │                                                       │    │
│  │  Tier 2: OpenAI-compatible (any baseUrl + apiKey)     │    │
│  │    ollama, lmstudio, together, fireworks, groq,       │    │
│  │    openrouter, company internal, any custom endpoint  │    │
│  │                                                       │    │
│  │  Tier 3: Plugin adapters (.ts files)                  │    │
│  │    exotic providers with non-standard APIs            │    │
│  │                                                       │    │
│  │  CLI adapters (optional, Phase 2):                    │    │
│  │    codex-cli (ChatGPT Plus subscription)              │    │
│  │    gemini-cli (Google free tier)                       │    │
│  │    opencode-cli (OpenCode Go subscription)            │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Observability                                        │    │
│  │  • SQLite: per-call logs (tokens, cost, duration)     │    │
│  │  • JSONL: event stream for replay                     │    │
│  │  • HTTP /metrics endpoint (Prometheus-compatible)     │    │
│  │  • Open for external backend integration              │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

---

## 6. How It Works — Step by Step

### Step 1: Main session receives user request

User asks Claude Code to do something. Claude (main session, running on Opus/Sonnet via direct Anthropic API) decides the task should be delegated to a cheaper/specialized model.

### Step 2: Claude calls MCP tool

```
mcp__model-router__delegate(
  role: "explorer-fast",
  task: "Find all authentication-related files and patterns in this codebase. Report file paths and key functions.",
  model: "glm-5.1"
)
```

### Step 3: model-router looks up config

```yaml
# Agent config loaded from config/agents.yaml
explorer-fast:
  description: "Quick codebase exploration"
  permissionMode: plan              # read-only
  tools: [Read, Grep, Glob]
  maxTurns: 30
  timeout: 300                      # seconds
  defaultModel: glm-5.1
  skills: [api-conventions]

# Provider config loaded from config/providers.yaml
opencode-go:
  type: api
  format: openai-compatible
  baseUrl: https://api.opencode.ai/v1
  apiKey: ${OPENCODE_GO_API_KEY}
  models: [glm-5.1, kimi-k2.5, qwen3.5-plus]
```

### Step 4: model-router ensures proxy is running

Local proxy starts on `localhost:PORT` (if not already running). Proxy registers routing rule: `model=glm-5.1 → opencode-go provider`.

### Step 5: model-router spawns CC process

```typescript
const proc = spawn('claude', [
  '-p', task,
  '--agent', 'explorer-fast',
  '--max-turns', '30',
  '--permission-mode', 'plan',
  '--output-format', 'stream-json',
  '--max-budget-usd', '0.50',
], {
  env: {
    ANTHROPIC_BASE_URL: `http://localhost:${proxyPort}`,
    ANTHROPIC_API_KEY: 'model-router-proxy-key',
    ANTHROPIC_MODEL: 'glm-5.1',
    PATH: process.env.PATH,
    HOME: process.env.HOME,
  },
  cwd: projectRoot,  // inherit from main session
});
```

### Step 6: Spawned CC process boots

The spawned `claude -p` process:
- Loads `~/.claude/CLAUDE.md` and `.claude/CLAUDE.md`
- Loads `.claude/agents/explorer-fast.md` (if exists, for hooks/skills)
- Loads skills listed in agent frontmatter
- Activates hooks from agent definition
- Connects to `http://localhost:PORT` (proxy) instead of `api.anthropic.com`
- Sends API key via `X-Api-Key` header (OAuth completely skipped)

### Step 7: CC sends API request through proxy

```
POST http://localhost:PORT/v1/messages
Headers:
  X-Api-Key: model-router-proxy-key
  anthropic-version: 2023-06-01
  anthropic-beta: ...
Body:
  {
    "model": "glm-5.1",
    "max_tokens": 8192,
    "system": [{ "text": "...(CC system prompt + CLAUDE.md + skills)..." }],
    "messages": [{ "role": "user", "content": "Find all auth patterns..." }],
    "tools": [
      { "name": "Read", "description": "...", "input_schema": {...} },
      { "name": "Grep", "description": "...", "input_schema": {...} },
      { "name": "Glob", "description": "...", "input_schema": {...} }
    ]
  }
```

### Step 8: Proxy translates and routes

Proxy receives the request, sees `model: "glm-5.1"`:
1. Translates Anthropic Messages format → OpenAI Chat Completions format
2. Maps tool definitions: Anthropic `tools` → OpenAI `functions`/`tools`
3. Forwards to OpenCode Go endpoint: `https://api.opencode.ai/v1/chat/completions`
4. Receives OpenAI-format response
5. Translates back to Anthropic Messages format
6. Returns to spawned CC process

### Step 9: CC agent loop executes

The spawned CC process receives the response, executes any tool calls (Read/Grep/Glob), sends results back through the proxy, continues the loop until the task is complete or `maxTurns` is reached.

### Step 10: Result returns to main session

model-router parses the `stream-json` output from the spawned process, extracts the final result text, logs metrics to SQLite, and returns the result as the MCP tool response. Main Claude Code session presents the result to the user.

---

## 7. Evidence & Verification

### Confirmed by official documentation

| Claim | Source | Quote |
|---|---|---|
| API key bypasses OAuth in `-p` mode | [/en/authentication](https://code.claude.com/docs/en/authentication) | *"In non-interactive mode (`-p`), the key is always used when present."* |
| `-p` loads full context (CLAUDE.md, hooks, skills) | [/en/headless](https://code.claude.com/docs/en/headless) | *"without `--bare`, `claude -p` loads the same context an interactive session would"* |
| `ANTHROPIC_BASE_URL` is officially supported | [/en/llm-gateway](https://code.claude.com/docs/en/llm-gateway) | *"LLM gateways provide a centralized proxy layer between Claude Code and model providers"* |
| `ANTHROPIC_CUSTOM_MODEL_OPTION` skips validation | [/en/model-config](https://code.claude.com/docs/en/model-config) | *"Claude Code skips validation for the model ID set in `ANTHROPIC_CUSTOM_MODEL_OPTION`"* |
| `--agent`, `--max-turns`, `--permission-mode` work in headless | `claude --help` output | Flags documented with "(print mode only)" or no restriction |
| `--max-budget-usd` caps spending | `claude --help` output | *"Maximum dollar amount to spend on API calls (only works with --print)"* |

### Confirmed by community projects

| Project | Stars | Pattern | Status |
|---|---|---|---|
| [1rgs/claude-code-proxy](https://github.com/1rgs/claude-code-proxy) | 3.4k | `ANTHROPIC_BASE_URL` + LiteLLM proxy | Working |
| [fuergaosi233/claude-code-proxy](https://github.com/fuergaosi233/claude-code-proxy) | 2.4k | `ANTHROPIC_BASE_URL` + OpenAI proxy | Active |
| [musistudio/claude-code-router](https://github.com/musistudio/claude-code-router) | 32k | Full routing proxy | Active (880 issues) |
| LiteLLM official docs | 43.5k | `ANTHROPIC_BASE_URL=litellm-server` | Documented |

### Critical difference from these projects

All existing projects set `ANTHROPIC_BASE_URL` **globally** on the main session → **ban risk**. Our approach sets it **only on spawned subagent sessions** → main session never touches proxy → **zero ban risk**.

---

## 8. Safety Model (8 Layers)

### Layer 1: Tool whitelist (agent definition)

```yaml
explorer-fast:
  tools: [Read, Grep, Glob]  # ONLY these 3 tools available
```

CC enforces at engine level. Model never sees Edit/Write/Bash tool definitions.

### Layer 2: Permission mode (CLI flag)

```
--permission-mode plan    # read-only, no edits
--permission-mode dontAsk # auto-deny all permission prompts
--permission-mode acceptEdits # auto-accept edits in cwd only
```

### Layer 3: Allowed/disallowed tools (CLI flag)

```
--allowedTools "Read,Grep,Glob"
--disallowedTools "Agent,Write"
```

CLI-level override, stacks with agent definition.

### Layer 4: Hooks (agent frontmatter)

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-safe-command.sh"
```

Custom validation scripts. Exit code 2 = block operation.

### Layer 5: Max turns (CLI flag)

```
--max-turns 30  # hard stop after 30 agentic turns
```

CC stops agent loop cleanly when limit reached.

### Layer 6: Budget cap (CLI flag)

```
--max-budget-usd 0.50  # max $0.50 per delegation
```

Built-in CC feature, print mode only.

### Layer 7: Process timeout (model-router)

```typescript
setTimeout(() => {
  proc.kill('SIGTERM');
  setTimeout(() => proc.kill('SIGKILL'), 5000);
}, config.timeout * 1000);
```

model-router kills spawned process after configured timeout.

### Layer 8: Loop detection (proxy)

```typescript
// Detect 3+ identical consecutive tool calls → abort
if (isRepeatingToolCall(call, history, 3)) {
  return { error: 'Loop detected, stopping agent' };
}
```

Proxy monitors tool call patterns and breaks infinite loops.

---

## 9. Context Inheritance Matrix

| Context | Native CC subagent | Pure MCP | **Spawned CC + Proxy** |
|---|---|---|---|
| CLAUDE.md (project + user) | Auto | Must self-load | **Auto (100%)** |
| Skills | Auto (if listed) | Must self-load | **Auto (100%)** |
| Hooks (PreToolUse, PostToolUse) | Auto fire | Not fire | **Auto fire (100%)** |
| Permissions (settings.json) | Auto | Must reimplement | **Auto (100%)** |
| Tool restrictions (per-agent) | Auto | Own impl | **Auto (100%)** |
| Agent memory (persistent) | Auto | Own impl | **Auto (100%)** |
| MCP tools from parent session | Auto | Not accessible | **Not accessible** |
| cwd (working directory) | Auto | Via env | **Via cwd param (100%)** |
| Conversation history from parent | Not shared | Not shared | **Not shared** |

**Only gap:** Parent's MCP tools are not accessible in spawned session (separate process). If a subagent needs specific MCP tools, configure them in the agent's `mcpServers` frontmatter or via `--mcp-config` CLI flag.

---

## 10. Config Surface

### Agent definitions

Two formats, used together:

**config/agents.yaml** — Quick config for all agents:
```yaml
agents:
  explorer-fast:
    description: "Quick codebase exploration, read-only"
    permissionMode: plan
    tools: [Read, Grep, Glob]
    maxTurns: 30
    timeout: 300
    defaultModel: glm-5.1
    maxBudgetUsd: 0.50
    skills: []

  coder-cheap:
    description: "General coding tasks with full file access"
    permissionMode: acceptEdits
    tools: [Read, Edit, Write, Bash, Grep, Glob]
    maxTurns: 50
    timeout: 600
    defaultModel: gpt-4o-mini
    maxBudgetUsd: 2.00
    skills: [api-conventions]
    hooks:
      PreToolUse:Bash: "./scripts/validate-safe-command.sh"

  reviewer-deep:
    description: "Deep code review with reasoning model"
    permissionMode: plan
    tools: [Read, Grep, Glob, Bash]
    maxTurns: 40
    timeout: 600
    defaultModel: mimo-v2-pro
    maxBudgetUsd: 1.00

  researcher:
    description: "Research tasks with long context"
    permissionMode: plan
    tools: [Read, Grep, Glob]
    maxTurns: 30
    timeout: 300
    defaultModel: kimi-k2.5
```

**config/agents/*.md** — Extended config with long system prompts:
```markdown
---
name: coder-cheap
description: General coding tasks with full file access
permissionMode: acceptEdits
tools: [Read, Edit, Write, Bash, Grep, Glob]
maxTurns: 50
timeout: 600
defaultModel: gpt-4o-mini
maxBudgetUsd: 2.00
skills: [api-conventions]
---

You are an expert software engineer focused on writing clean, efficient code.

When implementing changes:
1. Read existing code first to understand patterns
2. Follow existing conventions
3. Write tests for new functionality
4. Run linting after changes

Focus on minimal, correct implementations. Do not over-engineer.
```

When both exist, `.md` file takes precedence (can override YAML values).

### Provider definitions

**config/providers.yaml:**
```yaml
providers:
  # ─── Tier 1: Built-in API adapters ───
  opencode-go:
    type: api
    format: openai-compatible
    baseUrl: https://api.opencode.ai/v1
    apiKey: ${OPENCODE_GO_API_KEY}
    models:
      - glm-5.1
      - kimi-k2.5
      - mimo-v2-pro
      - qwen3.5-plus
      - minimax-text
    concurrency: 3        # max concurrent requests
    rateLimit: 200/5h     # per subscription tier

  openai:
    type: api
    format: openai-compatible
    baseUrl: https://api.openai.com/v1
    apiKey: ${OPENAI_API_KEY}
    models: [gpt-4o, gpt-4o-mini, gpt-5-mini, o4-mini]
    concurrency: 5

  gemini:
    type: api
    format: openai-compatible
    baseUrl: https://generativelanguage.googleapis.com/v1beta/openai
    apiKey: ${GEMINI_API_KEY}
    models: [gemini-2.5-pro, gemini-2.5-flash]
    concurrency: 3

  # ─── Tier 2: OpenAI-compatible custom ───
  my-ollama:
    type: custom
    format: openai-compatible
    baseUrl: http://localhost:11434/v1
    apiKey: ollama
    models: [llama-3.3-70b, qwen3-32b]

  company-internal:
    type: custom
    format: openai-compatible
    baseUrl: https://llm.internal.company.com/v1
    apiKey: ${INTERNAL_LLM_KEY}
    models: [internal-coder-v2]

  together-ai:
    type: custom
    format: openai-compatible
    baseUrl: https://api.together.xyz/v1
    apiKey: ${TOGETHER_API_KEY}
    models: [meta-llama/Llama-3.3-70B-Instruct]

  openrouter:
    type: custom
    format: openai-compatible
    baseUrl: https://openrouter.ai/api/v1
    apiKey: ${OPENROUTER_API_KEY}
    models: ["*"]  # any model via OpenRouter

  # ─── Tier 3: Plugin adapter ───
  exotic-provider:
    type: plugin
    path: ./plugins/exotic-adapter.ts
    config:
      endpoint: https://exotic-ai.example.com
      authType: bearer

  # ─── CLI adapters (Phase 2, optional) ───
  codex-cli:
    type: cli
    command: codex
    args: ["-q", "--json"]
    auth: chatgpt-oauth     # uses local codex auth state
    models: [gpt-4o, o4-mini]

  gemini-cli:
    type: cli
    command: gemini
    auth: google-oauth
    models: [gemini-2.5-pro, gemini-2.5-flash]
```

### Environment variables (.env)

```env
# Provider API keys
OPENCODE_GO_API_KEY=your-key-here
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=AIza...
ZHIPU_API_KEY=...
TOGETHER_API_KEY=...
OPENROUTER_API_KEY=sk-or-...

# model-router settings
MODEL_ROUTER_PROXY_PORT=3456
MODEL_ROUTER_METRICS_PORT=9876
MODEL_ROUTER_LOG_LEVEL=info
MODEL_ROUTER_DB_PATH=~/.model-router/metrics.db
```

---

## 11. Provider System (3 Tiers)

### Tier 1: Built-in API adapters

Pre-configured providers with known quirks handled. Ship with model-router.

Examples: OpenCode Go, OpenAI, Google Gemini, Zhipu (GLM), DeepSeek, Moonshot (Kimi), MiniMax.

### Tier 2: OpenAI-compatible custom

Any endpoint that speaks OpenAI's `/v1/chat/completions` API. User provides `baseUrl` + `apiKey` + `models` list — model-router auto-creates an adapter.

Covers: Ollama, LMStudio, vLLM, Together AI, Fireworks, Groq, Perplexity, OpenRouter, company-internal gateways, any custom endpoint.

### Tier 3: Plugin adapters

For providers with non-standard APIs. User writes a TypeScript file implementing the `ProviderAdapter` interface:

```typescript
// plugins/exotic-adapter.ts
import type { ProviderAdapter, AgentTask, AgentResult } from 'model-router';

export default class ExoticAdapter implements ProviderAdapter {
  id = 'exotic';
  type = 'plugin' as const;

  async execute(task: AgentTask): Promise<AgentResult> {
    // Custom API call logic
  }

  async healthCheck() {
    // Verify connectivity
  }

  async listModels() {
    // Return available models
  }
}
```

model-router dynamically imports plugin files at startup.

### CLI adapters (Phase 2)

For subscription-based providers where CLI is the only way to leverage the subscription (e.g., ChatGPT Plus via Codex CLI). These spawn the provider's CLI instead of calling an API.

Note: CLI adapters are optional and have known trade-offs (startup latency, output parsing fragility, config interference). See [Section 15](#15-rejected-approaches--why) for details.

---

## 12. Patterns Borrowed from Competitors

### From Aider: Architect/Editor split

Two-model serial pipeline — reasoning model plans, cheap model formats edits. Achieves 85% SOTA on benchmarks, beating single-model.

**How we apply:** Agent config supports `architectModel` + `editorModel` (Phase 3).

### From Codex CLI / Gemini CLI: Per-agent tool isolation + sandbox

Each subagent gets explicit tool allowlist. Codex enforces `sandbox_mode: "read-only"` at OS level.

**How we apply:** `tools` whitelist per agent + `--permission-mode plan` for read-only agents.

### From Roo Code: Sticky models per mode

Harness remembers last user-overridden model per agent role.

**How we apply:** `defaultModel` per agent in config, overridable per-call via `model` parameter.

### From Crush: Dual model per agent (large + small)

Every agent has `primaryModel` (reasoning) + `summarizerModel` (titles/summaries).

**How we apply:** Phase 3 — `summarizerModel` in agent config for cost reduction on metadata ops.

---

## 13. Known Caveats & Mitigations

### Caveat 1: Agent frontmatter `model:` field doesn't accept arbitrary model IDs

CC validates model names in agent frontmatter against known Anthropic models.

**Mitigation:** Set model via `ANTHROPIC_MODEL` or `ANTHROPIC_CUSTOM_MODEL_OPTION` env var when spawning. The proxy sees the model name in the request body and routes accordingly.

### Caveat 2: API format translation edge cases

Translating Anthropic Messages ↔ OpenAI Chat Completions has known issues:
- Thinking blocks (no equivalent in OpenAI) — skip/strip
- `cache_control` (Anthropic-specific) — skip
- Split assistant messages cause empty output (CC issue #40326)
- Model name format affects capability detection (CC issue #47298)

**Mitigation:** Build conformance test suite. Test each provider against known CC behaviors. Track translation fidelity per (provider × feature) matrix.

### Caveat 3: Non-Claude models may struggle with CC's system prompt

CC's system prompt is optimized for Claude's tool-use behavior. Other models may:
- Misformat tool calls
- Hallucinate tool names
- Not follow complex instructions as precisely

**Mitigation:** Per-provider system prompt adjustments in proxy (prepend/append hints). Strong models (GPT-4o, Gemini 2.5 Pro, GLM-5.1) handle tool calling well. Weak models should only be used for simple roles (explorer, read-only).

### Caveat 4: Startup latency (~150-300ms per delegation)

Each delegation spawns a new `claude -p` process.

**Mitigation (Phase 2):** Session keep-alive pool — reuse spawned CC processes for multiple calls. Use `--resume` flag to continue existing sessions.

### Caveat 5: Memory per subagent (~100-150MB per CC process)

Each spawned process is a full CC runtime.

**Mitigation:** Per-provider concurrency limit (default 3). Process cleanup after timeout/completion. Session pool with max size.

### Caveat 6: Parent MCP tools not accessible

Spawned CC is a separate process — cannot access parent's MCP tools (`chrome-devtools`, `hexstrike`, etc.).

**Mitigation:** If subagent needs specific MCP tools, configure them in agent's `.md` frontmatter (`mcpServers:` field) or pass via `--mcp-config` CLI flag.

---

## 14. Implementation Plan (Phases)

### Phase 0: Documentation + Scaffold (current)

**Deliverables:**
- [x] `docs/approach.md` (this file)
- [ ] `docs/architecture.md` (diagrams)
- [ ] `docs/phases.md` (detailed per-phase plan with acceptance criteria)
- [ ] `docs/adr/` (architecture decision records)
- [ ] Project scaffold: `package.json`, `tsconfig.json`, `bunfig.toml`
- [ ] `src/` directory structure (empty files with interfaces)
- [ ] `config/` examples
- [ ] `README.md` (quickstart)
- [ ] `.env.example`

**Acceptance:** Docs reviewed and approved. No code logic yet.

### Phase 1: MVP — Single Provider (OpenCode Go)

**Deliverables:**
- Local proxy: translate Anthropic ↔ OpenAI, 1 provider (OpenCode Go)
- Session spawner: spawn `claude -p` with custom env
- Stream-json parser: extract result from NDJSON events
- MCP server: expose `delegate(role, task, model)` tool
- Agent registry: load from `config/agents.yaml`
- Provider registry: load OpenCode Go from `config/providers.yaml`
- 1 pre-defined agent role: `explorer-fast` (read-only, GLM-5.1)
- Basic error handling + timeout

**Acceptance:**
- Claude Code main session can call `delegate("explorer-fast", "find auth files")` via MCP
- Spawned CC process connects to proxy, queries GLM-5.1, executes tools, returns result
- Main session receives text result
- CLAUDE.md content visible in spawned session's system prompt (verify via proxy log)
- `--max-turns` correctly limits execution

### Phase 2: Multi-Provider + Agent Roles

**Deliverables:**
- Add providers: OpenAI API, Gemini API, Zhipu API
- Tier 2 support: any OpenAI-compatible endpoint
- 3+ pre-defined agent roles: explorer, coder, reviewer
- Per-agent model override (`model` parameter in MCP call)
- Per-provider concurrency limit with queue
- SQLite metrics logging
- JSONL event log
- CLI adapter: OpenCode Go CLI (subscription)

**Acceptance:**
- All Tier 1 + Tier 2 providers working
- Concurrent delegations limited correctly
- Metrics queryable from SQLite

### Phase 3: Advanced Agent Features

**Deliverables:**
- Agent markdown files (long system prompts)
- Tier 3 plugin adapters
- Architect/Editor dual-model split
- Session keep-alive pool (reuse spawned processes)
- HTTP metrics endpoint (Prometheus format)
- Agent `mcpServers` passthrough (per-agent MCP tools)
- Hot-reload config (watch file changes)

**Acceptance:**
- Plugin adapter loads and executes correctly
- Keep-alive reduces latency by >50%
- Metrics endpoint returns Prometheus format

### Phase 4: Polish + OSS

**Deliverables:**
- Streaming output via MCP progress notifications
- Conformance test suite (provider × CC-feature matrix)
- npm package publishable
- Comprehensive README with examples
- CI/CD (GitHub Actions)
- Contributor guide

**Acceptance:**
- `npm install -g model-router` works
- Conformance tests pass for all Tier 1 providers
- README has quickstart that works in <5 minutes

---

## 15. Rejected Approaches — Why

### #1 CLI Wrapper (slash commands wrapping codex/gemini-cli/etc.)
- No CC context inheritance (CLAUDE.md, skills, hooks)
- CLI version changes break parsers (user's primary concern)
- Config interference if user also uses CLI standalone
- Output parsing fragile (per-CLI format)

### #2 Anthropic API Proxy (global ANTHROPIC_BASE_URL)
- **Anthropic bans OAuth login through proxy** — high ban risk
- Projects like CCS (`kaitranntt/ccs`) and claude-code-router (`musistudio/claude-code-router`) run this pattern, but risk account ban for subscription users
- No way to selectively proxy (all requests go through, including main session)

### #3 Gateway + Thin MCP (LiteLLM wrapper)
- No agent loop — 1-shot prompt/response only
- Cannot delegate multi-step tasks (no tool-use loop)
- Not a "subagent", just an "ask for opinion" tool

### #4 Pure MCP Backend (custom mini-agent loop)
- Zero ban risk, but:
- Hooks don't fire (~0% coverage)
- Permissions must be reimplemented (~70%)
- CLAUDE.md must be self-loaded (~95%)
- Skills must be self-loaded (~90%)
- Significant reimplementation of CC features
- Drift risk when CC updates config formats

### #5 Facade Native Agent + MCP
- Extra haiku token cost per delegation (~1-3k tokens)
- Inner layer (MCP) still doesn't inherit context
- Debug complexity: 2 layers, split logs
- Latency: 2 hops

### #6 MCP + claude-compat Library
- Highest build effort of all approaches
- Must reverse-engineer CC config parsing
- Fragile sync when CC updates formats
- Diminishing returns vs. spawned CC session approach

### #7 External Runtime via Agent SDK
- **SDK only accepts Claude models** — no custom LLM provider hook
- Fails primary goal of multi-provider support

### #8 Codex Plugin Fork
- Bound to CLI per-provider
- Per-CLI parser fragility (same issue as #1)
- Generalization effort ≈ building #4 from scratch

### #9 Tmux Session per Subagent
- Heavy startup (full CLI process per pane)
- IPC via tmux pane scraping — fragile, slow
- Poor programmatic control
- Resource intensive (RAM per pane)

---

## 16. References & Sources

### Official Anthropic Documentation
- [Claude Code Headless Mode](https://code.claude.com/docs/en/headless)
- [Claude Code Authentication](https://code.claude.com/docs/en/authentication)
- [Claude Code LLM Gateway](https://code.claude.com/docs/en/llm-gateway)
- [Claude Code Model Configuration](https://code.claude.com/docs/en/model-config)
- [Claude Code Environment Variables](https://code.claude.com/docs/en/env-vars)
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents)
- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference)
- [Agent SDK — Subagents](https://code.claude.com/docs/en/agent-sdk/subagents)
- [MCP Sampling Spec](https://modelcontextprotocol.io/docs/concepts/sampling)

### Community Projects (verified)
- [musistudio/claude-code-router](https://github.com/musistudio/claude-code-router) — 32k stars, Anthropic API proxy
- [1rgs/claude-code-proxy](https://github.com/1rgs/claude-code-proxy) — 3.4k stars, LiteLLM-based proxy
- [fuergaosi233/claude-code-proxy](https://github.com/fuergaosi233/claude-code-proxy) — 2.4k stars, OpenAI proxy
- [rynfar/meridian](https://github.com/rynfar/meridian) — 819 stars, Claude SDK bridge
- [BeehiveInnovations/pal-mcp-server](https://github.com/BeehiveInnovations/pal-mcp-server) — CLI wrapper MCP
- [dvcrn/mcp-server-subagent](https://github.com/dvcrn/mcp-server-subagent) — Multi-CLI MCP dispatcher
- [ajhcs/Better-OpenCodeMCP](https://github.com/ajhcs/Better-OpenCodeMCP) — OpenCode CLI wrapper
- [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — Codex plugin for CC
- [kaitranntt/ccs](https://github.com/kaitranntt/ccs) — Claude Code Switch (multi-provider CLI)
- [BerriAI/litellm](https://github.com/BerriAI/litellm) — 43.5k stars, LLM gateway

### Competitor CLI Research
- [sst/opencode](https://github.com/sst/opencode) — 144k stars, multi-provider native
- [cline/cline](https://github.com/cline/cline) — VS Code extension, multi-provider
- [RooCodeInc/Roo-Code](https://github.com/RooCodeInc/Roo-Code) — Cline fork, sticky models
- [Aider-AI/aider](https://github.com/Aider-AI/aider) — Architect/Editor split
- [openai/codex](https://github.com/openai/codex) — 75k stars, Rust CLI, per-agent sandbox
- [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) — per-agent tool isolation
- [charmbracelet/crush](https://github.com/charmbracelet/crush) — 23k stars, dual model per agent
- [block/goose](https://github.com/block/goose) — 42k stars, subagent vs subrecipe
- [plandex-ai/plandex](https://github.com/plandex-ai/plandex) — 9 model roles

### GitHub Issues (Anthropic)
- [#38135](https://github.com/anthropics/claude-code/issues/38135) — Multi-provider simultaneously
- [#38698](https://github.com/anthropics/claude-code/issues/38698) — Per-agent provider routing (14 upvotes)
- [#1785](https://github.com/anthropics/claude-code/issues/1785) — MCP sampling not implemented
- [#40326](https://github.com/anthropics/claude-code/issues/40326) — Empty output with split assistant messages via proxy
- [#47298](https://github.com/anthropics/claude-code/issues/47298) — Model name format affects capability detection
- [#46416](https://github.com/anthropics/claude-code/issues/46416) — Context window detection for 3rd-party providers

---

*Last updated: 2026-04-17*
