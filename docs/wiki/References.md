# References

## Official Anthropic Documentation

| Topic | URL |
|-------|-----|
| Claude Code Headless Mode | https://code.claude.com/docs/en/headless |
| Claude Code Authentication | https://code.claude.com/docs/en/authentication |
| Claude Code LLM Gateway | https://code.claude.com/docs/en/llm-gateway |
| Claude Code Model Configuration | https://code.claude.com/docs/en/model-config |
| Claude Code Environment Variables | https://code.claude.com/docs/en/env-vars |
| Claude Code Subagents | https://code.claude.com/docs/en/sub-agents |
| Claude Code CLI Reference | https://code.claude.com/docs/en/cli-reference |
| Claude Code Agent Teams | https://code.claude.com/docs/en/agent-teams |
| Agent SDK — Subagents | https://code.claude.com/docs/en/agent-sdk/subagents |
| Agent SDK — Overview | https://code.claude.com/docs/en/agent-sdk/overview |
| MCP Sampling Spec | https://modelcontextprotocol.io/docs/concepts/sampling |

## Community Projects — Proxy/Router

| Project | Stars | Description | URL |
|---------|-------|-------------|-----|
| claude-code-router | 32k | Anthropic API proxy, multi-provider | https://github.com/musistudio/claude-code-router |
| claude-code-proxy (1rgs) | 3.4k | LiteLLM-based proxy | https://github.com/1rgs/claude-code-proxy |
| claude-code-proxy (fuergaosi233) | 2.4k | OpenAI proxy | https://github.com/fuergaosi233/claude-code-proxy |
| CCS (Claude Code Switch) | 2k | Multi-provider profile manager | https://github.com/kaitranntt/ccs |
| LiteLLM | 43.5k | Universal LLM gateway | https://github.com/BerriAI/litellm |
| Meridian | 819 | Claude SDK bridge | https://github.com/rynfar/meridian |
| ccproxy-api | 228 | Plugin-based proxy | https://github.com/CaddyGlow/ccproxy-api |

## Community Projects — MCP Subagent Wrappers

| Project | Description | URL |
|---------|-------------|-----|
| pal-mcp-server | CLI wrapper MCP (Codex/Gemini/Claude) | https://github.com/BeehiveInnovations/pal-mcp-server |
| mcp-server-subagent | Multi-CLI dispatcher | https://github.com/dvcrn/mcp-server-subagent |
| Better-OpenCodeMCP | OpenCode CLI wrapper with process pool | https://github.com/ajhcs/Better-OpenCodeMCP |
| opencode-mcp | OpenCode HTTP API wrapper | https://github.com/AlaeddineMessadi/opencode-mcp |
| codex-plugin-cc | Codex plugin for Claude Code | https://github.com/openai/codex-plugin-cc |

## Competitor CLI Research

| Tool | Stars | Key Pattern | URL |
|------|-------|-------------|-----|
| OpenCode | 144k | Per-agent model in frontmatter | https://github.com/sst/opencode |
| Cline | 80k+ | ApiHandler multi-provider | https://github.com/cline/cline |
| Roo Code | - | Sticky Models per mode | https://github.com/RooCodeInc/Roo-Code |
| Aider | - | Architect/Editor 2-model split | https://github.com/Aider-AI/aider |
| Codex CLI | 75k | Per-agent sandbox + MCP | https://github.com/openai/codex |
| Gemini CLI | - | Per-agent tool isolation | https://github.com/google-gemini/gemini-cli |
| Crush | 23k | largeModel + smallModel per agent | https://github.com/charmbracelet/crush |
| goose | 42k | Subagent vs Subrecipe split | https://github.com/block/goose |
| Plandex | - | 9 model roles | https://github.com/plandex-ai/plandex |

## GitHub Issues (Anthropic — Relevant)

| Issue | Topic |
|-------|-------|
| [#38135](https://github.com/anthropics/claude-code/issues/38135) | Multi-provider simultaneously |
| [#38698](https://github.com/anthropics/claude-code/issues/38698) | Per-agent provider routing (14 upvotes) |
| [#1785](https://github.com/anthropics/claude-code/issues/1785) | MCP sampling not implemented |
| [#40326](https://github.com/anthropics/claude-code/issues/40326) | Empty output with proxy split messages |
| [#47298](https://github.com/anthropics/claude-code/issues/47298) | Model name format affects capabilities |
| [#46416](https://github.com/anthropics/claude-code/issues/46416) | Context window for 3rd-party providers |

## Patterns Borrowed from Competitors

| Pattern | Source | Application |
|---------|--------|-------------|
| Architect/Editor split | Aider | Reasoning model plans, cheap model executes (Phase 3) |
| Per-agent tool isolation | Gemini CLI, Codex CLI | tools whitelist in agent frontmatter |
| Sticky Models per mode | Roo Code | defaultModel per agent in config |
| Dual model (large+small) | Crush | primaryModel + summarizerModel (Phase 3) |
| Subagent vs Subrecipe | goose | Ephemeral vs reusable agent patterns |

## Key Quotes from Official Docs

> *"In non-interactive mode (`-p`), the key is always used when present."*
> — [Claude Code Authentication](https://code.claude.com/docs/en/authentication)

> *"without `--bare`, `claude -p` loads the same context an interactive session would, including anything configured in the working directory or `~/.claude`"*
> — [Claude Code Headless Mode](https://code.claude.com/docs/en/headless)

> *"LLM gateways provide a centralized proxy layer between Claude Code and model providers"*
> — [Claude Code LLM Gateway](https://code.claude.com/docs/en/llm-gateway)

> *"Claude Code skips validation for the model ID set in `ANTHROPIC_CUSTOM_MODEL_OPTION`, so you can use any string your API endpoint accepts."*
> — [Claude Code Model Configuration](https://code.claude.com/docs/en/model-config)
