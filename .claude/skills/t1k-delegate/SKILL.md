---
name: t1k:delegate
description: "Delegate tasks to cheaper/specialized AI models via OpenCode Go. Use when a task is self-contained and doesn't need Opus-level reasoning — exploration, docs, boilerplate code, reviews, tests."
keywords: [delegate, cheap model, opencode, route, subagent, explore cheap, review cheap, code cheap, test cheap, delegate to cheap, use cheap model, use opencode go]
argument-hint: "<role> \"<task>\" [--model <model>] [--profile <profile>]"
effort: low
version: 0.3.0
origin: theonekit-model-router
repository: The1Studio/theonekit-model-router
module: model-router
protected: false
---

## How Model Selection Works

**You (Claude) decide which model to use.** Before delegating:

1. Read `.claude/model-capabilities.md` for model strengths, costs, and guidelines
2. Read `.claude/providers-config.json` to check which models/providers are enabled
3. Choose the best model for the task (consider complexity, context size, cost)
4. Pass your choice via `--model <model>` flag

**Default models per role** are set in `scripts/mr-delegate.sh` but you can (and should) override when the task warrants a different model.

## Available Roles

| Role | Default model | Permissions | Best for |
|------|--------------|-------------|----------|
| `mr-explorer-fast` | qwen3.5-plus | Read-only | File discovery, pattern search, codebase navigation |
| `mr-doc-scout` | kimi-k2.5 | Read-only | Doc audit, gap analysis, stale section detection |
| `mr-doc-writer` | kimi-k2.6 | Edit docs only | Write/update documentation, README, wiki |
| `mr-coder-cheap` | kimi-k2.6 | Full access | Code implementation per plan, bug fixes, boilerplate |
| `mr-reviewer-deep` | glm-5.1 | Read-only + Bash | Security review, architecture analysis, deep reasoning |
| `mr-tester` | qwen3.5-plus | Read-only + Bash | Run test suite, interpret results, report failures |

## How to Delegate

```bash
bash scripts/mr-delegate.sh <role> "<task>" [--model <model>]
```

### Model selection examples

```bash
# Simple file search → cheapest model
bash scripts/mr-delegate.sh mr-explorer-fast "list all .ts files" --model qwen3.5-plus

# Complex exploration → upgrade to better model
bash scripts/mr-delegate.sh mr-explorer-fast "analyze auth architecture and map all dependencies" --model kimi-k2.6

# Large codebase review → long context model
bash scripts/mr-delegate.sh mr-reviewer-deep "review entire src/ directory" --model minimax-m2.7

# Quick boilerplate → cheap model
bash scripts/mr-delegate.sh mr-coder-cheap "add standard error handling to all API routes" --model qwen3.6-plus

# Critical security review → best reasoning model
bash scripts/mr-delegate.sh mr-reviewer-deep "audit auth module for OWASP Top 10" --model glm-5.1
```

### Model quick reference

| Need | Model | Why |
|------|-------|-----|
| Cheapest possible | `qwen3.5-plus` | 10K req/5hr, basic quality |
| Best balance | `kimi-k2.6` | Good quality + reasonable cost |
| Best reasoning | `glm-5.1` | Complex tasks, worth the cost |
| Long context (1M) | `minimax-m2.7` | Large file analysis |
| Fast prototyping | `mimo-v2-pro` | Quick code generation |

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
