# AI Chat Modernization Plan

Last updated: February 28, 2026

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
- Compression step every 8-12 turns (based on current context size/token budget) to keep token cost bounded.
- Compression-linked hygiene: each compression cycle triggers audit tagging and periodic deletion/anonymization checks for expired memory rows.

3. Retrieval pipeline (backend)
- Hybrid retrieval: metadata filter (college/semester/branch/subject) + vector + keyword.
- Priority order:
  1) pinned resource (AI Studio scope)
  2) user-uploaded attachments for current turn
  3) profile-constrained campus resources
  4) fallback campus resources by topic
  5) web search fallback when confidence policy is not met
- Search fallback policy and confidence definition:
  - `retrieval_score`: max(top-1 reranked relevance, weighted average of top-3 chunk scores).
  - `llm_uncertainty_score`: calibrated model confidence from answer-validation pass.
  - `combined_confidence = (0.7 * retrieval_score) + (0.3 * llm_uncertainty_score)`.
  - Default threshold: `combined_confidence < 0.70` triggers web fallback.
  - No-result condition: top chunk score `<0.35` or `0` eligible chunks triggers immediate web fallback.
  - Low-quality condition: results exist but below threshold triggers web fallback and answer regeneration.
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
  - Retrieval context budget: `<= 2,400` tokens total.
  - Chunk budget: max 6 chunks, 400 tokens/chunk soft cap, 500 hard cap.
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
  - Minimum sample: 2,000 sessions or 95% statistical confidence (whichever is later).
  - Success threshold: >=2 percentage point gain in primary metric with no reliability regression.
- Rollback criteria and alert ownership:
  - Rollback triggers: error rate >2%, P95 first-token latency regression >25%, CSAT drop >0.2 points, auth denial spike >30%.
  - Alert owner: AI Platform on-call engineer; product owner receives escalation if rollback lasts >2 hours.
- Monitoring and deployment gates:
  - Required dashboards: latency by scenario, error rate, fallback recovery, security events, cost burn.
  - Required pre-deploy smoke tests: router schema validation, retrieval auth checks, fallback execution, artifact URL TTL.
  - Post-deploy evaluation window: 24h for canary, 72h for staged, 7 days for full rollout gate sign-off.

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
