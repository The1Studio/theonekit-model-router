# theonekit-model-router

Multi-model subagent system for Claude Code — delegate tasks to cheaper AI models with full context inheritance.

## Problem

Claude Code uses Claude Opus for everything, including simple tasks like file exploration, docs writing, and boilerplate code. This is expensive and wasteful.

## Solution

Spawn separate `claude -p` sessions routed to cheaper models (Kimi, GLM, Qwen, etc.) while inheriting 100% of Claude Code's context (CLAUDE.md, skills, hooks, permissions, tools).

Two modes:

| Mode | How | Cost |
|------|-----|------|
| **Explicit** (default) | `/t1k:delegate mr-coder-cheap "task"` | Only when you ask |
| **Transparent** | `/t1k:cook "task"` auto-delegates | Automatic for mapped roles |

## Install

```bash
# 1. Login GitHub (The1Studio org required)
gh auth login

# 2. Init project with model-router kit
t1k init --kit model-router

# post-install auto-configures:
#   - CCS + remote CLIProxy (ccs.the1studio.org)
#   - API keys + providers
```

## Usage

### Explicit Delegation (Scenario 2)

Manually delegate specific tasks to cheaper models:

```bash
# Explore codebase with cheap model
/t1k:delegate mr-explorer-fast "find all auth-related files"

# Code review with Kimi
/t1k:delegate mr-reviewer-deep "security review of src/auth.ts" --profile kimi --model kimi-k2.6

# Write docs
/t1k:delegate mr-doc-writer "update README with new API endpoints"

# Implement feature
/t1k:delegate mr-coder-cheap "implement login form validation" --profile kimi
```

### Transparent Routing (Scenario 3)

Enable once, then T1K skills auto-delegate to cheap models:

```bash
# Enable transparent routing
t1k router enable-transparent

# Now these auto-delegate to cheap models:
/t1k:cook "implement feature X"      # → mr-coder-cheap (Kimi K2.6)
/t1k:review "review auth module"     # → mr-reviewer-deep (Kimi K2.6)
/t1k:test "run test suite"           # → mr-tester (Kimi K2.5)
/t1k:docs "update API docs"          # → mr-doc-writer (Kimi K2.6)

# Complex tasks still use Claude (planner, debugger, git-manager)

# Disable when needed
t1k router disable-transparent
```

**How it works:** Routing overlay (priority 92) maps T1K roles → model-router agents. A rule file checks `t1k-config-mr.json` mode — if transparent, delegates via `mr-delegate.sh` instead of spawning Claude agents.

## Agent Roles

| Role | Default Model | Mode | Delegates for |
|------|--------------|------|---------------|
| `mr-explorer-fast` | kimi-k2.5 | read-only | File discovery, codebase exploration |
| `mr-doc-scout` | kimi-k2.5 | read-only | Find and audit documentation |
| `mr-doc-writer` | kimi-k2.6 | write | Write docs, README, comments |
| `mr-coder-cheap` | kimi-k2.6 | write | Implement features, boilerplate |
| `mr-reviewer-deep` | kimi-k2.6 | read-only | Code review, security audit |
| `mr-tester` | kimi-k2.5 | read-only | Run tests, interpret results |

## Providers

| Provider | Models | Auth | Endpoint |
|----------|--------|------|----------|
| **Kimi (direct)** | kimi-k2, k2.5, k2.6 | `gh auth token` | ccs.the1studio.org |
| **Codex** | gpt-5.1, o3 | `gh auth token` | ccs.the1studio.org |
| **OpenCode Go** | GLM, Qwen, MiMo, MiniMax | API key | localhost:3456 |

Check available: `curl -sH "Authorization: Bearer $(gh auth token)" https://ccs.the1studio.org/providers | jq`

## Architecture

```
/t1k:cook "implement feature X" (transparent mode)
  │
  ├─ T1K routing: implementer → mr-coder-cheap (p92 > core p10)
  ├─ Rule: mode=transparent → delegate via mr-delegate.sh
  │
  ├─ mr-delegate.sh:
  │   ├─ gh auth token → validate The1Studio org
  │   ├─ ANTHROPIC_BASE_URL=ccs.the1studio.org/api/provider/kimi
  │   └─ claude -p "task" --agent mr-coder-cheap --model kimi-k2.6
  │       ↓
  │   Cloudflare Tunnel → Auth Proxy → CLIProxy → Kimi API
  │
  └─ Result returned to main session
```

## Safety

8-layer safety model:
1. Tool whitelist per agent role
2. Permission mode (plan/acceptEdits)
3. `MR_SPAWNED` recursive delegation guard
4. `--disallowedTools Agent` (no nested delegation)
5. Max turns per role (25-50)
6. Budget cap per role ($5-$10)
7. Timeout (300s)
8. Write lock (single writer at a time)

## Requirements

- [Claude Code](https://claude.ai/code)
- [GitHub CLI](https://cli.github.com/) (`gh auth login` with The1Studio org)
- [TheOneKit CLI](https://github.com/The1Studio/theonekit-cli) (`t1k`)

CCS + oc-go-cc are auto-installed by post-install.

## Documentation

See the [Wiki](../../wiki) for comprehensive docs:
- [Architecture](../../wiki/Architecture) — system design + CCS CLIProxy flow
- [CCS Integration](../../wiki/CCS-Integration) — auth proxy, providers, remote CLIProxy
- [Safety Model](../../wiki/Safety-Model) — 8-layer protection
- [Agent Roster](../../wiki/Agent-Roster) — all roles with capabilities
- [Telemetry](../../wiki/Telemetry) — event tracking + analytics

## License

MIT
