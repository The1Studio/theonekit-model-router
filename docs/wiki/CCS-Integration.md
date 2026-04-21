# CCS Integration

Deep-dive into [CCS (Claude Code Switch)](https://github.com/kaitranntt/ccs) internals relevant to model-router integration.

## CCS Overview

- **Version:** 7.72+ (daily releases)
- **Author:** Kai Tran (kaitranntt), sole maintainer
- **License:** MIT
- **Stars:** 2,014
- **Package:** `@kaitranntt/ccs` on npm

## Architecture

```
ccs <profile> -p "task" --agent role --max-turns 30
│
├─ Profile Detection
│  detectProfile(args) → { profile, remainingArgs }
│  First arg = profile name, rest = Claude flags (100% passthrough)
│
├─ Profile Type Resolution
│  ├─ CLIProxy (OAuth): gemini, codex, kimi, qwen, kiro, ghcp
│  ├─ Settings (API key): glm, km, ollama, custom
│  ├─ Account (Claude sub): work, personal
│  └─ Default: no profile → Claude's own auth
│
├─ CLIProxy Plus (Go binary, singleton)
│  ├─ Port: 8317 (default, configurable)
│  ├─ Routes: /api/provider/{gemini,codex,...}
│  ├─ Shared across ALL concurrent CCS sessions
│  ├─ OAuth tokens: ~/.ccs/cliproxy/auth/{provider}/
│  └─ Remote proxy: ccs.the1studio.org:443 (optional)
│
├─ Environment Setup
│  ANTHROPIC_BASE_URL = http://127.0.0.1:8317/api/provider/{provider}
│  ANTHROPIC_MODEL = {provider-specific model}
│  ANTHROPIC_AUTH_TOKEN = ccs-internal-managed
│
└─ spawn(claude, remainingArgs, { stdio: 'inherit', env })
```

## Flag Passthrough (Verified)

**Intercepted by CCS:** `--auth`, `--thinking`, `--effort`, `--1m`, `--proxy-*`, `--settings`

**Passed through to Claude:** Everything else, including:
- `--agent <name>` ✅
- `--permission-mode <mode>` ✅
- `--allowedTools <tools>` ✅
- `--disallowedTools <tools>` ✅
- `--max-turns <N>` ✅
- `--max-budget-usd <amount>` ✅
- `--output-format <format>` ✅
- `--mcp-config <config>` ✅
- `-p` (headless) ✅

## stdio Behavior

| Mode | stdio | CCS status output |
|------|-------|-------------------|
| Interactive | `stdio: 'inherit'` | stderr (spinners, proxy status) |
| Headless (`-p`) | `stdio: ['ignore', 'pipe', 'pipe']` | stderr |

**Key:** CCS prints **nothing to stdout**. All status messages go to stderr. Piping stdout gives clean Claude output.

## Concurrency

- **CLIProxy is singleton** — one proxy on :8317 serves all sessions
- **Multiple providers simultaneously** — each gets own URL path
- **Session tracking** — file-based lock with PID tracking
- **Safe for parallel delegations** — confirmed by design

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Config error |
| 3 | Network error (recoverable) |
| 4 | Auth error |
| 5 | Binary error |
| 6 | Provider error (recoverable) |
| 7 | Profile error |
| 8 | Proxy error |
| 130 | User abort (SIGINT) |

## Available Profiles

### OAuth (CLIProxy, zero API key needed)

| Profile | Provider | Model examples |
|---------|----------|----------------|
| `gemini` | Google | gemini-2.5-pro, gemini-2.5-flash |
| `codex` | OpenAI | gpt-5.3-codex, gpt-5-mini |
| `kimi` | Moonshot | kimi-k2.5 |
| `qwen` | Alibaba | qwen3.5-plus |
| `kiro` | AWS | Claude via CodeWhisperer |
| `ghcp` | GitHub | Copilot models |
| `agy` | Antigravity | Claude/Gemini |

### API Key Profiles

| Profile | Provider | Setup |
|---------|----------|-------|
| `glm` | Zhipu | `ccs api create --preset glm` |
| `km` | Kimi API | `ccs api create --preset kimi` |
| `ollama` | Local | `ccs api create --preset ollama` |
| `openrouter` | OpenRouter | `ccs api create --preset openrouter` |
| Custom | Any OpenAI-compat | `ccs api create` |

## Hooks (CCS-injected)

CCS injects two hooks for third-party profiles:

1. **WebSearch Transformer** — intercepts WebSearch tool calls, routes through Gemini CLI / OpenCode / Grok as fallback chain (since non-Claude models can't use Anthropic's native web search)

2. **Image Analyzer** — intercepts image file reads, provides vision analysis via external tool

Both only active for non-Claude profiles (skipped for default/account profiles).

## Integration Patterns

### Pattern 1: Spawn CCS CLI (recommended)

```typescript
const proc = spawn('ccs', [
  profile, '-p', task,
  '--agent', role,
  '--max-turns', String(maxTurns),
  '--permission-mode', permissionMode,
  '--max-budget-usd', String(budget),
  '--output-format', 'stream-json',
], { stdio: ['ignore', 'pipe', 'pipe'] });

// stdout = Claude stream-json (clean)
// stderr = CCS status (ignore or log)
```

### Pattern 2: Export env, spawn Claude directly (fallback)

```bash
eval $(ccs env gemini --format anthropic)
claude -p "task" --agent explorer-fast --max-turns 30 --output-format json
```

### Pattern 3: Existing ccs-delegation skill

Already available as `/ccs "task"` — auto-selects profile, enhances prompt, supports continuation.

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| CCS sole maintainer | Pin version; fallback to Pattern 2 (env export) |
| Breaking changes | Pin version; CI test on updates |
| CLIProxy binary | Pre-install; checksum verify |
| Remote proxy privacy | Use local-only mode; self-host |
| OAuth token storage | Plaintext but file perms 0o600; no cloud sync |
