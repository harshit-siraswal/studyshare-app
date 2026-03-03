# AI Chat Modernization Plan

Last updated: February 28, 2026

Companion documents for NotebookLM-style direction:
- `AI_NOTEBOOKLM_PRD.md` (product scope, UX, acceptance criteria)
- `AI_NOTEBOOKLM_TRD.md` (architecture, retrieval/OCR/quiz implementation plan)

## Product split (must stay explicit)
- AI Studio: in-resource workflows (summary, quiz, flashcards) from a selected PDF/resource.
- AI Chat: open assistant from home with cross-resource memory, intent routing, and internet fallback.

## Current gaps
- Chat context is not persisted/reused reliably across turns.
- Stream route probing adds avoidable latency when backend has no stream endpoint.
- Upload metadata leaks into user-visible chat text.
- Quiz/report intents are partially supported but tool routing is still prompt-fragile.
- Source attribution is inconsistent between backend response formats.

## Target architecture
1. Intent Router (backend)
- Classify request into: `answer`, `generate_quiz`, `generate_summary_report`, `resource_search`.
- Use function/tool calling instead of free-form prompt-only branching.
- Enforce strict JSON schema validation on router input/output and whitelist allowed actions/parameters to block prompt-injection and malformed tool calls.

2. Memory model (backend)
- Short-term memory: rolling session window (last 12 turns + summary memory), retained for 30 days from last activity.
- Long-term memory: per-session semantic memory store keyed by user + chat session, retained for 180 days by default.
- User privacy controls: explicit opt-in for long-term memory, one-click memory disable per chat, and deletion request handling (GDPR/CCPA) with hard-delete SLA <=30 days.
- Security controls: sanitize/redact sensitive fields before storage, encrypt at rest (AES-256) and in transit (TLS 1.2+), and enforce role-based access controls for memory read/write paths.
- Compression: keep a "rolling window of the last 12 turns plus summary memory" uncompressed. Define `uncompressed_session_token_budget = model_token_budget - (system_tools_reserved + retrieval_budget + output_budget + estimated_summary_tokens)` and trigger compression when `uncompressed_session_tokens > max(uncompressed_session_token_budget, min_compression_threshold)`.
- Incremental compression loop: when the threshold is exceeded, the main loop repeatedly calls `compress_next_turn_until_budget(...)` as its reusable per-turn helper (not a separate scheduler), recomputes `uncompressed_session_tokens`, and repeats until it is at or below the exit target (`threshold - compression_safety_margin`, default margin `0`) - i.e., until `uncompressed_session_tokens > exit_target` is false.
- Non-progress guard: implement `MAX_COMPRESSION_ITERATIONS` (default `64`) in the loop that calls `compress_oldest_turn`/`compress_turn`; break with a deterministic fallback if the cap is reached.
- Token-reduction check per iteration: compute reduction after the initial compression attempt (`tokens_reduced_precap`) and after optional capping (`tokens_reduced_postcap`). Use `tokens_reduced_precap < min_token_delta` only to decide whether to attempt `apply_per_turn_token_cap`; mark `non_compressible_turn` only if final `tokens_reduced_postcap < min_token_delta` (default `16`), then persist the flag, skip it in subsequent iterations, and continue to the next eligible turn (do not terminate the cycle early unless `MAX_COMPRESSION_ITERATIONS` is reached).
- Compression helper primitive definitions:
  - `apply_per_turn_token_cap(turn, cap_tokens) -> capped_turn`: aggressively truncates or summarizes a single oversized turn to `<= cap_tokens`, returns updated turn + tokens reduced.
  - `compress_next_turn_until_budget(session, threshold, single_step=true, turn_override=null) -> compression_step_result`: reusable helper called by the main loop. In one step it selects the next eligible turn (or uses `turn_override`), attempts compression, and if initial reduction is below `min_token_delta` it invokes `apply_per_turn_token_cap` for that same turn before returning:
    - `pre_tokens`, `post_tokens`,
    - `tokens_reduced_precap` (initial compression reduction),
    - `tokens_reduced_postcap` (total final reduction for this single turn, including compression and any optional cap; equals `tokens_reduced_precap` when no cap is applied, never a marginal-only field),
    - `turn_id`, and status flags (`used_cap`, `marked_non_compressible_candidate`).
  - `used_cap` contract: `used_cap=false` when no cap routine is executed; `used_cap=true` only when `apply_per_turn_token_cap` actually ran.
  - `marked_non_compressible_candidate` contract: this flag is set by `compress_next_turn_until_budget` for non-token failure modes (for example timeout, provider/API hard error, unsupported turn format). It is not required for token-delta-only decisions because callers can derive those from `tokens_reduced_postcap < min_token_delta`.
- `non_compressible_turn` persistence/retry policy:
  - Persist `non_compressible_turn=true` with `last_attempt_epoch` and `failure_reason`.
  - Skip flagged turns in future compression cycles.
  - Clear flag only on explicit external trigger (turn edit/delete/re-upload) or epoch reset (`compression_epoch` increment).
- Progress safeguard and rolling-window invariant: keep the rolling window uncompressed by default. Allow within-window compression only as an emergency safeguard when all older-than-window turns are exhausted and either (a) no progress is observed for two consecutive calls to `compress_next_turn_until_budget` (across any turn, not same-turn-only), defined as `tokens_reduced_postcap < min_token_delta` in each of those two calls, with `uncompressed_session_tokens` recomputed after each call, or (b) a hard storage/token safety limit is reached.
- Deterministic termination fallback when `MAX_COMPRESSION_ITERATIONS` is hit:
  - stop active compression loop for this cycle,
  - deterministically drop oldest turns beyond `RETENTION_TURNS` (configurable; default `12`, and equal to `SHORT_TERM_WINDOW_TURNS` by default) to free space,
  - optionally apply aggressive per-turn capping before drop if enabled,
  - log warning with `MAX_COMPRESSION_ITERATIONS`, `turns_dropped`, and `tokens_reduced`,
  - mark cycle `compression_incomplete=true` so next compression cycle resumes remaining eligible turns.
- Compression cycle trigger and resume policy:
  - Event-driven trigger: enqueue a compression cycle after turn persistence when threshold is exceeded.
  - Periodic trigger: background worker runs every `5` minutes and scans sessions with `compression_incomplete=true` or threshold breach.
  - On-demand trigger: request-path preflight may run one cycle when threshold is exceeded and no active cycle lock exists.
  - Concurrency limit: one active compression cycle per session (`session_id` lock). The merge window is a fixed `60s` interval that starts when the active cycle acquires the `session_id` lock (non-sliding). `pending_rerun` is a single boolean per `session_id`: triggers during the merge window set/refresh that boolean but do not extend the window and do not create additional queued reruns. Triggers after the merge window expires but before the active cycle completes set the same boolean for the next queued rerun. When the active cycle completes, exactly one queued rerun executes if `pending_rerun=true`; that rerun acquires the same `session_id` lock and starts its own fixed `60s` merge window.
  - Retry/backoff for cycle failures: `30s`, `2m`, `10m` (max `3` retries) before leaving `compression_incomplete=true` for the next periodic run.
  - Resume behavior: if `compression_incomplete=true`, the next worker tick (and eligible on-demand trigger) resumes from remaining eligible turns.
  - Emergency predicate definition (side-effect-free function):
    - `emergency_window_compression_allowed(session_state) -> bool` returns `true` only when:
      - older-than-window turns are exhausted, and
      - (`session_state.consecutive_no_progress_count >= 2`) OR (`current_storage_usage >= storage_usage_threshold` OR `uncompressed_session_tokens >= token_usage_hard_limit`).
    - `session_state.consecutive_no_progress_count` is session-persistent (stored on the session object and not reset at cycle start), increments immediately after each `compress_next_turn_until_budget` call when `tokens_reduced_postcap < min_token_delta`, and resets to `0` when `tokens_reduced_postcap >= min_token_delta`.
    - The function reads external `session_state` counters/thresholds but performs no state mutation; all mutations happen in the compression loop/controller.
- Compression loop pseudocode:
  - `threshold = max(uncompressed_session_token_budget, min_compression_threshold)`
  - `exit_target = threshold - compression_safety_margin` (default `compression_safety_margin=0`)
  - `while uncompressed_session_tokens > exit_target and compression_ops < MAX_COMPRESSION_ITERATIONS:`
  - `  turn = nextOldestEligibleTurn(skip_non_compressible=true)`
  - `  if turn == null and emergency_window_compression_allowed(): turn = nextOldestWithinWindowTurnEmergency()`
  - `  if turn == null: break`
  - `  step = compress_next_turn_until_budget(session, threshold, single_step=true, turn_override=turn)`
  - `  compression_ops += 1`
  - `  if step.tokens_reduced_postcap < min_token_delta: mark_non_compressible(turn); continue`
  - `if compression_ops >= MAX_COMPRESSION_ITERATIONS: deterministic_retention_fallback()`
- Compression observability: emit `compression_attempts`, `tokens_reduced`, and `non_compressible_turns` metrics for every session compression cycle.
- `min_compression_threshold` default: `2,000` tokens (to avoid premature compression on small sessions).
- Definitions:
- `SHORT_TERM_WINDOW_TURNS` (allocation policy): count of most-recent turns kept uncompressed by default (`12`).
- `RETENTION_TURNS` (deterministic fallback retention): number of turns to retain after termination fallback; defaults to `SHORT_TERM_WINDOW_TURNS` unless explicitly overridden.
- `uncompressed_session_tokens` (observed usage): tokens from turns still stored uncompressed (rolling window + any older turns not yet compressed). Excludes summary memory tokens and excludes compressed summaries.
- `compressed_turns` (storage state): older turns stored as compressed summaries (for example in a session summary field or a compressed-turns table). Raw pre-compression tokens do not count toward `uncompressed_session_tokens`.
- `estimated_active_context_usage` (observed usage estimate): tokens expected to be injected into the model at runtime = `system_tools_used + estimated_summary_tokens + uncompressed_turns_used + retrieved_chunks_used + output_buffer_used`.
- `system_tools_reserved` (allocation): token allocation reserved for system prompt + tool schemas.
- `retrieval_budget` (allocation): max token allocation reserved for retrieved chunks.
- `output_budget` (allocation): max token allocation reserved for the model response buffer.
- `retrieved_chunks_used` / `output_buffer_used` (observed usage): runtime token usage consumed by retrieval chunks and output buffer in the current request.
- `estimated_summary_tokens` (allocation/overhead): token reservation for summary memory injected with the rolling context.
- Compressed-turn retention: retain compressed turns for 30 days from last activity (same as short-term memory). Compressed content only counts toward budgets if its summaries are included in the active context.
- `model_token_budget` definition (used in the uncompressed-session budget formula above):
  - `model_token_budget = min(model_max_context_window, configured_session_token_budget)`.
  - Default `configured_session_token_budget`: `5,000` tokens (the end-to-end soft budget in this plan) unless overridden by deployment config.
  - Examples with default config:
    - 8k model window -> `model_token_budget = min(8,000, 5,000) = 5,000`.
    - 32k model window -> `model_token_budget = min(32,000, 5,000) = 5,000`.
    - 128k model window -> `model_token_budget = min(128,000, 5,000) = 5,000`.
  - If a configured session limit is lower than the model max (for example `4,000`), use the smaller value via `min(...)`.
- Compression-linked hygiene: each compression cycle triggers audit tagging and periodic deletion/anonymization checks for expired memory rows.

3. Retrieval pipeline (backend)
- Hybrid retrieval: metadata filter (college/semester/branch/subject) + vector + keyword.
- Priority order:
  1) pinned resource (AI Studio scope)
  2) user-uploaded attachments for current turn
  3) profile-constrained campus resources
  4) fallback campus resources by topic
  5) web search fallback when confidence policy is not met
- Search fallback policy and confidence definition (evaluate in this order):
  - `top_chunk_score` = top-1 reranked relevance score. This is the `retrieval_score` used below.
  - `llm_confidence_score`: calibrated model confidence from answer-validation pass (higher = more confident).
  - Step 1 (no-result check): if `top_chunk_score < 0.35` or eligible chunks = `0`, trigger immediate web fallback.
  - Step 2 (quality check): compute `combined_confidence = (0.7 * retrieval_score) + (0.3 * llm_confidence_score)`.
  - Step 3 (threshold): if `combined_confidence < 0.70`, treat as low-quality and trigger web fallback + answer regeneration.
  - Web fetch behavior: fetch 3 sources by default (max 5), re-rank, and retain only policy-compliant domains.
- LLM answer validation gate:
  - Validate citation coverage, confidence, and policy checks before final response.
  - If validation fails threshold, invoke web fallback and re-answer with merged local+web context.
- Resource and query safety:
  - Enforce per-user/per-course authorization checks before retrieval.
  - Apply metadata-based authorization filters in every query path.
  - Sanitize/escape user-supplied search/tool parameters before execution.

4. Structured outputs (backend + client)
- Never print raw URLs in response text.
- Return `sources[]` as structured metadata only.
- Return `actions[]` for UI actions (`start_quiz`, `download_report_pdf`).

5. Artifact generation
- Quiz: return normalized quiz JSON + action token; client opens full-page quiz engine.
- Report: generate file artifact (PDF/doc) and return download payload, not plain text dump.
- Validate artifact payload schema before publishing.
- Serve artifacts through signed short-lived URLs (not raw persistent links in assistant text).

6. Observability and guardrails
- Add per-stage timings: intent, retrieve, rerank, generate, post-process.
- Track no-local-hit rate, web-fallback rate, citation coverage, quiz parse success.
- Add security telemetry to stage metrics: prompt-injection attempts, schema-validation failures, auth denials, rate-limit hits, anomaly flags.
- Add automated eval set for 200-300 representative student queries, plus continuous evaluation using sampled real queries with periodic dataset refresh.
- Coverage goals for evals: edge cases, multi-turn continuity, ambiguous intents, retrieval failure paths, and recovery behavior.

7. Security & Input Validation (cross-cutting)
- Intent Router: strict request/response schemas, allowlisted actions, allowlisted parameter shapes, and blocked tokens/patterns for known injection vectors.
- Memory model: sensitive-field redaction before persistence, encrypted semantic stores, and ACL checks on every memory read/write operation.
- Retrieval/resource access: enforce row-level/metadata authorization checks, sanitize all user query strings, and block or escape user content passed into tool calls.
- Abuse controls: global rate limiting, per-user quotas, and anomaly detection on request spikes, prompt patterns, and repeated auth failures.
- Artifact endpoints: schema validation before storage and signed URL delivery with TTL + audience constraints.
- Security observability: expose security metrics on the same dashboard as latency/quality for deploy gates.

## Execution phases
1. Phase 1 (done in client)
- Pass structured history in RAG requests.
- Preserve metadata when stream falls back to non-stream.
- Hide attachment marker text from user messages.
- Improve first-message visibility with resilient scroll-to-bottom.
- Rollout stage: 100% client rollout completed.
- Acceptance gates: no regressions in chat render, metadata chips, and session persistence.

2. Phase 2 (next backend sprint)
- Add intent router + tool invocation contracts.
- Implement retrieval priority stack with profile-aware filtering.
- Add source/action schema normalization.
- Rollout stage: canary -> 25% staged -> 50% staged.
- Acceptance gates: schema pass rate >=99%, rollback-safe dual-path routing enabled, and no P95 latency regression >15%.

3. Phase 3 (quality and scale)
- Session memory summarization and semantic memory store.
- Eval harness + regression checks per deploy.
- Cost and latency optimization (chunk budget, reranker thresholding, cache).
- Rollout stage: 50% -> 100% after Phase 3 gates pass for 7 consecutive days.
- Acceptance gates: reliability, cost, and UX metrics all inside SLO.

### Phase 3 budgeted optimization constraints
- Cost budget:
  - Target average cost per query: `<= $0.05`.
  - Hard cap per query: `<= $0.10`.
  - Monthly production cap: `<= $5,000` with alerting at 70%, 85%, and 95%.
- Token budgets:
  - Router/classification: `<= 600` input tokens.
  - Retrieval context budget: `<= 2,400` chunk tokens total (chunk tokens only; excludes prompt/system/citation overhead).
  - Chunk budget: max 6 chunks, 350 tokens/chunk soft cap, 400 hard cap (`2,100` soft, `2,400` hard).
  - Response budget: standard answers `<= 900` output tokens, artifact intents `<= 1,400`.
  - End-to-end soft budget per normal request: `<= 5,000` total tokens.
- Cost-vs-quality decision rules (linked to chunk budget, reranker thresholding, cache):
  - If P95 latency breaches for 2 hours and accuracy drop is <=2 percentage points, reduce `top_k` and tighten reranker threshold.
  - If monthly spend trend exceeds cap forecast and quality drop remains <=2 percentage points, route low-risk intents to cheaper model tier.
  - If confidence remains low after optimization knobs, prioritize cache/web fallback over larger context expansion.

### Rollout and Testing Strategy
- Gradual rollout plan:
  - Phase 2 canary: 10% traffic for 48h, then 25% for 72h, then 50% for 7 days.
  - Phase 3 scale rollout: 50% for 7 days, then 100% when all gates are green.
  - Rollout is blocked if any acceptance gate fails during its observation window.
- A/B testing framework:
  - Compare baseline vs candidate for retrieval policy, memory compression, and fallback behavior.
  - Primary metrics: contextual accuracy, first-token latency, recovery success, CSAT.
  - Minimum sample: whichever requires more sessions - `2,000` sessions or the sample size needed to achieve 95% statistical confidence.
  - Success threshold: >=2 percentage point gain in primary metric with no reliability regression.
- Rollback criteria and alert ownership:
  - Rollback triggers: error rate >2%, P95 first-token latency regression >25%, CSAT drop >0.2 points, auth denial spike >30%.
  - Alert owner: AI Platform on-call engineer; product owner receives escalation if rollback lasts >2 hours.
- Monitoring and deployment gates:
  - Required dashboards: latency by scenario, error rate, fallback recovery, security events, cost burn.
  - Required pre-deploy smoke tests: router schema validation, retrieval auth checks, fallback execution, artifact URL TTL.
  - Post-deploy evaluation window: 24h for canary, 72h for staged, 7 days for full rollout gate sign-off.

## Immediate implementation queue (continuation)
1. Backend compression runtime (next 3-5 days)
- Implement `compress_next_turn_until_budget` with final `tokens_reduced_postcap` semantics, `used_cap` contract, and session-persistent `consecutive_no_progress_count`.
- Add `compression_safety_margin` config and strict loop exit `uncompressed_session_tokens > exit_target`.
- Ship metrics: `compression_attempts`, `tokens_reduced`, `non_compressible_turns`, `compression_incomplete`.

2. Compression scheduler + lock manager (next 3-5 days)
- Implement `session_id` lock + `pending_rerun` coalescing behavior with cycle-scoped merge windows.
- Add event-driven enqueue + periodic worker triggers + retry/backoff policy.
- Add deterministic retention fallback path with audit logging.

3. Retrieval confidence + OCR impact contract (next 5-7 days)
- Implement backend `combined_confidence = (0.7 * retrieval_score) + (0.3 * llm_confidence_score)` to match fallback gating terminology in this plan.
- Implement `ocrFailureAffectsRetrieval(...)` predicate and emit it in retrieval response metadata.
- Connect UI warning state to `ocrFailureAffectsRetrieval` and retry/reupload action affordances.

4. OCR retry/reupload APIs (next 5-7 days)
- External HTTP endpoints (controller routes):
  - `POST /api/notebooks/sources/upload`
  - `POST /api/notebooks/sources/:source_id/request-reupload`
  - `POST /api/notebooks/sources/:source_id/retry-now`
  - `POST /api/notebooks/sources/:source_id/cancel-retry`
- Internal handlers (worker functions):
  - `RequestReuploadHandler`
  - `RetryNowHandler`
  - `CancelRetryHandler`
  - `NotifyAdminHandler`
  - `CreateSupportTicketHandler`
- Add integration tests for retry exhaustion, manual retry cooldown, and permanent-failed transitions.

5. Compliance and deletion observability (next sprint)
- Add deletion job IDs, SLA timestamps, audit fields, and exception-reason tracking.
- Implement expedited soft-mark (`24-72h`) path with override controls and bounded batch processing.
- Add compliance dashboards for deletion SLA completion and exception counters.

## Success metrics
- `>=90%` contextual follow-up accuracy in multi-turn chat benchmark.
- Latency SLOs (first-token):
  - Cached/local answers: median `<=2.5s`, P95 `<=5.0s`, P99 `<=7.5s`.
  - Non-cached local retrieval: median `<=3.5s`, P95 `<=7.0s`, P99 `<=10.5s`.
  - Web fallback: median `<=5.0s`, P95 `<=10.0s`, P99 `<=15.0s`.
- Reliability:
  - End-to-end request/response error rate `<=1.0%`.
  - Graceful-degradation sessions (cached/static fallback due to upstream issues) `<=5.0%`.
  - Retrieval fallback recovery success (when primary retrieval fails) `>=90%`.
- UX and engagement:
  - CSAT `>=4.4/5.0` for AI Chat interactions.
  - 7-day returning AI chat user rate `>=35%`.
- `>=95%` quiz JSON parse success for quiz intents.
- `0%` source URL leakage in assistant text responses.
