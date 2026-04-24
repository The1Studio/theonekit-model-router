---
name: t1k:delegate
description: "Delegate tasks to cheaper/specialized AI models via model-router. Use when a task is self-contained and doesn't need Opus-level reasoning — exploration, docs, boilerplate code, reviews, tests."
keywords: [delegate, cheap model, opencode, route, subagent, explore cheap, review cheap, code cheap, test cheap, delegate to cheap, use cheap model, use opencode go]
argument-hint: "<role> \"<task>\" --provider <provider> --model <model>"
effort: low
version: 0.6.2
origin: theonekit-model-router
repository: The1Studio/theonekit-model-router
module: model-router
protected: false
---

## How Model Selection Works

**You (Claude) decide which provider and model to use.** Before delegating:

1. Read `.claude/model-capabilities.md` for model strengths, costs, and guidelines
2. Read `.claude/providers-config.json` to check which providers/models are available
3. Choose the best provider + model for the task (consider complexity, context size, cost)
4. Pass your choice via `--provider <provider> --model <model>` flags

There are **no defaults** — you MUST pass `--provider` and `--model` every time.

## Available Roles

| Role | Permissions | Best for |
|------|-------------|----------|
| `mr-explorer-fast` | Read-only | File discovery, pattern search, codebase navigation |
| `mr-doc-scout` | Read-only | Doc audit, gap analysis, stale section detection |
| `mr-doc-writer` | Edit docs only | Write/update documentation, README, wiki |
| `mr-coder-cheap` | Full access | Code implementation per plan, bug fixes, boilerplate |
| `mr-reviewer-deep` | Read-only + Bash | Security review, architecture analysis, deep reasoning |
| `mr-tester` | Read-only + Bash | Run test suite, interpret results, report failures |

## How to Delegate

```bash
bash .claude/scripts/mr-delegate.sh <role> "<task>" --provider <provider> --model <model>
```

### Model selection examples

```bash
# Simple file search — cheapest model via opencode-go
bash .claude/scripts/mr-delegate.sh mr-explorer-fast "list all .ts files" --provider opencode-go --model qwen3.5-plus

# Complex exploration — upgrade to better model
bash .claude/scripts/mr-delegate.sh mr-explorer-fast "analyze auth architecture and map all dependencies" --provider kimi --model kimi-k2.6

# Large codebase review — long context model
bash .claude/scripts/mr-delegate.sh mr-reviewer-deep "review entire src/ directory" --provider opencode-go --model minimax-m2.7

# Quick boilerplate — cheap model
bash .claude/scripts/mr-delegate.sh mr-coder-cheap "add standard error handling to all API routes" --provider opencode-go --model qwen3.6-plus

# Critical security review — best reasoning model
bash .claude/scripts/mr-delegate.sh mr-reviewer-deep "audit auth module for OWASP Top 10" --provider opencode-go --model glm-5.1
```

### Model quick reference

| Need | Model | Provider | Why |
|------|-------|----------|-----|
| Cheapest possible | `qwen3.5-plus` | opencode-go | 10K req/5hr, basic quality |
| Best balance | `kimi-k2.6` | kimi or opencode-go | Good quality + reasonable cost |
| Best reasoning | `glm-5.1` | opencode-go | Complex tasks, worth the cost |
| Long context (1M) | `minimax-m2.7` | opencode-go | Large file analysis |
| Fast prototyping | `mimo-v2-pro` | opencode-go | Quick code generation |

> Full details: read `.claude/model-capabilities.md`

## When to Delegate vs Keep

**Delegate** (use this skill):
- Codebase exploration and file search
- Documentation audit and writing
- Boilerplate code generation
- Simple bug fixes with clear scope
- Code review (non-critical)
- Running test suites
- Repetitive tasks across many files

**Keep in main session** (use Claude directly):
- Architecture decisions and system design
- Security-critical code changes
- Multi-step refactors needing conversation context
- Complex debugging with iterative reasoning
- Tasks requiring parent MCP tools (chrome-devtools, etc.)

## Safety

Every delegation enforces:
- Tool whitelist per role (explorer can't edit, coder can't spawn subagents)
- Permission mode (plan=read-only, acceptEdits=cwd only)
- Max turns (hard stop per role)
- Budget cap (max USD per call)
- Timeout (5 minutes default)
- No nested delegation (MR_SPAWNED guard)
- Write lock (only 1 write-capable agent at a time)
- Telemetry (events sent to T1K cloud for monitoring)

## Logs & Telemetry

- Local logs: `~/.model-router/calls.jsonl`
- Tool usage: `~/.model-router/tool-usage.jsonl`
- Proxy telemetry: `~/.model-router/telemetry.jsonl` (WAL, flushed to cloud every 60s)
