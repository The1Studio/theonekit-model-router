# Safety Model (8 Layers)

Spawned CC sessions run non-Claude models with full tool access. Multiple safety layers prevent unauthorized actions and infinite loops.

## Layer 1: Tool Whitelist (CC Agent Definition)

```markdown
# .claude/agents/explorer-fast.md
---
tools: [Read, Grep, Glob]
---
```

CC removes unlisted tools from the agent's tool definitions. The model **never sees** Edit, Write, or Bash — cannot call them even if it tries.

**Enforced by:** Claude Code engine (native)

## Layer 2: Permission Mode (CLI Flag)

```bash
--permission-mode plan     # read-only, no edits/writes/bash
--permission-mode dontAsk  # auto-deny all permission prompts  
--permission-mode acceptEdits  # auto-accept edits in cwd only
```

In headless mode (`-p`), permission prompts have no user to ask — `default` mode auto-denies anything not explicitly allowed.

**Enforced by:** Claude Code permission system (native)

## Layer 3: Allowed/Disallowed Tools (CLI Flag)

```bash
--allowedTools "Read,Grep,Glob"
--disallowedTools "Agent,Write"
```

CLI-level override that stacks with agent definition. Double protection.

**Enforced by:** Claude Code CLI (native)

## Layer 4: Hooks (Agent Frontmatter)

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-safe-command.sh"
```

Custom validation scripts run before each tool call. Exit code 2 = block.

Example: block SQL writes, block edits outside project root, block rm -rf.

**Enforced by:** Claude Code hook system (native)

## Layer 5: Max Turns (CLI Flag)

```bash
--max-turns 30
```

Hard stop after N agentic turns. CC stops the loop cleanly and returns partial result.

**Enforced by:** Claude Code (native, print mode only)

## Layer 6: Budget Cap (CLI Flag)

```bash
--max-budget-usd 0.50
```

Maximum dollar amount per delegation. CC tracks API costs and stops when budget exceeded.

**Enforced by:** Claude Code (native, print mode only)

## Layer 7: Process Timeout (model-router)

```typescript
const timer = setTimeout(() => {
  proc.kill('SIGTERM');
  setTimeout(() => proc.kill('SIGKILL'), 5000);
}, config.timeout * 1000);  // default 300s
```

model-router kills the spawned process after configured timeout, regardless of what the model is doing.

**Enforced by:** model-router delegation layer

## Layer 8: Loop Detection (model-router)

```typescript
// Monitor stream events for repeated identical tool calls
if (lastThreeCalls.every(c => c.name === call.name && c.args === call.args)) {
  proc.kill('SIGTERM');
  return { error: 'Loop detected: 3 identical tool calls' };
}
```

If the model makes 3+ identical consecutive tool calls (reading same file, running same command), model-router detects the loop and kills the process.

**Enforced by:** model-router delegation layer

## Summary

```
Layer 1: Agent tools whitelist     → Model can't see restricted tools
Layer 2: --permission-mode         → CC enforces read-only/edit/deny
Layer 3: --allowedTools            → CLI-level double protection
Layer 4: Agent hooks PreToolUse    → Custom validation scripts
Layer 5: --max-turns 30            → Hard stop after N turns
Layer 6: --max-budget-usd 0.50    → Cost cap per delegation
Layer 7: Process timeout (300s)    → Kill hung processes
Layer 8: Loop detection (3x same)  → Kill infinite loops
```

Layers 1-6 use **official Claude Code features** (native enforcement).
Layers 7-8 are **model-router additions** (defense in depth).

## Example: Read-Only Explorer

```bash
ccs gemini -p "find auth files" \
  --agent explorer-fast \      # L1: tools=[Read,Grep,Glob]
  --max-turns 30 \             # L5: stop after 30 turns
  --permission-mode plan \     # L2: read-only mode
  --max-budget-usd 0.50        # L6: $0.50 cap
# L7: model-router timeout 300s
# L8: model-router loop detection
```

This agent physically cannot: edit files, write files, run bash commands, spawn subagents, exceed 30 turns, spend more than $0.50, or run longer than 5 minutes.
