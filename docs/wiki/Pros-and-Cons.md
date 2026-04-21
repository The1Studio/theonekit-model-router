# Pros and Cons

## Chosen Approach: Spawned CC + CCS

### Pros

| Category | Pro | Detail |
|----------|-----|--------|
| **Context** | 100% CC inheritance | CLAUDE.md, skills, hooks, permissions, agents, plugins all loaded natively — verified by live test |
| **Security** | Zero Anthropic ban risk | Main session stays direct to Anthropic. Spawned sessions use CCS proxy but never authenticate with Anthropic |
| **Providers** | 13+ providers out of box | CCS supports: Gemini, Codex/GPT, Kimi, Qwen, GLM, Kiro, Antigravity, GitHub Copilot, Ollama, OpenRouter, DeepSeek, MiniMax, custom |
| **Subscriptions** | Leverage OAuth subscriptions | ChatGPT Plus (via Codex), Google free tier (via Gemini), Kimi free — no API key needed |
| **Flexibility** | Per-subagent model | Each role maps to different CCS profile/model |
| **Safety** | 8-layer safety model | Tool whitelist, permission mode, hooks, max-turns, max-budget, timeout, loop detection, CC auto-compact |
| **Effort** | Minimal code | ~50 lines (skill) or ~700 lines (MCP). CCS handles proxy, auth, routing, retry, cleanup |
| **Stability** | Official APIs only | Uses only documented Claude Code flags: `-p`, `--agent`, `--max-turns`, `--permission-mode`, `--output-format` |
| **Extensibility** | Custom providers | `ccs api create` for any OpenAI-compatible endpoint |
| **Concurrency** | Parallel safe | CCS CLIProxy is singleton, multiple instances share it safely |

### Cons

| Category | Con | Severity | Mitigation |
|----------|-----|----------|------------|
| **Performance** | ~150-300ms startup per delegation | Medium | Phase 2: session keep-alive pool |
| **Memory** | ~100-150MB per spawned CC process | Medium | Per-provider concurrency limit (default 3) |
| **Dependency** | Relies on CCS (sole maintainer) | Medium | Pin version; fallback: `ccs env` export + spawn claude directly |
| **Determinism** | Skill approach ~90% (Claude interprets) | Low | Upgrade to MCP for 100% determinism |
| **Metrics** | Skill approach has unreliable logging | Low | Use wrapper script or upgrade to MCP |
| **Quality** | Non-Claude models may struggle with CC prompts | Medium | Per-provider prompt adjustments; use strong models for complex roles |
| **MCP tools** | Parent's MCP tools not accessible in subagent | Low | Per-agent `mcpServers` in frontmatter |
| **Translation** | Anthropic↔OpenAI format edge cases | Medium | CCS CLIProxy handles; conformance tests in Phase 4 |
| **CCS updates** | Fast release cadence, potential breaking changes | Low | Pin version, CI tests on CCS updates |

## Comparison: All 10 Approaches Evaluated

| Approach | Context Inherit | Ban Risk | Per-agent Model | Effort | Verdict |
|----------|----------------|----------|-----------------|--------|---------|
| 1. CLI Wrapper | 0% | Zero | Yes | XS | No CC context |
| 2. Anthropic Proxy (global) | 100% | **HIGH** | Hard | M | **Ban risk** |
| 3. Gateway + Thin MCP | 0% | Zero | Yes | S | No agent loop |
| 4. Pure MCP Backend | ~70% | Zero | Yes | M | Must reimplement CC |
| 5. Facade Agent + MCP | ~50% inner | Zero | Yes | M | Cost + complexity |
| 6. MCP + compat lib | ~90% | Zero | Yes | L | Fragile sync |
| 7. Agent SDK external | 100% | Zero | **No** (Claude only) | S | Fails goal |
| 8. Codex Plugin Fork | ~30% | Zero | Partial | M | CLI fragility |
| 9. Tmux Sessions | 100% | Zero | Yes | L | Heavy, poor IPC |
| **10. Spawned CC + CCS** | **100%** | **Zero** | **Yes** | **S-M** | **Chosen** |

## When NOT to Use This Approach

- **Latency-critical tasks** (<100ms needed) — CC process startup adds 150-300ms
- **High-volume batch** (100+ delegations/min) — memory overhead accumulates
- **Tasks needing parent MCP tools** — use native CC subagent instead
- **Tasks needing conversation context from parent** — subagent starts fresh
- **Weak models on complex CC tasks** — CC's system prompt is tuned for Claude; use strong models

## Cost Analysis

| Scenario | Claude (main) | Delegated model | Savings |
|----------|---------------|-----------------|---------|
| Code exploration | Opus ~$15/MTok | Gemini free | **~100%** |
| Simple code gen | Sonnet ~$3/MTok | GPT-4o-mini ~$0.15/MTok | **~95%** |
| Code review | Opus ~$15/MTok | Kimi K2.5 free tier | **~100%** |
| Boilerplate | Sonnet ~$3/MTok | GLM-5.1 (OpenCode Go $10/mo) | **~90%+** |
