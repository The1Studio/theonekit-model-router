---

origin: theonekit-model-router
repository: The1Studio/theonekit-model-router
module: null
protected: false
---
# Model Capabilities Guide

> This file is read by the primary Claude agent to decide which model and provider to use for each delegation. When delegating via `/t1k:delegate`, choose the model that best fits the task requirements.

## Available Models (OpenCode Go)

| Model | Quality | Context | Speed | Cost | Best for |
|-------|---------|---------|-------|------|----------|
| `glm-5.1` | Excellent | 200K | Medium | High (~880 req/5hr) | Complex architecture, security review, difficult reasoning |
| `glm-5` | Good | 200K | Medium | Medium (~1150 req/5hr) | High-quality coding, refactoring |
| `kimi-k2.6` | Excellent | 256K | Medium | Medium (~1850 req/5hr) | Best balance — general coding, writing, analysis |
| `kimi-k2.5` | Good | 256K | Medium | Medium (~1850 req/5hr) | Solid fallback, good writing quality |
| `mimo-v2-pro` | Good | 128K | Fast | Medium (~1290 req/5hr) | Code completion, generation, fast tasks |
| `mimo-v2-omni` | Fair | 256K | Fast | Low (~2150 req/5hr) | Fast prototyping, simple tasks |
| `qwen3.6-plus` | Fair | 128K | Fast | Low (~3300 req/5hr) | Cost-effective general coding |
| `qwen3.5-plus` | Basic | 128K | Very Fast | Very Low (~10200 req/5hr) | Cheapest — file listing, grep, simple lookup |
| `minimax-m2.7` | Fair | **1M** | Medium | Low (~3400 req/5hr) | Long context specialist — large file analysis |
| `minimax-m2.5` | Basic | **1M** | Fast | Very Low (~6300 req/5hr) | Long context on a budget |

## Model Selection Guidelines

### By task complexity

| Task complexity | Recommended models | Why |
|----------------|-------------------|-----|
| **Simple** (list files, grep, lookup) | `qwen3.5-plus`, `mimo-v2-omni` | Cheapest, fast enough |
| **Medium** (code review, write docs, implement feature) | `kimi-k2.6`, `glm-5` | Good quality/cost balance |
| **Complex** (architecture analysis, security audit, deep reasoning) | `glm-5.1` | Best reasoning, worth the cost |
| **Long context** (analyze large codebase, read many files) | `minimax-m2.7` | 1M context window |

### By agent role (defaults, can override)

| Role | Default model | Override when |
|------|--------------|---------------|
| `mr-explorer-fast` | `qwen3.5-plus` | Complex codebase → `kimi-k2.6` |
| `mr-doc-scout` | `kimi-k2.5` | Large docs set → `minimax-m2.7` |
| `mr-doc-writer` | `kimi-k2.6` | Technical docs → `glm-5.1` |
| `mr-coder-cheap` | `kimi-k2.6` | Simple boilerplate → `qwen3.5-plus` |
| `mr-reviewer-deep` | `glm-5.1` | Quick scan → `kimi-k2.6` |
| `mr-tester` | `qwen3.5-plus` | Complex test analysis → `kimi-k2.6` |

### Known limitations

| Model | Limitation |
|-------|-----------|
| `kimi-k2.5/k2.6` | Tool_calls with Write may fail (reasoning_content issue). Fallback auto-kicks in. |
| `qwen3.5-plus` | May hit Alibaba quota. Fallback to mimo-v2-pro. |
| `minimax-m2.5/m2.7` | Uses Anthropic-compatible endpoint (native, no translation needed). |

## Providers

| Provider | Status | Auth | Models | Endpoint |
|----------|--------|------|--------|----------|
| **OpenCode Go** | Enabled | OC_GO_CC_API_KEY via oc-go-cc proxy | GLM, Kimi, Qwen, MiMo, MiniMax | `localhost:3456` |
| **Kimi (direct)** | Enabled | `gh auth token` (The1Studio org) | kimi-k2, kimi-k2.5, kimi-k2.6 | `ccs.the1studio.org` |

### Provider selection guidelines

| Scenario | Provider | Why |
|----------|----------|-----|
| Default (most tasks) | OpenCode Go | More models, local proxy, lower latency |
| Kimi-specific tasks | Kimi direct | Native Kimi API, no translation layer, better tool_calls support |
| OpenCode Go quota exhausted | Kimi direct | Fallback — independent quota |

> To use Kimi direct: `--profile kimi --model kimi-k2.6`
> Requires: `gh auth login` with The1Studio org membership.

## Cache behavior

All models auto-cache prompts ≥1024 tokens. Turn 2+ typically 98% cache hit. No action needed.
