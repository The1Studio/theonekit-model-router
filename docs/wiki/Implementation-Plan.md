# Implementation Plan

## Progressive Approach: A → B

### Option A: Skill + Script (MVP, ship today)

**Deliverables:**

1. **Agent definitions** (`.claude/agents/*.md`)
   - `explorer-fast.md` — read-only, tools: [Read, Grep, Glob], permissionMode: plan
   - `coder-cheap.md` — full access, tools: all, permissionMode: acceptEdits
   - `reviewer-deep.md` — read-only + Bash, permissionMode: plan
   - `researcher.md` — read-only, long context tasks

2. **Wrapper script** (`scripts/delegate.sh`, ~50 lines)
   - Role → CCS profile mapping
   - Safety flags enforcement (max-turns, permission-mode, max-budget-usd)
   - JSONL logging to `~/.model-router/calls.jsonl`
   - Error handling with CCS exit codes

3. **Skill** (`.claude/skills/model-router/SKILL.md`)
   - Role descriptions and when to delegate
   - Instructions to call `scripts/delegate.sh`
   - Guidelines: when to delegate vs keep in main session

4. **CCS profiles** (if not already configured)
   - `ccs api create --preset glm` (or other needed profiles)
   - Verify: gemini, codex, kimi already available via CLIProxy

**Acceptance criteria:**
- [ ] Claude Code main session can delegate "explore codebase" to Gemini via skill
- [ ] Spawned session loads CLAUDE.md (verify via output)
- [ ] `--max-turns` limits execution correctly
- [ ] `--permission-mode plan` prevents file edits
- [ ] JSONL log written with call metadata
- [ ] Main session receives and presents result

**Effort:** ~2-4 hours

---

### Option B: MCP Server (upgrade when needed)

**Components (~700 lines total):**

| Component | Lines | Description |
|-----------|-------|-------------|
| MCP Server (`src/index.ts`) | ~80 | Bun + @modelcontextprotocol/sdk, expose tools |
| Agent Registry (`src/registry.ts`) | ~120 | Load config/agents.yaml + agents/*.md |
| CCS Spawner (`src/spawner.ts`) | ~200 | Spawn ccs, capture stdio, timeout |
| Stream Parser (`src/parser.ts`) | ~100 | Parse NDJSON stream-json events |
| Safety Layer (`src/safety.ts`) | ~80 | Loop detection on top of CC's built-in safety |
| Metrics (`src/metrics.ts`) | ~120 | SQLite logging + HTTP /metrics endpoint |

**Additional deliverables:**
- `config/agents.yaml` — role definitions with CCS profile mapping
- `config/agents/*.md` — extended system prompts (Markdown)
- `.env.example` — environment template
- MCP registration in `.claude/settings.local.json`

**Acceptance criteria:**
- [ ] `delegate("explorer-fast", "find auth files")` MCP tool works
- [ ] `list_roles()` returns available roles with profiles
- [ ] `get_usage()` returns metrics summary
- [ ] Concurrent delegations limited per-provider
- [ ] SQLite metrics logging per-call
- [ ] HTTP /metrics endpoint returns Prometheus format
- [ ] Timeout kills hung processes

**Effort:** ~1-2 weeks

---

## When to Upgrade A → B

Upgrade to MCP server when you need:

| Trigger | Why MCP helps |
|---------|---------------|
| >5 agent roles | Bash case statement unwieldy, YAML config cleaner |
| Parallel delegation | MCP background tasks, concurrency control |
| Structured metrics | SQLite + Prometheus, reliable logging |
| 100% determinism | Code enforces flags vs Claude interpreting skill |
| External integration | Other tools/scripts call delegate() programmatically |
| Team usage | Multiple users need consistent interface |

## Future Phases (after B)

### Phase 3: Advanced Features
- Session keep-alive pool (reuse spawned CC processes)
- Architect/Editor dual-model split (Aider pattern)
- Hot-reload config (fs.watch)
- Per-agent MCP server passthrough

### Phase 4: OSS Polish
- Conformance test suite (provider × CC-feature matrix)
- npm package (`model-router`)
- CI/CD (GitHub Actions)
- Comprehensive documentation
