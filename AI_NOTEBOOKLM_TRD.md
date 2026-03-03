# StudyShare AI (NotebookLM-Style) Technical Requirements Document (TRD)

Last updated: March 3, 2026  
Owner: AI Platform Engineering

## 1. Scope

Define the technical architecture and delivery plan for a NotebookLM-like AI layer in StudyShare:
1. Context-aware conversational QA.
2. Reliable quiz generation and attempt lifecycle.
3. OCR-first extraction resilience.
4. Grounded citations and confidence-aware fallback.

This TRD builds on current backend RAG services and modernizes them for quality and determinism.

## 2. Current Baseline (verified)

1. Client calls backend RAG APIs:
- `POST /api/rag/query`
- `POST /api/rag/query/stream`

2. Backend uses Gemini models:
- Generation model: `gemini-2.5-flash`.
- Embedding model: `text-embedding-004`.

3. Retrieval stack:
- Hybrid lexical + semantic scoring.
- Query rewrite for follow-ups (limited).
- Web fallback available (Wikipedia/DuckDuckGo).

4. OCR:
- Ingestion path uses structured extraction with OCR for scanned PDFs.
- Query-time attachment extraction supports OCR but currently de-prioritizes some attachment types.

## 3. Target Architecture

## 3.1 Logical components

1. Client Layer (Flutter)
- AI Chat UI, AI Studio workflows, quiz player, result review.

2. AI Orchestrator (Backend API)
- Intent routing, tool invocation, response contract normalization.

3. Retrieval Engine
- Query preprocess, hybrid retrieval, reranking, confidence scoring.

4. Memory Engine
- Session history + compression + long-term semantic memory (opt-in).

5. Artifact Engine
- Quiz/report generation, validation, repair, storage callbacks.

6. Ingestion/OCR Pipeline
- PDF/document/image extraction, OCR fallback, chunking, embedding.

7. Async Workflow Engine (n8n with explicit decision criteria)
- Use n8n when any of these are true:
  - ingestion payload > `25` MB,
  - expected async processing latency > `30s`,
  - workflow requires retries + DLQ + callback orchestration.
- Routing guard: jobs initially estimated `>30s` are routed directly to n8n and are not eligible for internal-queue-to-n8n re-routing later.
- If criteria are not met, run the built-in backend worker/queue path.

## 3.2 Deployment topology

1. Synchronous path (chat)
- Flutter -> backend -> retrieval + generation -> stream response.

2. Asynchronous path (heavy jobs)
- Backend -> queue/webhook -> n8n workers -> callback.
- If n8n criteria are not met, Backend -> internal worker queue -> callback with equivalent status contract.

## 3.2.1 Internal Worker Queue Specification

1. Queue implementation
- Default: Redis-backed job queue (`bullmq`-style semantics) with durable job payload storage.
- Alternatives allowed by deployment profile: RabbitMQ or SQS with the same status contract.

2. Retry policy
- Max attempts: `5`.
- Backoff: exponential (`5s`, `30s`, `2m`, `10m`, `30m`) with jitter.

3. DLQ handling
- Failed jobs after max retries move to DLQ.
- DLQ retention: `14` days by default.
- Replay: manual replay endpoint + scheduled replay worker for approved job classes.

4. Callback contract
- Worker callback payload must include: `job_id`, `status`, `status_version`, `result|error`, `trace_id`, `updated_at`.
- Callback retries: exponential backoff, max `5` attempts, idempotent by `job_id + status_version`.

5. Async latency estimation and escalation
- `expected async processing latency` is estimated from rolling historical metrics by job type and source size bucket.
- Escalation anti-oscillation rule: only jobs initially routed to internal queue (initial estimate `<=30s`) can be re-routed, and only once (`reroute_attempted=true`) when observed runtime exceeds `60s` (hysteresis).
- On re-route, emit alert with `job_id`, `initial_estimate`, `observed_runtime`, and `reroute_attempted=true`; do not route the same job back to internal queue.

3. Storage and state
- `rag_files`, `rag_chunks`, `rag_query_cache`, `rag_chat_sessions`, `rag_chat_turns`.
- Add `ai_quiz_artifacts`, `ai_quiz_attempts`, `ai_quiz_attempt_answers`.

## 4. Functional Technical Requirements

## 4.1 Query Understanding Pipeline

Required steps before retrieval:
1. Normalize and sanitize input.
2. Typo correction (edit distance + embedding nearest term map).
3. Acronym/synonym expansion (e.g., `np`, `numpy`, `nunpy` -> `NumPy`).
4. Follow-up rewrite to standalone query using prior turns.
5. Intent classification: `qa`, `quiz`, `summary`, `flashcards`, `search`.

Acceptance:
- On typo benchmark, retrieval miss rate reduced by >=40%.

## 4.2 Retrieval Pipeline (must move beyond word matching)

Pipeline order:
1. Scope resolution:
- pinned resource -> turn attachments -> profile/campus scope -> broader campus.
2. Candidate retrieval:
- lexical BM25/FTS + dense vector retrieval.
3. Fusion and reranking:
- reciprocal rank fusion + cross-encoder reranker (default for production real-time traffic).
- optional LLM rerank pass only for high-value/low-throughput paths (escalations, batch review, or when quality thresholds fail).
- LLM rerank trigger condition: any confidence-threshold condition met AND cost budget available.
- LLM rerank must run async/fallback so real-time latency SLA is not violated.
4. Confidence estimation:
- `retrieval_score`, `citation_coverage`, `answer_consistency`.
5. Decision:
- answer local OR fallback to web OR ask clarification.

Minimum requirements:
1. Top-k retrieval: default 8, max 12.
2. Reranked shortlist used for final generation prompt.
3. Structured source objects always returned with page/timestamp metadata.

## 4.2.1 Confidence Thresholds

1. `retrieval_score` threshold
- `threshold_low_retrieval_score = 0.45`.

2. `citation_coverage` threshold
- `threshold_low_citation_coverage = 0.60`.

3. `answer_consistency` definition
- Generate two independent candidate answers from the same retrieved context.
- Compute embedding cosine similarity between the two answers.
- Configurable threshold: `ANSWER_CONSISTENCY_THRESHOLD` (default `0.80`) from environment/config.
- Mark consistency failed when cosine `< ANSWER_CONSISTENCY_THRESHOLD`.
- Dual-generation trigger policy:
  - Default: do dual generation only for quality-sensitive paths (`low retrieval_score`, `low citation_coverage`, escalation flows, or when fallback decision is uncertain).
  - Do not run dual generation on every query by default.
- Cost impact guidance:
  - For queries where dual generation runs, generation-stage LLM cost is approximately 2x.
  - Overall blended cost increase is approximately `dual_generation_coverage_rate * baseline_generation_cost`.
- Cost budget enforcement:
  - Gate with per-minute and daily caps (`ANSWER_CONSISTENCY_BUDGET_PER_MIN`, `ANSWER_CONSISTENCY_BUDGET_PER_DAY`).
  - Concurrency semantics: enforce budget consumption with atomic decrements (for example Redis `INCR`/Lua or token-bucket lease) so concurrent requests cannot over-allocate budget.
  - Window/reset semantics:
    - per-minute budget uses rolling 60-second token-bucket refill,
    - daily budget uses UTC-midnight reset (single authoritative timezone).
  - Sizing guidance:
    - start with `ANSWER_CONSISTENCY_BUDGET_PER_MIN ~= expected_qps * quality_sensitive_ratio * 60`.
    - set `ANSWER_CONSISTENCY_BUDGET_PER_DAY ~= daily_requests * quality_sensitive_ratio` with 10-20% headroom.
    - Example: `20 qps`, `10%` quality-sensitive -> per-minute budget baseline `120`; if daily requests `1.2M`, daily budget baseline `120k`.
  - If budget is exhausted, skip dual generation and continue with single-generation path while recording a `budget_exhausted` reason.
- Required telemetry:
  - `answer_consistency_comparisons_total`,
  - `answer_consistency_similarity_mean`,
  - `answer_consistency_similarity_p50`,
  - `answer_consistency_rerank_trigger_total`,
  - `budget_exhausted_count` (labels: `window=minute|day`, endpoint/intention labels),
  - budget gauges: `answer_consistency_budget_remaining_minute`, `answer_consistency_budget_remaining_day`,
  - budget timestamps: `budget_window_minute_started_at`, `budget_window_day_started_at`.
- Rollout/tuning requirement: run A/B evaluation with candidate thresholds `0.70`, `0.80`, `0.85` and select production default based on quality/cost tradeoff.

## 4.2.2 LLM Rerank Async Behavior

1. Trigger
- Enqueue async LLM rerank job when any threshold condition is met AND cost budget is available.

2. Runtime behavior
- Current request proceeds with cross-encoder rerank result (no blocking on LLM rerank).
- LLM rerank runs as a background job and may update retrieval cache metadata.

3. User-facing behavior
- No real-time retry/update is pushed to the current response.
- Async rerank output is logged for quality analytics and future cache-assisted queries.

4. Latency semantics
- Latency budget is only a gating condition for enqueue/no-enqueue decisions; it does not block current request completion.

## 4.3 OCR and Extraction Strategy

1. Ingestion-time OCR policy
- Always run extraction quality check.
- Compute:
  - `text_density = extracted_char_count / page_area_sq_in` where `page_area_sq_in = page_width_inches * page_height_inches` (derive from PDF metadata or DPI).
  - `confidence_score = mean(token_confidences)` when token-level confidence exists; fallback to `provider_page_confidence` or mean word confidence when token-level scores are unavailable.
  - `normalized_text_density = scale_to_0_100(text_density, min_density, max_density)`.
  - Default density bounds: `min_density=50` and `max_density=1500` (chars per square inch), configurable via `OCR_TEXT_DENSITY_MIN` / `OCR_TEXT_DENSITY_MAX`.
  - `scale_to_0_100(text_density, min_density, max_density)` contract:
    - internally clamp input: `x = clamp(text_density, min_density, max_density)`,
    - scale: `((x - min_density) / (max_density - min_density)) * 100`.
  - Clamping note: input clamping guarantees output in `[0,100]` for valid bounds; any extra output clamp is optional external sanity-checking, not required behavior.
  - `extraction_quality_score = (weight_confidence * confidence_score) + (weight_density * normalized_text_density)` with defaults `weight_confidence=0.6`, `weight_density=0.4` (both tunable).
- Mark low-text/scanned when `extraction_quality_score < 30` OR raw word count `< 100` words/page.
- If scanned/low-text: OCR and store OCR provenance in metadata.

2. Query-time OCR policy
- Trigger OCR retry when:
  - no local chunks above threshold, and
  - candidate source is scanned/low-confidence extraction (`extraction_quality_score < 30`).

3. OCR provider strategy
- Primary provider configurable (`google`/`sarvam`).
- Circuit breaker + fallback provider support.
- Supported confidence fallback semantics must be documented per provider (`token`, `word`, `page` confidence availability).

4. Required metadata
- `is_scanned_detected`, `is_ocr_processed`, `ocr_provider`, extraction quality score.
- Field names for implementation: `is_scanned_detected`, `is_ocr_processed`, `ocr_provider`, `extraction_quality_score`.

## 4.4 Response Contract Normalization

Every AI response must conform to:
1. `answer` (string).
2. `sources[]` (structured metadata only).
3. `confidence` (`high|medium|low` + numeric score).
4. `actions[]` (UI actions like `start_quiz`, `download_report`).
5. `no_local` (boolean).

Never include raw source URLs directly in prose answer body.

## 4.5 Quiz Generation Reliability

## 4.5.1 Generation contract
Generate strict JSON:
1. paper metadata.
2. questions array.
3. each question: text, 4 options, one correct answer, explanation, source mapping.

## 4.5.2 Validation/repair pipeline
1. Schema validation.
2. Semantic validation:
- no placeholders,
- option uniqueness,
- answer index in range,
- minimum unique question ratio.
3. Auto-repair pass for minor violations.
4. Regenerate if validation still fails.

## 4.5.3 Attempt lifecycle
1. Start quiz -> save attempt row.
2. Save per-question selected answer.
3. Submit -> lock attempt and compute score.
4. Review endpoint returns:
- selected vs correct answer per question,
- explanation,
- source mapping.

Required DB additions:
1. `ai_quiz_artifacts(id, user_id, session_id, paper_json, status, created_at)`.
2. `ai_quiz_attempts(id, artifact_id, user_id, score, total, submitted_at)`.
3. `ai_quiz_attempt_answers(id, attempt_id, question_idx, selected_idx, correct_idx)`.

Retention policy (configurable):
1. `ai_quiz_artifacts`: default 90 days from `created_at`.
2. `ai_quiz_attempts` (completed): default retention is 1 year from `submitted_at`; configure via `RETENTION_AI_QUIZ_ATTEMPTS_YEARS` (default `1`, set to `2` to extend to 2 years).
3. `ai_quiz_attempts` + `ai_quiz_attempt_answers` (incomplete/failed): retained exactly 30 days from `created_at`.
4. Scheduled cleanup job:
  - delete/anonymize rows older than configured thresholds,
  - purge incomplete/failed attempts after the 30-day window,
  - enforce cascade handling `ai_quiz_artifacts -> ai_quiz_attempts -> ai_quiz_attempt_answers`.
5. Expose retention durations as environment config for compliance overrides.

## 4.5.4 Data Deletion and Compliance

1. User-initiated deletion override
- User deletion requests override retention windows and must complete within 14 days (stricter than GDPR Article 17's one-month requirement).
- SLA definition:
  - clock start: deletion request acceptance timestamp (`deletion_requested_at`),
  - clock stop: audit-confirmed purge completion across active stores (`deletion_completed_at`) plus user-visible confirmation.
- Observability and compliance tracking (mandatory):
  - unique `deletion_job_id`,
  - timestamps: request/queued/start/finish,
  - per-table verification counts or hashes (`answers`, `attempts`, `artifacts`),
  - immutable audit entry with requester, operator/system actor, reason, and outcome,
  - audit-log retention for regulatory queries.
- Allowed exception classes (must be explicitly recorded with approver identity and justification):
  - legal hold,
  - backup retention lock window,
  - active dispute/investigation.
- Exception handling:
  - exception intervals pause or extend SLA accounting only when approved and logged,
  - resumed processing must re-enter expedited queue immediately after exception clearance.

2. Cascade deletion order
- Required order: `ai_quiz_attempt_answers -> ai_quiz_attempts -> ai_quiz_artifacts`.
- Cleanup implementation requirement (automated job):
  - execute transactional, idempotent cleanup with referential integrity guarantees,
  - preserve logical deletion order (`answers -> attempts -> artifacts`) or equivalent FK-safe cascade behavior,
  - enforce bounded batches and a safety window (for example, delay final hard delete by 24h after soft-mark) to prevent accidental mass deletion.
  - expedited deletion path semantics (user-initiated):
    - do not immediate-hard-delete by default; place rows in an `expedited_soft_mark` quarantine state (default `48h`, configurable `24-72h` per deletion and audit-logged),
    - duration selection rules:
      - `24h` for low-risk deletions (for example non-sensitive, single-user, automated housekeeping),
      - `48h` default for standard expedited requests,
      - `72h` for high-risk deletions (for example sensitive data, shared resources, pending legal/verification checks),
    - hard-delete before quarantine expiry is allowed only with auditable admin override.
  - expedited safeguards:
    - ownership verification and strong requester confirmation before enqueue,
    - operator/admin override requires MFA-backed confirmation,
    - deletion audit log entry must include requester, timestamp, reason, approver/operator ID, and override flag.
  - operational controls:
    - enforce bounded batches with rate limits on expedited jobs,
    - document recovery/override procedure for accidental expedited requests.

3. Anonymize vs delete
- Identifiable learner responses require deletion (not anonymization-only).
- Anonymization is allowed only for non-identifiable aggregate analytics.

4. Configurability
- Retention/deletion windows are environment-configurable for regional compliance overrides.

## 4.6 Memory Engine

Implement memory as defined in modernization plan:
1. Rolling uncompressed window (last 12 turns + summary memory).
2. Compression threshold based on token budget.
3. Incremental compression of oldest eligible turn until below threshold.

Required memory APIs:
1. `loadSessionMemory(sessionId, userId, scope)`.
2. `persistTurnPair(sessionId, userId, userTurn, assistantTurn)`.
3. `compressSessionMemory(sessionId)` with deterministic loop.

## 4.7 Web Fallback Policy

1. Trigger only when local confidence threshold fails OR user explicitly asks internet fallback.
2. Allowed sources:
- `wikipedia.org` plus vetted, explicitly approved education/news hosts from backend whitelist.
- Replace blanket `*.edu` with verified institution root domains or approved subdomains only.
3. Fetch limits:
- max 5 sources/request, max 3 snippets/source.
4. Reliability and bias heuristics (explicit):
- Score each source on a `0..100` scale per metric, then combine:
  - `provenance_score`: weighted sum of `source_type_score` (official docs/journals > community blogs), transport/security checks (HTTPS valid, no TLS errors), and ownership transparency (`about/contact/publisher` presence).
  - `author_credibility_score`: weighted sum of verified author identity, institutional affiliation, and historical correction/retraction profile.
  - `citation_density_score`: normalized ratio of verifiable citations/references per 1,000 words (with spam-reference suppression).
  - `domain_reputation_score`: weighted sum of domain age, historical uptime, abuse/spam history, and backend-maintained allowlist reputation.
- Reliability score composition:
  - `reliability_score = 0.35*provenance_score + 0.20*author_credibility_score + 0.25*citation_density_score + 0.20*domain_reputation_score`.
  - Bands (aligned with trust threshold): `low < 40`, `medium 40..59`, `high >= 60`.
  - Band semantics and operational trust are aligned: `high` corresponds to trusted threshold `reliability_score >= 60`.
  - Decision threshold: treat source as `trusted` when `reliability_score >= 60`; otherwise `untrusted` and deprioritize or drop.
  - Tie-breaker: if two candidates are within 3 points, prefer higher `provenance_score`, then newer source (if query is time-sensitive).
  - Example: provenance `82`, author `60`, citations `55`, domain `75` -> reliability `69.45` (`high` band, `trusted` by threshold).
5. Operational controls:
- per-source and global web-fetch rate limits,
- response timeouts,
- cache repeated queries,
- circuit breaker that temporarily blacklists flaky hosts.
6. Time-sensitivity classifier:
- Trigger inputs:
  - keyword sets (examples): `latest`, `today`, `recent`, `new law`, `release`, `breaking`, `deadline`, `current`.
  - NER/entity types: `news_event`, `legislation`, `product_release`, explicit date/time entities.
- Classifier logic: mark `time_sensitive=true` when `(keyword_match OR entity_type_match OR explicit_recency_request)` is true.
- Recency thresholds by entity type:
  - `news_event`: 7 days,
  - `legislation`: 30 days,
  - `product_release`: 90 days.
- Apply strict recency filtering only when `time_sensitive=true`; otherwise rely on reliability ranking first.
- Example: query contains `latest` + `product_release` entity -> time-sensitive, enforce 90-day recency filter.
7. Re-rank fetched snippets.
8. Mark response provenance as `web`.
9. Keep local-vs-web distinction visible to user.

## 5. API Contracts (Target)

## 5.1 Chat query
`POST /api/rag/query`

Request additions:
1. `intent_hint` (optional).
2. `mode`: `local_only|local_then_web`.
3. `notebook_id` (optional).
4. `confidence_policy` (optional override).

Response additions:
1. `confidence: { score, band, reasons[] }`.
2. `retrieval_debug: { rewritten_query, top_scores[], fallback_reason }` (debug/admin only).

## 5.2 Quiz workflow APIs

1. `POST /api/ai/quiz/generate`
- returns `artifact_id`, `status`.

2. `POST /api/ai/quiz/:artifact_id/start`
- returns `attempt_id` + quiz payload.

3. `POST /api/ai/quiz/:attempt_id/answer`
- save answer for question.

4. `POST /api/ai/quiz/:attempt_id/submit`
- returns `score_summary`.

5. `GET /api/ai/quiz/:attempt_id/review`
- returns per-question review data.

## 5.3 Standard errors and rate limits

Error response schema (all endpoints above):
1. `status` (HTTP status code).
2. `error_code` (machine code, stable).
3. `message` (human-readable summary).
4. `details` (optional object).
5. `field_errors` (optional array for validation):
- `{ field, issue, code }`.

Rate-limiting defaults:
1. `POST /api/rag/query`: `60` requests/min/user.
2. Quiz write endpoints (`generate/start/answer/submit`): `30` requests/min/user.
3. Quiz review endpoint: `90` requests/min/user.
4. On limit exceed: return `429` with `Retry-After` header and body:
- `{ "status": 429, "error_code": "RATE_LIMIT_EXCEEDED", "message": "...", "details": { "retry_after_seconds": N } }`.
5. Unauthenticated behavior:
- unauthenticated clients are IP-limited to `10` requests/min.
- quiz write endpoints require authentication (unauthenticated requests rejected).
6. Algorithm:
- token-bucket with per-minute refill, burst capacity `limit/4`, refill rate `limit/60` tokens/sec.
7. Distributed enforcement:
- Redis atomic counters/tokens with keys like `ratelimit:{endpoint_group}:{user_id}` (or `...:{ip}` for unauthenticated).
- if Redis unavailable, use degraded per-instance fallback limiter and emit warning metrics.
8. Overrides:
- admin identities receive `10x` standard limits.
- trusted service accounts are exempt.
9. `retrieval_debug` must never be exposed to non-admin users in error payloads.

## 6. Performance and Caching

1. Query cache key should include:
- normalized rewritten query,
- filters,
- session context hash,
- attachment hash,
- scope mode.

2. Retrieval cache:
- ingestion events that invalidate cache:
  - new file upload,
  - file content update,
  - OCR completion/retry completion,
  - reindex completion,
  - source metadata change.
- invalidation mechanism:
  - emit ingestion event bus/webhook events with resource IDs and ingestion version,
  - increment per-resource ingestion counter,
  - include ingestion version in cache key/header validation.
- invalidation scope:
  - default: resource-specific invalidation keyed by `attachment hash`/resource ID,
  - session-specific invalidation keyed by `session context hash` when chat context changes,
  - global invalidation only for index-wide reindex.
- `no_local` handling:
  - short TTL (default 2-5 minutes) plus immediate event-driven invalidation for affected keys.

## 6.1 Cache Infrastructure Requirements

1. Event bus and delivery guarantees
- Technology: Redis Streams (default) or Kafka in high-scale deployments.
- Delivery guarantee: at-least-once delivery with idempotent consumers.
- Event schema minimum:
  - `event_type`, `resource_id`, `user_id`, `attachment_hash`, `session_context_hash`, `ingestion_version`, `occurred_at`.

2. TTL strategy (fallback absolute TTLs)
- Query cache absolute TTL: default 10 minutes.
- Resource-scoped retrieval cache absolute TTL: default 30 minutes.
- `no_local` cache absolute TTL: default 2-5 minutes.
- Event-driven invalidation always takes priority over TTL expiry.

3. Cache layers and cache-control behavior
- Server-side cache layers only: in-memory L1 + Redis L2.
- No client-side/CDN caching for AI retrieval/query responses.
- Include `ingestion_version` in response metadata and cache key composition.

4. Reindex mitigation (thundering herd protection)
- Use batched/gradual invalidation for index-wide reindex jobs.
- Preserve old cache entries temporarily with `degraded=true` metadata during migration windows.
- Pre-warm critical queries/resources after reindex to reduce cold-start spikes.

3. Embedding cache:
- maintain query embedding cache with size limits and LRU eviction.

4. Latency budgets:
- retrieval <=1.5s p95,
- rerank <=1.0s p95,
- generation first token <=3.5s p95 (local mode).

## 7. Security and Privacy

1. Strict tool/action allowlist.
2. JSON schema validation on all tool input/output.
3. Per-user and per-college authorization filters in every retrieval path.
4. Prompt-injection hardening:
- strip/escape tool directives from user content.
- do not allow user text to override system tool policies.
5. Encryption at rest and in transit for memory/artifact data.
6. Audit logs for query, tool decisions, fallback reasons, and security events.

## 8. Observability and Evaluation

## 8.1 Telemetry

Capture per request:
1. latency by stage (`intent`, `retrieve`, `rerank`, `generate`, `postprocess`).
2. retrieval stats (`top_score`, chunk count, source mix).
3. fallback reason (`none`, `low_confidence`, `no_local`, `user_requested_web`).
4. quiz pipeline stats (schema fail rate, repair rate, regenerate rate).

## 8.2 Eval harness

1. Gold dataset of 300+ academic queries:
- typo cases, follow-up references, low-context asks, quiz intents.
2. Metrics:
- retrieval recall@k,
- citation precision,
- groundedness,
- no-answer precision,
- quiz validity rate.
3. Deploy gate:
- block rollout if critical metrics regress beyond thresholds.

## 9. n8n Role in This Design

Use n8n for:
1. long-running ingestion/reindex pipelines,
2. artifact generation retries,
3. DLQ replay workflows,
4. scheduled maintenance jobs.

Do not use n8n for:
1. token-by-token chat streaming path,
2. latency-sensitive retrieval/answer orchestration.

## 10. Implementation Plan

## Phase 1 (2-3 weeks): Context and Quiz Stability
1. Add typo/synonym rewrite module.
2. Add rerank stage in retrieval pipeline.
3. Improve OCR retry triggers for no-context outcomes.
4. Implement quiz validation + repair loop.
5. Add quiz attempt/review APIs and DB tables.

Deliverables:
1. reduced false no-local responses,
2. reliable quiz generation and review.

## Phase 2 (3-5 weeks): NotebookLM Experience
1. notebook/source scope model.
2. response confidence bands and richer citation UX.
3. memory compression and long-term memory toggle.

Deliverables:
1. notebook-scoped chat quality improvements,
2. stronger multi-turn continuity.

## Phase 3 (ongoing): Scale and Cost Optimization
1. adaptive routing by intent and confidence.
2. dynamic chunk budgeting.
3. provider abstraction and A/B testing.

Deliverables:
1. lower cost per answer at stable quality,
2. predictable p95 latency.

## 11. Risks and Fallbacks

1. Model API instability
- fallback to extractive answer path.

2. OCR provider failures
- retry with alternate provider; mark degraded mode.

3. Retrieval schema drift
- strict migration checks + compatibility fallbacks.

4. Cost drift
- adaptive top-k and rerank thresholds + cache-first strategy.
