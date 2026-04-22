# theonekit-model-router

Multi-model subagent system for Claude Code — delegate tasks to any AI model as subagents with full Claude Code context inheritance.

## Problem

Claude Code only supports Claude models natively. There's no official way to use other AI models as subagents while preserving the full Claude Code ecosystem (CLAUDE.md, skills, hooks, permissions, tools).

## Solution

Spawn separate `claude -p` sessions with different model providers. Each spawned session inherits 100% of Claude Code's context while routing API calls to any provider.

```
Claude Code main session (direct Anthropic, safe)
│
│  /t1k:delegate mr-coder-cheap "implement feature X" --profile kimi
│
├─ mr-delegate.sh:
│   ├─ ANTHROPIC_BASE_URL → provider endpoint
│   ├─ ANTHROPIC_AUTH_TOKEN → auth token
│   └─ claude -p "task" --agent mr-coder-cheap --model kimi-k2.6
│
└─ Result returned to main session
```

## Providers

| Provider | Type | Models | Auth |
|----------|------|--------|------|
| **OpenCode Go** | Local proxy (oc-go-cc) | GLM-5.1, Kimi-K2.5/K2.6, Qwen, MiMo, MiniMax | API key |
| **Kimi** | CCS CLIProxy | kimi-k2, kimi-k2.5, kimi-k2.6 | `gh auth token` |
| **Codex** | CCS CLIProxy | gpt-5.1, o3 | `gh auth token` |

CCS CLIProxy providers route through `ccs.the1studio.org` with GitHub org auth (The1Studio members only).

Check available providers: `curl -H "Authorization: Bearer $(gh auth token)" https://ccs.the1studio.org/providers`

## Install

```bash
# Via TheOneKit
t1k modules add model-router

# post-install.sh runs automatically:
#   - Installs CCS + oc-go-cc
#   - Creates CCS profile
#   - Prompts for API key
#   - Starts proxy
```

## Usage

```bash
# Default (OpenCode Go, local)
/t1k:delegate mr-explorer-fast "find auth files"

# Kimi direct (remote, via ccs.the1studio.org)
/t1k:delegate mr-coder-cheap "implement feature" --profile kimi --model kimi-k2.6

# Override model for any role
/t1k:delegate mr-reviewer-deep "security review" --model glm-5.1
```

## Agent Roles

| Role | Default Model | Mode | Use case |
|------|--------------|------|----------|
| `mr-explorer-fast` | qwen3.5-plus | plan | File discovery, grep, quick lookup |
| `mr-doc-scout` | kimi-k2.5 | plan | Find and read documentation |
| `mr-doc-writer` | kimi-k2.6 | acceptEdits | Write docs, README, comments |
| `mr-coder-cheap` | kimi-k2.6 | acceptEdits | Implement features, boilerplate |
| `mr-reviewer-deep` | glm-5.1 | plan | Code review, security audit |
| `mr-tester` | qwen3.5-plus | plan | Test analysis, test writing |

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
- [CCS](https://github.com/kaitranntt/ccs) (v7.50+)
- [GitHub CLI](https://cli.github.com/) (`gh auth login` with The1Studio org)
- [oc-go-cc](https://github.com/The1Studio/oc-go-cc) (auto-installed)

## Documentation

See the [Wiki](../../wiki) for comprehensive docs.

## License

MIT
