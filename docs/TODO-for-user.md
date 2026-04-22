# TODO for User (manual steps needed)

## P0 — Blocked on access

### 1. Apply theonekit-cli patch
Register model-router kit so `t1k modules install model-router` works.

```bash
cd /path/to/theonekit-cli
git checkout -b feat/register-model-router
git apply /tmp/theonekit-cli-model-router.patch
git commit -m "feat: register theonekit-model-router kit"
git push -u origin feat/register-model-router
gh pr create --title "feat: register theonekit-model-router kit" \
  --body "Enables: t1k modules install model-router"
```

Patch adds `"model-router"` to `KitType` enum + `AVAILABLE_KITS` in `src/types/kit.ts`.

### 2. Grant repo access (optional)
For future PRs to theonekit-cli:
```bash
gh api repos/The1Studio/theonekit-cli/collaborators/h3nr1-d14z -X PUT -f permission=push
```

## P1 — T1K telemetry Worker

### 3. Update Worker schema for model-router events
The T1K telemetry Worker at `t1k-telemetry.tuha.workers.dev` needs to accept new event types:

**New event types from model-router:**
```json
// From oc-go-cc proxy (Layer 1 — richest data)
{
  "type": "model-router:request",
  "kit": "theonekit-model-router",
  "requestModel": "glm-5.1",
  "routedModel": "glm-5.1",
  "scenario": "passthrough",
  "streaming": true,
  "messageCount": 3,
  "toolDefCount": 6,
  "inputTokens": 5622,
  "outputTokens": 584,
  "cachedTokens": 4900,
  "latencyMs": 4200,
  "success": true,
  "fallbackAttempts": 0,
  "fallbackModel": null,
  "errorType": null,
  "toolCallCount": 2,
  "hostname": "...",
  "platform": "darwin"
}

// From mr-delegate.sh (Layer 2 — delegation events)
{
  "type": "model-router:delegation",
  "kit": "theonekit-model-router",
  "id": "1776751267-9769",
  "role": "mr-explorer-fast",
  "profile": "opencode-go",
  "model": "glm-5.1",
  "exit": 0,
  "duration": 42,
  "ts": "2026-04-22T...",
  "hostname": "...",
  "platform": "Darwin"
}

// From mr-telemetry.cjs hook (Layer 3 — per-tool events)
{
  "type": "model-router:tool-use",
  "kit": "theonekit-model-router",
  "role": "mr-explorer-fast",
  "tool": "Read",
  "durationMs": 150,
  "ts": "2026-04-22T..."
}
```

**Action:** Add these types to Worker's accepted schema. Key fields to index:
- `type` (filter by event type)
- `kit` (filter by kit)
- `requestModel` / `routedModel` (model usage analytics)
- `cachedTokens` (cache hit rate)
- `success` + `errorType` (reliability dashboard)
- `latencyMs` (performance tracking)

### 4. Add `t1k router` CLI subcommand
Needs implementation in theonekit-cli. Commands:
- `t1k router list` — show roles + models + enabled/disabled
- `t1k router test <profile>` — canary test
- `t1k router enable-transparent` / `disable-transparent`
- `t1k router usage` — show stats from calls.jsonl
- `t1k router enable <model>` / `disable <model>` — toggle in providers-config.json

## P2 — Polish

### 5. Update wiki pages
Pages that need updating after this session:
- **Architecture.md** — add telemetry layers diagram, AI-driven model selection
- **Model-Selection.md** — update with model-capabilities.md reference, AI-driven approach
- **CCS-Integration.md** — add oc-go-cc telemetry section
- **Implementation-Plan.md** — mark completed items, add new phases

### 6. Kimi K2.6 streaming fix
Deeper investigation needed: `reasoning_content` fix works for non-streaming but streaming path still fails on turn 2+. The oc-go-cc streaming handler may need to inject reasoning_content during SSE replay.

### 7. Add more providers
When CCS remote proxy is back online or new API keys obtained:
- Add Gemini (free tier via CCS OAuth)
- Add Codex (ChatGPT Plus via CCS OAuth)
- Update model-capabilities.md with new models
- Update providers-config.json
