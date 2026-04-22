# Telemetry Design

## Overview

model-router sends telemetry to the T1K cloud for monitoring, analytics, and quality tracking. Three layers ensure low data loss even on unexpected exits.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 1: oc-go-cc proxy (daemon, survives Ctrl+C)            │
│                                                                │
│  On every request completion:                                 │
│  1. Write event → ~/.model-router/telemetry.jsonl (sync WAL) │
│  2. Background goroutine flushes to cloud every 60s           │
│  3. On startup: flush pending from previous crash             │
│  4. On shutdown: final flush                                  │
│                                                                │
│  Data: tokens, cache hits, latency, model, routing,           │
│        fallbacks, errors, tool call count                     │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Layer 2: mr-delegate.sh (script, per-delegation)             │
│                                                                │
│  On delegation completion:                                    │
│  1. Async curl POST to cloud (background, 3s timeout)         │
│                                                                │
│  Data: role, model, profile, duration, exit code              │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Layer 3: mr-telemetry.cjs (CC PostToolUse hook)              │
│                                                                │
│  On every tool call in delegated session:                     │
│  1. POST to cloud (3s timeout, fail-open)                     │
│                                                                │
│  Data: role, tool name, duration                              │
└──────────────────────────────────────────────────────────────┘
```

## Endpoint

```
URL:  https://t1k-telemetry.tuha.workers.dev/ingest
Auth: Authorization: Bearer <gh-auth-token>
Org:  The1Studio member required
```

## Event Types

### `model-router:request` (Layer 1 — proxy)

Richest event. Sent on every API request completion (success or failure).

```json
{
  "type": "model-router:request",
  "kit": "theonekit-model-router",
  "ts": "2026-04-22T08:50:17Z",
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
  "hostname": "mac-studio",
  "platform": "darwin"
}
```

### `model-router:delegation` (Layer 2 — script)

Sent when a delegation completes (all turns finished).

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
  "ts": "2026-04-22T08:51:00Z",
  "hostname": "mac-studio",
  "platform": "Darwin"
}
```

### `model-router:tool-use` (Layer 3 — hook)

Sent on each tool call within a delegated session.

```json
{
  "type": "model-router:tool-use",
  "kit": "theonekit-model-router",
  "role": "mr-explorer-fast",
  "parentPid": "12345",
  "tool": "Read",
  "durationMs": 150,
  "ts": "2026-04-22T08:50:30Z",
  "hostname": "mac-studio",
  "platform": "darwin"
}
```

## Data Loss Matrix

| Scenario | Layer 1 (proxy) | Layer 2 (script) | Layer 3 (hook) |
|----------|----------------|-------------------|----------------|
| Normal exit | Flush on shutdown | Sent | Sent |
| User Ctrl+C | WAL on disk, flush next startup | Lost (curl killed) | Lost (hook killed) |
| Proxy crash | WAL on disk, flush next startup | N/A | N/A |
| Network down | Queue locally, retry next flush | Lost | Lost |
| Machine restart | WAL persists, flush next proxy start | Lost | Lost |

**Layer 1 is the safety net** — proxy daemon survives user exits and WAL persists across crashes.

## Privacy

- **No prompt content** sent — only metadata (token counts, model names, latency)
- **No file content** — only tool names and durations
- **Hostname** sent for device identification (can be anonymized)
- **GitHub org membership** verified server-side

## Configuration

```json
// In ~/.config/oc-go-cc/config.json
{
  "telemetry": {
    "enabled": true,
    "endpoint": "https://t1k-telemetry.tuha.workers.dev/ingest",
    "flush_interval_sec": 60
  }
}
```

Disable: set `"enabled": false` or env `T1K_TELEMETRY_ENABLED=0`.

## Analytics Queries (for Worker/D1)

```sql
-- Cache hit rate per model
SELECT routedModel, 
       AVG(cachedTokens * 1.0 / inputTokens) as cache_rate
FROM events WHERE type = 'model-router:request'
GROUP BY routedModel;

-- Model reliability
SELECT routedModel,
       COUNT(*) as total,
       SUM(CASE WHEN success THEN 1 ELSE 0 END) as success_count,
       AVG(latencyMs) as avg_latency
FROM events WHERE type = 'model-router:request'
GROUP BY routedModel;

-- Delegation cost by role  
SELECT role, COUNT(*) as delegations, AVG(duration) as avg_duration
FROM events WHERE type = 'model-router:delegation'
GROUP BY role;

-- Fallback frequency
SELECT routedModel, fallbackModel, COUNT(*) 
FROM events WHERE type = 'model-router:request' AND fallbackAttempts > 0
GROUP BY routedModel, fallbackModel;
```
