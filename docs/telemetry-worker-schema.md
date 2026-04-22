# Telemetry Worker Schema

> Schema for T1K telemetry Worker at `t1k-telemetry.tuha.workers.dev/ingest`
> 
> **Action needed:** Update Worker to accept model-router event types alongside existing theonekit-core events.

## Endpoint

```
POST https://t1k-telemetry.tuha.workers.dev/ingest
Authorization: Bearer <gh-auth-token>
Content-Type: application/json
```

Auth: GitHub token via `gh auth token`. Worker validates The1Studio org membership.

---

## Existing Schema (theonekit-core — prompt-telemetry)

Already accepted by Worker:

```json
{
  "ts": "2026-04-22T08:00:00.000Z",
  "sessionId": "abc-123",
  "prompt": "user prompt text (max 2000 chars)",
  "promptTokens": 150,
  "project": "my-project",
  "kit": "theonekit-core",
  "installedModules": ["t1k-base", "t1k-extended"],
  "classifiedAs": "cook",
  "matchedSkills": ["t1k-cook"],
  "activatedSkills": ["t1k-cook"],
  "routedAgent": "fullstack-developer",
  "routingMode": "auto",
  "osPlatform": "darwin",
  "nodeVersion": "v22.17.1",
  "hookVersion": "1.62.1",
  "cliVersion": "1.45.0",
  "installedKits": ["theonekit-core", "theonekit-model-router"],
  "isSlashCommand": true,
  "sessionPromptIndex": 3,
  "model": "claude-opus-4-6",
  "gitBranch": "main",
  "contextTokens": 45000,
  "contextSize": 200000,
  "usageInputTokens": 5000,
  "usageOutputTokens": 500,
  "usageCacheCreationTokens": 4000,
  "usageCacheReadTokens": 3500,
  "rateLimit5hPercent": 15.2,
  "rateLimit7dPercent": 8.1,
  "linesAdded": 42,
  "linesRemoved": 10,
  "claudeEmail": "user@example.com",
  "claudeOrgId": "org-123",
  "subscriptionType": "max",
  "prevSessionId": "prev-abc",
  "prevOutcome": "success",
  "prevErrorType": null,
  "prevErrorCount": 0,
  "prevDurationSec": 120,
  "prevActivatedSkills": ["t1k-cook"],
  "prevToolsUsed": ["Read", "Edit", "Bash"],
  "prevSubagentsSpawned": 2
}
```

---

## New Schema (theonekit-model-router — 3 event types)

### Event Type 1: `model-router:request`

**Source:** oc-go-cc proxy WAL (Layer 1 — richest data, daemon, survives Ctrl+C)
**Trigger:** Every API request completion (success or failure)
**Volume:** ~3-10 events per delegation (1 per turn in agent loop)

```json
{
  "type": "model-router:request",
  "kit": "theonekit-model-router",
  "ts": "2026-04-22T08:50:17.000Z",

  "requestModel": "claude-opus-4-6",
  "routedModel": "kimi-k2.6",
  "scenario": "passthrough",
  "streaming": true,

  "messageCount": 3,
  "toolDefCount": 6,

  "inputTokens": 5622,
  "outputTokens": 584,
  "cachedTokens": 4900,

  "latencyMs": 4200,

  "success": true,
  "fallbackAttempts": 1,
  "fallbackModel": "",
  "errorType": "",
  "toolCallCount": 2,

  "hostname": "mac-studio.local",
  "platform": "darwin"
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | yes | Always `"model-router:request"` |
| `kit` | string | yes | Always `"theonekit-model-router"` |
| `ts` | string (ISO 8601) | yes | Event timestamp |
| `requestModel` | string | yes | Model CC requested (e.g. `"claude-opus-4-6"`) |
| `routedModel` | string | yes | Model proxy actually used (e.g. `"kimi-k2.6"`) |
| `scenario` | string | yes | Routing scenario: `"default"`, `"passthrough"`, `"think"`, `"long_context"`, `"background"`, `"complex"`, `"fast"` |
| `streaming` | boolean | yes | Whether request was streaming SSE |
| `messageCount` | int | yes | Number of messages in conversation |
| `toolDefCount` | int | yes | Number of tool definitions sent |
| `inputTokens` | int | yes | Prompt input tokens |
| `outputTokens` | int | yes | Completion output tokens |
| `cachedTokens` | int | yes | Tokens served from provider cache (0 = miss) |
| `latencyMs` | int | yes | Total request latency in milliseconds |
| `success` | boolean | yes | Whether request succeeded |
| `fallbackAttempts` | int | yes | Number of models tried (1 = no fallback) |
| `fallbackModel` | string | no | Model used as fallback (empty if no fallback) |
| `errorType` | string | no | Error category if failed: `"rate_limit"`, `"timeout"`, `"auth"`, `"transform"`, `"upstream"`, `"unknown"` |
| `toolCallCount` | int | yes | Number of tool calls in response (0 for streaming) |
| `hostname` | string | yes | Machine hostname |
| `platform` | string | yes | OS platform: `"darwin"`, `"linux"`, `"win32"` |

**Key analytics:**
- Cache hit rate: `AVG(cachedTokens / inputTokens)` per model
- Model reliability: `SUM(success) / COUNT(*)` per routedModel
- Fallback frequency: `COUNT(*) WHERE fallbackAttempts > 1`
- Latency p95/p99 per model
- Token usage per model per day

---

### Event Type 2: `model-router:delegation`

**Source:** mr-delegate.sh (Layer 2 — delegation completion)
**Trigger:** When a delegation finishes (all turns complete)
**Volume:** 1 event per delegation

```json
{
  "type": "model-router:delegation",
  "kit": "theonekit-model-router",
  "id": "1776751267-9769",
  "role": "mr-explorer-fast",
  "profile": "opencode-go",
  "model": "glm-5.1",
  "exit": 0,
  "duration": 42,
  "ts": "2026-04-22T08:51:00.000Z",
  "hostname": "mac-studio.local",
  "platform": "Darwin"
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | yes | Always `"model-router:delegation"` |
| `kit` | string | yes | Always `"theonekit-model-router"` |
| `id` | string | yes | Unique delegation ID (`timestamp-pid`) |
| `role` | string | yes | Agent role: `"mr-explorer-fast"`, `"mr-coder-cheap"`, etc. |
| `profile` | string | yes | CCS profile used: `"opencode-go"`, `"gemini"`, etc. |
| `model` | string | yes | Model used (may differ from default if AI-selected) |
| `exit` | int | yes | Process exit code (0 = success) |
| `duration` | int | yes | Total delegation duration in seconds |
| `ts` | string (ISO 8601) | yes | Completion timestamp |
| `hostname` | string | yes | Machine hostname |
| `platform` | string | yes | OS name |

**Key analytics:**
- Role usage distribution: `COUNT(*) GROUP BY role`
- Model per role: `COUNT(*) GROUP BY role, model`
- Success rate per role: `AVG(exit = 0) GROUP BY role`
- Average delegation duration per role

---

### Event Type 3: `model-router:tool-use`

**Source:** mr-telemetry.cjs hook (Layer 3 — per-tool events in delegated sessions)
**Trigger:** Every tool call inside a delegated CC session
**Volume:** ~3-20 events per delegation

```json
{
  "type": "model-router:tool-use",
  "kit": "theonekit-model-router",
  "role": "mr-explorer-fast",
  "parentPid": "12345",
  "tool": "Read",
  "durationMs": 150,
  "ts": "2026-04-22T08:50:30.000Z",
  "hostname": "mac-studio.local",
  "platform": "darwin",
  "arch": "arm64"
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | yes | Always `"model-router:tool-use"` |
| `kit` | string | yes | Always `"theonekit-model-router"` |
| `role` | string | yes | Agent role executing the tool |
| `parentPid` | string | no | PID of parent delegate.sh process |
| `tool` | string | yes | Tool name: `"Read"`, `"Glob"`, `"Grep"`, `"Edit"`, `"Bash"`, etc. |
| `durationMs` | int | no | Tool execution duration (null if not available) |
| `ts` | string (ISO 8601) | yes | Event timestamp |
| `hostname` | string | yes | Machine hostname |
| `platform` | string | yes | OS platform |
| `arch` | string | no | CPU architecture |

**Key analytics:**
- Tool usage distribution per role: `COUNT(*) GROUP BY role, tool`
- Average tool execution time: `AVG(durationMs) GROUP BY tool`

---

## Batch Format (oc-go-cc WAL flush)

Layer 1 events are batched and sent as JSON array (max 100 per POST):

```json
[
  { "type": "model-router:request", ... },
  { "type": "model-router:request", ... },
  { "type": "model-router:request", ... }
]
```

Worker should accept both single object and array at `/ingest`.

---

## D1 Schema Suggestions

```sql
-- Table for model-router events (alongside existing prompt_events)
CREATE TABLE model_router_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,               -- 'request', 'delegation', 'tool-use'
  kit TEXT DEFAULT 'theonekit-model-router',
  ts TEXT NOT NULL,                 -- ISO 8601
  
  -- request fields
  request_model TEXT,
  routed_model TEXT,
  scenario TEXT,
  streaming INTEGER,                -- 0/1
  message_count INTEGER,
  tool_def_count INTEGER,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cached_tokens INTEGER,
  latency_ms INTEGER,
  success INTEGER,                  -- 0/1
  fallback_attempts INTEGER,
  fallback_model TEXT,
  error_type TEXT,
  tool_call_count INTEGER,
  
  -- delegation fields
  delegation_id TEXT,
  role TEXT,
  profile TEXT,
  model TEXT,
  exit_code INTEGER,
  duration_sec INTEGER,
  
  -- tool-use fields
  tool_name TEXT,
  tool_duration_ms INTEGER,
  
  -- common
  hostname TEXT,
  platform TEXT,
  
  created_at TEXT DEFAULT (datetime('now'))
);

-- Indexes for common queries
CREATE INDEX idx_mr_type ON model_router_events(type);
CREATE INDEX idx_mr_ts ON model_router_events(ts);
CREATE INDEX idx_mr_model ON model_router_events(routed_model);
CREATE INDEX idx_mr_role ON model_router_events(role);
CREATE INDEX idx_mr_success ON model_router_events(success);
```

---

## Example Analytics Queries

```sql
-- Cache hit rate per model (last 7 days)
SELECT routed_model,
       COUNT(*) as requests,
       AVG(CAST(cached_tokens AS REAL) / NULLIF(input_tokens, 0)) as cache_rate,
       AVG(latency_ms) as avg_latency
FROM model_router_events
WHERE type = 'request' AND ts > datetime('now', '-7 days')
GROUP BY routed_model;

-- Model reliability
SELECT routed_model,
       COUNT(*) as total,
       SUM(success) as ok,
       ROUND(100.0 * SUM(success) / COUNT(*), 1) as success_pct
FROM model_router_events
WHERE type = 'request'
GROUP BY routed_model;

-- Role usage + cost
SELECT role, model, COUNT(*) as delegations,
       AVG(duration_sec) as avg_duration,
       SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) as successes
FROM model_router_events
WHERE type = 'delegation'
GROUP BY role, model;

-- Fallback frequency
SELECT routed_model, fallback_model, COUNT(*)
FROM model_router_events
WHERE type = 'request' AND fallback_attempts > 1
GROUP BY routed_model, fallback_model;

-- Tool usage per role
SELECT role, tool_name, COUNT(*) as calls,
       AVG(tool_duration_ms) as avg_ms
FROM model_router_events
WHERE type = 'tool-use'
GROUP BY role, tool_name;
```
