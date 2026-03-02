# n8n Implementation Guide For MyStudySpace AI

Last updated: February 28, 2026

## 1) Goal

Use `n8n` as an automation sidecar for long-running AI jobs, while keeping your existing backend as the real-time chat orchestrator.

- Keep synchronous chat answers in backend (`/api/rag/query`).
- Move heavy or asynchronous jobs to n8n:
  - PDF ingest pipeline (extract -> chunk -> embed -> index)
  - Quiz artifact generation
  - Summary/report PDF generation
  - Notifications and retries

This matches your app split:
- AI Studio: artifact workflows from a resource
- AI Chat: conversational assistant with context + retrieval

## 2) What n8n should and should not do

### Use n8n for
- Workflows that may take seconds/minutes
- Retryable background tasks
- Fan-out tasks across OCR, embedding, PDF generation, notifications
- Scheduled housekeeping (re-embed stale resources, dead-letter reprocess)

### Do not use n8n for
- Per-token streaming chat responses
- Low-latency first-token responses
- Core retrieval ranking logic for live chat

## 3) Target architecture

1. Flutter app -> existing backend
2. Backend handles live chat and retrieval
3. Backend enqueues heavy tasks to n8n webhook/queue
4. n8n executes pipeline and writes job result to DB/storage
5. Backend exposes job status API to app
6. App shows loading/progress and fetches final artifact

## 4) Minimum workflows to create in n8n

## 4.1 `resource_ingest_pipeline`
- Trigger: webhook from backend on new resource upload
- Steps:
  1) Validate payload and auth signature
  2) Download file (PDF/image)
  3) OCR/text extraction (if required)
  4) Chunk + metadata enrich
  5) Embedding generation
  6) Upsert vectors/doc metadata
  7) Mark ingest status complete/failed
- Operational resilience defaults:
  - Retry strategy: exponential backoff with jitter (`1s, 2s, 4s, 8s`), max 4 retries for transient errors.
  - Timeouts: download `30s`, OCR `120s`, embedding `90s`, vector upsert `30s`.
  - Failure policy:
    - Fail-fast (no retry): schema/auth/permission errors (`4xx`, signature mismatch).
    - Retryable: network timeout, `429`, `5xx`, temporary provider outages.
  - Dead-letter handling: after max retries, persist to `ai_jobs_dlq` with `job_id`, `attempt_count`, `last_error`, `trace_id`.

Output:
- `job_id`, `status`, `chunk_count`, `index_id`, `error`

## 4.2 `generate_quiz_artifact`
- Trigger: webhook job for AI Chat/Studio quiz request
- Steps:
  1) Load user context (college, semester, branch)
  2) Fetch candidate resources from backend/DB API
  3) Generate structured quiz JSON
  4) Validate schema (strict)
  5) Store artifact
  6) Callback backend with `artifact_url` + metadata
- Operational resilience defaults:
  - Retry strategy: exponential backoff with jitter, max 3 retries for model/provider/network failures.
  - Timeouts: resource fetch `20s`, generation `90s`, storage upload `30s`, callback `15s`.
  - Failure policy:
    - Fail-fast: invalid user scope, schema validation fail, unsupported action.
    - Retryable: model timeout, storage transient error, callback endpoint timeout.
  - Dead-letter handling: store final failure in `ai_jobs` (`status=failed`) and mirror to DLQ for replay.

Output:
- `action: "start_quiz"`, `artifact_url`, `question_count`, `status`

## 4.3 `generate_summary_report`
- Trigger: webhook job for summary/report request
- Steps:
  1) Retrieve scoped resources/attachments
  2) Generate summary content
  3) Render PDF/doc
  4) Upload to storage
  5) Callback backend
- Operational resilience defaults:
  - Retry strategy: exponential backoff with jitter, max 3 retries for transient provider/storage failures.
  - Timeouts: retrieval `20s`, generation `120s`, render `60s`, upload `30s`, callback `15s`.
  - Failure policy:
    - Fail-fast: invalid attachment payload, authorization failure, schema mismatch.
    - Retryable: network timeout, temporary PDF renderer/storage outage.
  - Dead-letter handling: failed jobs move to `ai_jobs_dlq` and surface user-visible failure state.

Output:
- `action: "download_report"`, `file_url`, `file_type`, `status`

## 4.4 `notify_job_completion`
- Trigger: status update from workflows
- Steps:
  1) Persist result to `ai_jobs`
  2) Send push notification (if enabled)
  3) Audit log
- Operational resilience defaults:
  - Retry strategy: exponential backoff with jitter, max 5 retries for notification delivery.
  - Timeouts: DB update `10s`, push publish `10s`, audit write `10s`.
  - Failure policy:
    - Fail-fast: unknown `job_id`, ownership mismatch, invalid callback schema.
    - Retryable: temporary DB lock/contention, push gateway timeout.
  - Dead-letter handling: enqueue undelivered notifications with `next_retry_at`.

### Cross-workflow retry state and validation guidance
- Persist retry state in `ai_jobs` (`attempt_count`, `next_retry_at`, `last_error`, `status_version`) and mirror exhausted jobs to `ai_jobs_dlq`.
- Test resilience before production:
  - Inject mock `429/500/timeouts` at OCR, embedding, storage, callback.
  - Run load tests at expected peak concurrency and 2x burst.
  - Verify replay from DLQ restores success without duplicate side effects.

## 5) Data contracts (recommended)

Use strict JSON payloads between backend and n8n.

### Contract versioning and schema validation
- Add `contract_version` in request and callback payloads.
- Store canonical schemas:
  - `request_schema` for backend -> n8n webhook payload
  - `callback_schema` for n8n -> backend callback payload
- Validate contracts on both sides (backend handler and n8n first node) before processing.

### Attachment size/pagination policy
- Enforce limits:
  - `max_attachments = 10`
  - `max_attachment_size_mb = 25`
- If limits are exceeded:
  - reject with validation error (`HTTP 422` for sync endpoints),
  - set callback `error` with code/details,
  - always include `trace_id` in failure payload for debugging.
- Optional pagination fields for large batches: `attachments_page`, `attachments_page_size`, `attachments_page_token`.

Request from backend to n8n:

```json
{
  "contract_version": "1.0.0",
  "job_id": "uuid",
  "job_type": "resource_ingest|generate_quiz|generate_summary_report",
  "user_id": "uid",
  "college_id": "kiet",
  "session_id": "chat-session-id",
  "resource_scope": {
    "file_id": "optional",
    "semester": "1",
    "branch": "cse",
    "subject": "python"
  },
  "attachments": [
    { "name": "notes.pdf", "url": "https://...", "type": "pdf" }
  ],
  "prompt": "Generate quiz for python loops",
  "trace_id": "uuid"
}
```

Callback from n8n to backend:

```json
{
  "contract_version": "1.0.0",
  "job_id": "uuid",
  "status": "completed|failed",
  "result": {
    "action": "start_quiz|download_report|none",
    "artifact_url": "https://...",
    "metadata": {}
  },
  "error": null,
  "trace_id": "uuid"
}
```

Schema-validation failure callback example:

```json
{
  "contract_version": "1.0.0",
  "job_id": "uuid",
  "status": "failed",
  "result": { "action": "none", "metadata": {} },
  "error": {
    "code": "SCHEMA_VALIDATION_FAILED",
    "message": "attachments exceeded max_attachments",
    "details": { "max_attachments": 10 }
  },
  "trace_id": "uuid"
}
```

## 6) Security requirements

1. Use signed webhooks (`x-webhook-signature` HMAC SHA-256).
2. Validate timestamp (`x-webhook-timestamp`) to prevent replay.
3. Restrict n8n ingress by IP/VPC/security group.
4. Store all credentials in n8n credentials vault or env vars, never in workflow text.
5. Use per-environment keys (`dev/stage/prod`).

### Signature key rotation policy
- Rotate webhook HMAC keys every 90 days (or immediately on suspected leak).
- Safe rollover:
  1) create new key in secret manager
  2) accept both old/new keys for 7-day overlap
  3) switch signers to new key
  4) remove old key after overlap
- Keep key IDs in headers/metadata to identify active verification key.

### Audit logging requirements
- Log at minimum: webhook receives, signature validation result, timestamp validation result, auth decisions, callback status updates, and replay detection events.
- Retain security/audit logs for 180 days minimum.
- Ship logs to centralized store (e.g., ELK/CloudWatch/Datadog) with immutable retention controls.

### Rate limiting and abuse controls
- Apply endpoint limits to webhook and callback paths:
  - default `60 req/min` per IP and `120 req/min` per service key,
  - burst allowance up to 2x for 10 seconds with token bucket.
- Throttle behavior:
  - return `429` with retry-after,
  - record rate-limit hits and anomaly score,
  - auto-block repeat offenders when abuse threshold is crossed.

## 7) Suggested infra (production)

1. n8n with persistent DB (Postgres)
2. Queue mode with Redis for reliability
3. Reverse proxy (Nginx/Caddy) with TLS
4. Separate worker process for heavy jobs
5. Log shipping and metrics

Operational additions:
- Resource sizing baseline:
  - n8n API node: 2 vCPU / 4 GB RAM baseline.
  - n8n worker: 2-4 vCPU / 4-8 GB RAM based on concurrent workflows and average job duration.
  - Start with queue-depth target `<100` pending jobs.
- Backup and DR:
  - Postgres daily snapshots + PITR with 30-day retention; weekly offsite backup copy.
  - Redis AOF/RDB enabled for queue durability where applicable; quarterly restore drills.
- Horizontal scaling triggers:
  - scale workers when queue backlog >200 for >10 minutes, CPU >70%, or memory >75%.
  - scale down only after 30-minute stabilization below thresholds.
- Monitoring and retention:
  - dashboards for queue depth, job duration, failure rate, retry rate, and infra saturation.
  - retain metrics 90 days, logs 180 days for capacity and incident analysis.

## 8) EC2 docker-compose baseline

```yaml
version: "3.9"
services:
  n8n:
    # Pin image tag; upgrade deliberately in controlled release windows.
    image: n8nio/n8n:1.25.0
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=n8n.yourdomain.com
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://n8n.yourdomain.com/
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${N8N_DB_PASSWORD}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 4G
        reservations:
          cpus: "1.0"
          memory: 2G
    depends_on:
      - postgres
      - redis

  n8n-worker:
    image: n8nio/n8n:1.25.0
    command: worker
    restart: unless-stopped
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${N8N_DB_PASSWORD}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:16.6
    restart: unless-stopped
    environment:
      - POSTGRES_DB=n8n
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=${N8N_DB_PASSWORD}
    volumes:
      - n8n-postgres:/var/lib/postgresql/data
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 4G
        reservations:
          cpus: "1.0"
          memory: 2G

  redis:
    image: redis:7.2.5-alpine
    restart: unless-stopped

volumes:
  n8n-postgres:
```

## 9) Backend integration checklist

1. Add `ai_jobs` table:
   - `job_id`, `job_type`, `status`, `status_version`, `user_id`, `session_id`, `payload_json`, `result_json`, `error`, `trace_id`, timestamps
2. Add backend endpoints:
   - `POST /api/ai/jobs` create job and forward to n8n
   - `GET /api/ai/jobs/:job_id` job status/result
   - `POST /api/ai/jobs/callback` n8n signed callback
3. Enforce authentication and authorization:
   - require auth for `POST /api/ai/jobs` and `GET /api/ai/jobs/:job_id`
   - verify user owns `job_id` (`user_id/session_id` check) before returning status
   - lock callback endpoint to trusted service identity + signature validation
4. Add rate limiting and throttling:
   - job creation limit: max 5 concurrent jobs per user, max 20 creates/min per user
   - status polling limit: max 60 polls/min per user
   - on limit breach return `429` and backoff hint
5. Add idempotency:
   - ignore duplicate callbacks by `job_id` + `status_version`
6. Data retention and cleanup:
   - archive or delete completed `result_json`/`error` after 30-90 days (policy-based)
   - retain minimal audit fields (`job_id`, `trace_id`, status timeline) for 180 days
7. Observability:
   - propagate/store `trace_id` through backend -> n8n -> backend and include in error logs and alerts
   - ensure retention/idempotency policies preserve traceability for incident review

## 10) Flutter integration checklist

1. When user asks for quiz/report generation:
   - call `POST /api/ai/jobs`
   - show loading state in chat bubble
2. Poll `GET /api/ai/jobs/:job_id` with exponential backoff:
   - start at `1s`, double each retry (`1, 2, 4, 8...`) capped at `30s`
   - reset backoff on successful status response
3. Polling timeout policy:
   - stop polling after 5 minutes total
   - surface failure state with clear user message: "This is taking longer than expected. Please retry."
4. Error-state UX:
   - show specific messages for network error, auth error, server error, timeout
   - keep the failed job card visible with timestamp and error reason
5. Retry controls:
   - provide "Retry job" button to re-call `POST /api/ai/jobs`
   - provide "Resume status check" button to continue polling existing `job_id`
6. On completion:
   - for quiz: render `Start Quiz` action button
   - for report: render `Download Report` action button
7. Never show raw source URLs in assistant text

## 11) Rollout plan

1. Stage first:
   - run n8n with synthetic jobs
   - validate callbacks and retries
   - verify dashboards and alerts are active before traffic is enabled
2. Canary:
   - route 10% quiz/report jobs via n8n for 48h
   - canary success criteria:
     - error rate `<=2%`
     - P95 job completion latency `<=30s`
     - no increase in retry/backoff failure loops
     - throughput supports projected peak with <=70% worker CPU
3. Staged rollout:
   - increase 10% -> 25% -> 50% -> 100% only after each stage passes 24-72h gates

### Rollback criteria
- Trigger rollback if any occurs during canary/staged windows:
  - error rate >5%
  - P95 latency >30s sustained for 15+ minutes
  - retry exhaustion or backoff-failure rate >3%
  - callback signature failures or auth anomalies spike above baseline

### Rollback procedure
1. Disable n8n feature flag / routing rule in backend.
2. Route all new jobs to previous stable path.
3. Stop canary traffic and revoke n8n callback ingress for canary source if needed.
4. Keep existing in-flight jobs readable; mark incomplete jobs with recoverable failure state.
5. Publish incident note with `trace_id` samples and remediation owner.

### Monitoring and alerting requirements
- Required metrics: request error rate, callback error rate, queue depth, retry counts, P50/P95/P99 job latency, worker CPU/memory.
- Required alerts:
  - error-rate and latency thresholds from rollback criteria
  - queue backlog growth and dead-letter growth
  - signature validation failure bursts
- On-call ownership must be assigned before each rollout stage.

## 12) Done criteria

1. `>=95%` job completion without manual retry
2. `<=5s` median time to first status update in app
3. `>=95%` schema-valid quiz artifacts
4. `0` unsigned callback accepted by backend

## 13) Link with current plan

Use this guide with:
- `AI_CHAT_MODERNIZATION_PLAN.md`
