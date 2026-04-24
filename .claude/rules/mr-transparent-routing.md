---
origin: theonekit-model-router
repository: The1Studio/theonekit-model-router
module: null
protected: false
---
# Model Router — Transparent Routing

When transparent routing is enabled, delegate eligible tasks to cheaper AI models instead of using the primary Claude model.

## Activation Check

Before applying this rule, read `.claude/t1k-config-mr.json`. Only apply if:
- File exists AND `modelRouter.enabled` is `true` AND `modelRouter.mode` is `"transparent"`

If any condition is false, **ignore this rule entirely** and proceed with normal T1K routing.

## When to Delegate

When a T1K skill (cook, fix, review, test, docs) resolves a role to a `model-router-mr-*` agent, delegate via Bash instead of spawning that agent:

```bash
bash .claude/scripts/mr-delegate.sh <mr-role> "<task description>" --provider <provider> --model <model>
```

### Provider & Model Selection

Before delegating, you MUST choose a provider and model:

1. Check `modelRouter.roleOverrides` in `.claude/t1k-config-mr.json` first — if an override exists for this role, use it
2. Otherwise, read `.claude/model-capabilities.md` for model strengths, costs, and suggestions
3. Read `.claude/providers-config.json` for available providers and their endpoints
4. Choose the best provider + model for the task (consider complexity, context size, cost)

Pass your choice: `--provider <provider> --model <model>`

### Role Mapping

| Resolved Agent | mr-delegate.sh role | Use for |
|---------------|--------------------|---------| 
| model-router-mr-coder-cheap | mr-coder-cheap | Implementing features, writing code |
| model-router-mr-reviewer-deep | mr-reviewer-deep | Code review, security review |
| model-router-mr-tester | mr-tester | Running tests, test analysis |
| model-router-mr-doc-writer | mr-doc-writer | Writing documentation |
| model-router-mr-explorer-fast | mr-explorer-fast | File discovery, codebase exploration |
| model-router-mr-doc-scout | mr-doc-scout | Reading and finding documentation |

## When NOT to Delegate

Do NOT delegate in these cases — use the primary Claude model instead:

1. **Parallel/multi-agent mode**: skill invoked with `--parallel` flag or multi-agent pipeline
2. **Orchestration roles**: planner, git-manager, brainstormer, project-manager (no MR equivalent)
3. **Complex multi-step workflows**: cook full pipeline where orchestration needs Claude reasoning
4. **Agent already resolved to non-MR agent**: if resolved agent name doesn't start with `model-router-mr-`
5. **MR_SPAWNED=1**: already inside a delegated session (prevents recursion)
6. **Bash not available**: `command -v bash` fails (Windows without WSL)
7. **User explicitly requested Claude**: user said "use Claude" or "don't delegate"

## Delegation Output

The Bash call returns the cheap model's text output directly. Use it as if the agent had responded. If mr-delegate.sh exits with non-zero code, report the error to the user and suggest:
- Retry with `/t1k:delegate` explicitly
- Disable transparent routing: `t1k router disable-transparent`

## roleOverrides

Users can pin specific roles to a provider+model via `modelRouter.roleOverrides` in `t1k-config-mr.json`:

```json
{
  "modelRouter": {
    "roleOverrides": {
      "mr-reviewer-deep": { "provider": "kimi", "model": "kimi-k2.6" },
      "mr-explorer-fast": { "provider": "opencode-go", "model": "qwen3.5-plus" }
    }
  }
}
```

When roleOverrides exist for a role, use the specified `--provider` and `--model` flags instead of AI selection.
