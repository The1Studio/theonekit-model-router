---
name: t1k:delegate
description: "Delegate tasks to cheaper/specialized AI models via OpenCode Go. Use when a task is self-contained and doesn't need Opus-level reasoning — exploration, docs, boilerplate code, reviews, tests."
keywords: [delegate, cheap model, opencode, route, subagent, explore cheap, review cheap, code cheap, test cheap, delegate to cheap, use cheap model, use opencode go]
argument-hint: "<role> \"<task>\" [--model <model>] [--profile <profile>]"
effort: low
version: 0.2.0
origin: theonekit-model-router
repository: The1Studio/theonekit-model-router
module: mr-router
protected: false
---

## Available Roles

| Role | Model | Best for | Permissions | Budget |
|------|-------|----------|-------------|--------|
| `mr-explorer-fast` | qwen3.5-plus | File discovery, pattern search | Read-only | $0.30 |
| `mr-doc-scout` | kimi-k2.5 | Doc audit, gap analysis | Read-only | $0.30 |
| `mr-doc-writer` | kimi-k2.6 | Write/update documentation | Edit docs only | $2.00 |
| `mr-coder-cheap` | kimi-k2.6 | Code implementation per plan | Full access | $2.00 |
| `mr-reviewer-deep` | glm-5.1 | Security review, architecture analysis | Read-only + Bash | $1.00 |
| `mr-tester` | qwen3.5-plus | Run tests, interpret results | Read-only + Bash | $0.50 |

## How to Delegate

```bash
bash scripts/mr-delegate.sh <role> "<task description>"
```

### Examples

```bash
# Explore codebase
bash scripts/mr-delegate.sh mr-explorer-fast "Find all authentication-related files and list key functions"

# Audit documentation
bash scripts/mr-delegate.sh mr-doc-scout "Scan all docs for outdated sections and missing cross-references"

# Write docs
bash scripts/mr-delegate.sh mr-doc-writer "Update README.md with the new installation instructions"

# Implement code
bash scripts/mr-delegate.sh mr-coder-cheap "Add input validation to UserController.create following existing patterns"

# Review code
bash scripts/mr-delegate.sh mr-reviewer-deep "Review src/auth/ for security vulnerabilities and OWASP Top 10"

# Run tests
bash scripts/mr-delegate.sh mr-tester "Run the test suite and report failures with likely causes"
```

### Override model or profile

```bash
# Use a different model
bash scripts/mr-delegate.sh mr-coder-cheap "implement feature" --model glm-5.1

# Use a different CCS profile (e.g. gemini, codex when available)
bash scripts/mr-delegate.sh mr-explorer-fast "find auth files" --profile gemini
```

## When to Delegate vs Keep

**Delegate** (use mr-delegate):
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
- Max turns (hard stop)
- Budget cap (max USD per call)
- Timeout (5 minutes default)
- No nested delegation (MR_SPAWNED guard)
- Write lock (only 1 write-capable agent at a time)

## Logs

```
~/.model-router/calls.jsonl
```
