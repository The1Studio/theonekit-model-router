# model-router Wiki

> Multi-model subagent system for Claude Code — delegate tasks to any AI model with full CC context inheritance.

## Overview

model-router allows Claude Code to delegate tasks to any AI model (GPT, Gemini, GLM, Kimi, Qwen, DeepSeek, Ollama, etc.) as subagents, while preserving **100% of Claude Code's context** (CLAUDE.md, skills, hooks, permissions, tools).

### Core Insight

Instead of building a proxy that intercepts Claude Code's API calls (which risks Anthropic banning your account), we:

1. Keep the **main Claude Code session direct to Anthropic** (safe, untouched)
2. Use [CCS](https://github.com/kaitranntt/ccs) to **spawn separate `claude -p` sessions** with different model providers
3. Each spawned session loads all native CC context (CLAUDE.md, skills, hooks, permissions)
4. CCS handles proxy, auth, and provider routing
5. Main session **never contacts Anthropic through a proxy** → zero ban risk

### Result

| Property | Value |
|----------|-------|
| CC context inheritance | **100%** (CLAUDE.md, skills, hooks, permissions, agents) |
| Anthropic ban risk | **Zero** (main session untouched) |
| Providers supported | **13+** (Gemini, Codex/GPT, Kimi, Qwen, GLM, Ollama, OpenRouter, etc.) |
| Per-subagent model | **Yes** (each role maps to different provider/model) |
| Safety layers | **8** (tools, permissions, hooks, max-turns, budget, timeout, loop detect) |
| Implementation size | **~50 lines** (skill+script) or **~700 lines** (MCP server) |

## Wiki Pages

| Page | Description |
|------|-------------|
| [Approach](Approach) | Chosen approach with evidence and verification |
| [Architecture](Architecture) | System design, flow diagrams, component breakdown |
| [Pros and Cons](Pros-and-Cons) | Comprehensive tradeoff analysis |
| [Implementation Plan](Implementation-Plan) | Phased roadmap with acceptance criteria |
| [Rejected Approaches](Rejected-Approaches) | 9 alternatives evaluated and why they were rejected |
| [CCS Integration](CCS-Integration) | Deep-dive into CCS internals and integration patterns |
| [Safety Model](Safety-Model) | 8-layer safety system explained |
| [References](References) | 30+ sources, official docs, community projects |

## Quick Links

- [GitHub Repository](https://github.com/The1Studio/model-router)
- [CCS (Claude Code Switch)](https://github.com/kaitranntt/ccs)
- [Claude Code Subagents Docs](https://code.claude.com/docs/en/sub-agents)
- [Claude Code Headless Mode](https://code.claude.com/docs/en/headless)
