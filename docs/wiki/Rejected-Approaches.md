# Rejected Approaches

9 approaches were evaluated before choosing "Spawned CC Session + CCS". Each was rejected for specific, evidence-based reasons.

## 1. CLI Wrapper (Slash Commands)

**Pattern:** Wrap codex/gemini-cli/opencode-cli as slash commands, call via Bash.

**Prior art:** `cc-codex-plugin`, `omc ask`, `ccs-delegation` (existing)

**Why rejected:**
- **No CC context inheritance** — external CLIs don't read CLAUDE.md, skills, hooks
- **CLI version fragility** — CLI updates break output parsers (user's primary concern)
- **Config interference** — if user also uses the CLI standalone, shared config/quota/auth state conflicts
- **Unstructured output** — parsing CLI output is fragile

## 2. Anthropic API Proxy (Global)

**Pattern:** Set `ANTHROPIC_BASE_URL` globally to a proxy that routes to other providers. CC thinks it's talking to Anthropic.

**Prior art:** [claude-code-router](https://github.com/musistudio/claude-code-router) (32k★), [claude-code-proxy](https://github.com/1rgs/claude-code-proxy) (3.4k★), [CCS](https://github.com/kaitranntt/ccs)

**Why rejected:**
- **Anthropic bans OAuth login through proxy** — high ban risk for subscription users
- **All traffic goes through proxy** — can't selectively route (main session + subagents all proxied)
- Per-subagent model routing is difficult (proxy sees all requests, can't distinguish subagent from main)
- claude-code-router has 880 open issues, many edge case bugs

## 3. Gateway + Thin MCP (LiteLLM)

**Pattern:** LiteLLM/OneAPI as backend, MCP server wraps as `ask_<model>(prompt)` tool.

**Prior art:** LiteLLM (43.5k★), OneAPI

**Why rejected:**
- **No agent loop** — 1-shot prompt/response only
- Cannot delegate multi-step tasks (no tool-use cycle)
- Not a "subagent" — just "ask for opinion"
- LiteLLM PyPI v1.82.7/1.82.8 had credential-stealing malware (Nov 2025)

## 4. Pure MCP Backend (Custom Mini-Agent Loop)

**Pattern:** Build MCP server with own agent loop (Bun + Vercel AI SDK), implement tool-use cycle internally.

**Why rejected (as primary approach):**
- **Hooks don't fire** (~0% coverage) — must reimplement CC's hook system
- **Permissions must be reimplemented** (~70%) — must parse settings.json
- **CLAUDE.md must be self-loaded** (~95%) — must parse and inject
- **Skills must be self-loaded** (~90%) — must parse and inject
- Significant reimplementation of CC features
- Drift risk when CC updates config formats
- ~3000+ lines vs ~700 lines with CCS

## 5. Facade Native Agent + MCP

**Pattern:** `.claude/agents/*.md` with `model: haiku` acts as thin proxy, calls MCP tool which calls real provider.

**Why rejected:**
- Extra haiku token cost per delegation (~1-3k tokens, ~$0.001-0.003)
- Inner layer (MCP) still doesn't inherit context
- Debug complexity: 2 layers with split logs
- Latency: 2 hops (haiku agent → MCP → provider)

## 6. MCP + claude-compat Library

**Pattern:** Same as #4 but extract reusable library for parsing CLAUDE.md, skills, hooks, permissions.

**Why rejected:**
- **Highest build effort** of all approaches
- Must reverse-engineer CC config parsing (formats undocumented internally)
- Fragile sync when CC updates formats
- Diminishing returns vs spawned CC session approach (which gets 100% compat for free)

## 7. External Runtime via Agent SDK

**Pattern:** Use `@anthropic-ai/claude-agent-sdk` `query()` programmatically with custom agents.

**Prior art:** Official Anthropic SDK

**Why rejected:**
- **SDK only accepts Claude models** — no custom LLM provider hook
- No `provider`, `baseURL`, `client`, or `llm` parameter in SDK
- Fails the primary goal of multi-provider support
- Confirmed by reading SDK source and official docs

## 8. Codex Plugin Fork

**Pattern:** Fork `openai/codex-plugin-cc`, generalize for multiple providers.

**Prior art:** [codex-plugin-cc](https://github.com/openai/codex-plugin-cc)

**Why rejected:**
- Bound to CLI per-provider (each needs dedicated CLI)
- Per-CLI parser fragility (same issue as #1)
- Generalization effort ≈ building #4 from scratch
- Background job pattern is codex-specific, not generalizable

## 9. Tmux Session per Subagent

**Pattern:** Spawn full CLI (claude/codex/gemini-cli) in tmux panes, IPC via files.

**Prior art:** `omc-teams`, Claude Code agent teams (tmux backend)

**Why rejected:**
- **Heavy startup** — full CLI process per pane
- **IPC via tmux scraping** — fragile, slow (30s polling in some implementations)
- **Poor programmatic control** — no structured output
- **Resource intensive** — RAM per pane, no cleanup

## Summary Table

| # | Approach | Context | Ban Risk | Effort | Fatal Flaw |
|---|----------|---------|----------|--------|------------|
| 1 | CLI Wrapper | 0% | Zero | XS | No CC context |
| 2 | Global Proxy | 100% | **HIGH** | M | **Ban risk** |
| 3 | Gateway+MCP | 0% | Zero | S | No agent loop |
| 4 | Pure MCP | ~70% | Zero | M-L | Must reimplement CC |
| 5 | Facade+MCP | ~50% | Zero | M | Cost + complexity |
| 6 | MCP+Lib | ~90% | Zero | L | Fragile sync |
| 7 | Agent SDK | N/A | Zero | S | **Claude only** |
| 8 | Plugin Fork | ~30% | Zero | M | CLI fragility |
| 9 | Tmux | 100% | Zero | L | Heavy, poor IPC |
| **10** | **CC+CCS** | **100%** | **Zero** | **S** | **(chosen)** |
