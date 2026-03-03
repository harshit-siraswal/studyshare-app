# StudyShare AI (NotebookLM-Style) Product Requirements Document (PRD)

Last updated: March 3, 2026  
Owner: Product + AI Platform

## 1. Product Vision

Build a study-native AI assistant that behaves like a personal notebook tutor:
- Understands conversation context across turns.
- Grounds answers in user/campus study materials first.
- Automatically uses OCR when text extraction is weak.
- Generates reliable quizzes that students can attempt, submit, and review.
- Falls back to web only when local evidence is insufficient and user intent allows it.

This product includes:
- `AI Chat` (cross-resource conversational assistant).
- `AI Studio` (resource-scoped workflows: summary, quiz, flashcards, report exports).

## 2. Problem Statement

Current user pain:
1. Answers feel like literal keyword matching instead of conceptual understanding.
2. Typo/synonym queries fail too often (example: `NunPy` vs `NumPy`).
3. Quiz generation fails or returns low-quality/invalid output in some flows.
4. OCR fallback is not consistently applied for all query paths.
5. Users cannot trust the model when evidence confidence is low.

## 3. Goals and Non-Goals

### 3.1 Goals
1. Increase contextual answer quality for multi-turn study conversations.
2. Make quiz generation deterministic, schema-safe, and attemptable in-app.
3. Build robust source-grounding with transparent citations and confidence.
4. Reduce “no relevant info” false negatives with better semantic retrieval and OCR.
5. Maintain low-latency UX with clear fallback behavior.

### 3.2 Non-Goals
1. Replace core app features unrelated to AI.
2. Build an unrestricted general-purpose chatbot without grounding constraints.
3. Depend on a single model vendor without abstraction.

## 4. Personas and Jobs-To-Be-Done

1. Student (primary)
- JTBD: “Help me understand my notes and prepare for exams quickly.”
- Needs: precise answers, quizzes, concise summaries, revision flow, trustable citations.

2. Teacher / Department Account
- JTBD: “Create practice material from uploaded resources and monitor quality.”
- Needs: predictable quiz/report generation, quality controls, source traceability.

3. Admin / Platform Operator
- JTBD: “Ensure reliability, safety, and cost efficiency.”
- Needs: observability, rollout guardrails, abuse controls, retriable background jobs.

## 5. Product Principles

1. Grounded-first: local study materials are first-class evidence.
2. Context-aware: follow-up questions should not require users to restate topic.
3. Deterministic tool outputs: quiz/report generation must pass schema gates.
4. Honest uncertainty: explicitly state low confidence and trigger fallback path.
5. Learnable UX: users can see where answer came from and what to do next.

## 6. Functional Scope

## 6.1 Notebook Workspace Layer (new)

1. Notebook entity
- A notebook is a user-scoped collection of sources and chat threads.

2. Source ingestion
- Limits and formats:
  - `maxFileSizeMB`: default `100` MB per file (configurable).
  - `maxSourcesPerNotebook`: default `200` sources per notebook (configurable).
  - Supported extensions: `.pdf`, `.pptx`, `.ppt`, `.docx`, `.doc`, `.txt`, `.md`, `.png`, `.jpg`, `.jpeg`, `.tiff`, `.bmp`, `.gif`, including scanned/image-only PDF variants.
- Auto-detect scanned PDFs and trigger OCR.
- Error handling and UI states:
  - `unsupportedFormat` -> error code `INGESTION_UNSUPPORTED_FORMAT`, message `Unsupported file format.`
  - `fileTooLarge` -> error code `INGESTION_FILE_TOO_LARGE`, message `File exceeds max size limit.`
  - `ingestionFailed` -> error code `INGESTION_PIPELINE_FAILED`, message `We could not process this file.`
  - Canonical UI states: `uploading`, `ingesting`, `ocr_processing`, `indexed`, `unsupportedFormat`, `fileTooLarge`, `ingestionFailed`, `unavailable_for_search`.
  - `unavailable_for_search` is a distinct terminal/readonly state for OCR-unusable sources and replaces `ingestionFailed` when OCR is the terminal failure reason.
  - UI must show state transitions: `uploading -> ingesting -> ocr_processing (if needed) -> indexed | ingestionFailed | unavailable_for_search`.
  - Error-to-terminal mapping (authoritative):
    - `OCR_error_*` (for example unreadable scans, OCR engine failures, OCR-unusable documents) -> terminal state `unavailable_for_search`.
    - `ingestion_error_*` (for example parse/index failures, non-OCR pipeline/storage failures) -> terminal state `ingestionFailed`.
    - `INGESTION_UNSUPPORTED_FORMAT` and `INGESTION_FILE_TOO_LARGE` remain explicit terminal states `unsupportedFormat` / `fileTooLarge`.
- OCR fallback/retry policy:
  - Retry semantics: `max_retry_count=3` means total OCR attempts including the initial attempt (automatic retries after initial attempt = 2).
  - If scanned detection is true and first OCR pass fails quality checks, queue automatic retries with backoff (`1m`, `5m`) until `retry_count >= max_retry_count`.
  - OCR statuses (`pending`, `running`, `succeeded`, `failed`, `retry_scheduled`, `permanent_failed`):
    - `pending`, `running`, `failed`, and `retry_scheduled` are sub-states of canonical `ocr_processing`.
    - `permanent_failed` is terminal and maps directly to canonical `unavailable_for_search` (not a sub-state of `ocr_processing`).
  - OCR status-to-UI mapping:
    - `pending` -> canonical badge `ocr_processing` + secondary label `Pending OCR`.
    - `running` -> canonical badge `ocr_processing` + secondary label `Running OCR`.
    - `retry_scheduled` -> canonical badge `ocr_processing` + secondary label `Retry scheduled` + retry icon + actionable CTA:
      - primary action: `Retry now` -> call immediate retry API (`POST /api/notebooks/sources/:source_id/retry-now` or equivalent `triggerImmediateRetry(taskId)`).
      - secondary action: `Cancel retry` -> cancel scheduled retry (`POST /api/notebooks/sources/:source_id/cancel-retry` or equivalent `cancelScheduledRetry(taskId)`).
      - both actions must update status UI and show success/error feedback toast/banner.
    - `succeeded` -> transition to canonical state `indexed`.
    - `failed` -> remain in `ocr_processing` until retry policy resolves, then transition to `unavailable_for_search` on terminal OCR failure.
    - `permanent_failed` -> canonical `unavailable_for_search`, render admin-intervention panel, block further automatic retries, and emit `permanent_failed` backend event.
- Preserve metadata: title, subject, semester, branch, source type, upload date.

3. Source controls
- Pin/unpin sources per session.
- Enable scope modes: `pinned only`, `course scoped`, `all my sources`.

Acceptance:
- Upload success rate >=99%.
- Ingestion/OCR status visible in UI.

## 6.2 AI Chat (cross-resource)

1. Context understanding
- Resolve follow-up references (“explain this more”, “what about that formula”).
- Apply query rewrite + typo correction + synonym expansion before retrieval.

2. Retrieval modes
- `Local-only` mode (strictly notebook/campus materials).
- `Local + web fallback` mode (when confidence below threshold and user allows).

3. Answer format
- Concise answer.
- Citation block as structured chips (not raw URLs in body text).
- Confidence indicator and next-step actions.
- Confidence thresholds:
  - High: `score >= 0.80`
  - Medium: `0.50 <= score < 0.80`
  - Low: `score < 0.50`
- Low confidence behavior: trigger `Local + web fallback` only when user has enabled/allowed web fallback.
- Medium confidence behavior: show a short caveat and optional web fallback action.
- `score` composition formula (authoritative): `score = (0.6 * retrievalScore) + (0.4 * answerScore)`.
- Implementation note: backend must emit `retrievalScore`, `answerScore`, and computed `score` using the formula above; frontend should consume emitted `score` for thresholding (do not recompute with a divergent formula).
- Test requirement: add a backend unit test for the scorer (for example, `score_formula_v1`) that asserts the exact `retrievalScore`/`answerScore` -> `score` mapping.

Acceptance:
- Multi-turn contextual benchmark >=90%.
- Source chips shown for >=95% grounded answers.

## 6.3 AI Studio (resource-scoped)

1. Generate summary
- Structured summary with section headings + key takeaways.

2. Generate flashcards
- JSON-safe flashcards with deterministic difficulty tags (`Easy|Medium|Hard`).
- Difficulty mapping rules:
  - `Easy`: factual recall, single-step answer, low prerequisite knowledge, high confidence.
  - `Medium`: conceptual explanation with 1-2 reasoning steps or moderate prerequisites.
  - `Hard`: multi-step/synthesis/problem-solving with high abstraction or significant prerequisites.
- Deterministic heuristics for tagging:
  - question verb patterns (`define/list/name` -> Easy, `explain/compare` -> Medium, `derive/analyze/design/prove` -> Hard),
  - prerequisite concept count,
  - expected answer length,
  - confidence/similarity thresholds.
- Flashcard JSON schema must include:
  - `difficulty: "Easy" | "Medium" | "Hard"`.
- Example:
  - Easy: `{ "question": "Define stack.", "answer": "...", "difficulty": "Easy" }`
  - Medium: `{ "question": "Explain stack overflow with example.", "answer": "...", "difficulty": "Medium" }`
  - Hard: `{ "question": "Design an expression parser using stacks.", "answer": "...", "difficulty": "Hard" }`

3. Generate quiz / question paper
- Strict schema output.
- Minimum quality gate: no placeholders, enough unique questions, valid answers.

4. Export report artifact
- Save as PDF/doc and return short-lived download action.

Acceptance:
- Quiz parse success >=98%.
- Report artifact generation success >=97%.

## 6.4 Quiz Experience (must-fix)

1. Quiz session model
- Start quiz from generated paper.
- Track selected answer per question.
- Submit once.
- Session constraints (configurable):
  - Time limit: optional per-quiz TTL (`time_limit_seconds`), with visible countdown.
  - Ordering: `fixed` or `random` (with stored `ordering_seed` for deterministic replay).
  - Pause/resume: allowed when policy permits; persist session state and remaining time.
  - Navigation: `linear` or `free`; configure whether revisiting can change answers.
  - Timeout behavior: `auto_submit` (default) or `lockout_with_warning`.
- Rule interactions:
  - `Submit once` remains authoritative for final submission lock.
  - If timeout auto-submits, integrity checks still run on submitted payload.
  - If resume is enabled, integrity checks validate restored state before continuing.

2. Results
- Total score.
- Per-question review screen with:
  - marked answer,
  - correct answer,
  - short explanation,
  - source mapping.

3. Integrity checks
- Reject malformed quiz payloads before user sees them.
- Auto-repair pass for minor schema issues; regenerate if still invalid.

Acceptance:
- End-to-end “generate -> attempt -> submit -> review” success >=97%.

## 6.5 OCR and Extraction Reliability

1. Ingestion-time OCR
- For scanned/low-text PDFs.
- If OCR output is unreadable/low reliability, mark source as `unavailable_for_search` and queue re-processing with retry/backoff policy.

2. Query-time OCR retry
- If no relevant context and candidate files are scanned/low-quality text.
- If query-time OCR fails, fall back to filename/metadata-only search and show user message: `Results may be incomplete because OCR failed.` Provide actions: `Retry OCR` and `Request re-upload`.
- `Request re-upload` flow (explicit UX + backend):
  - UI label: `Request re-upload`.
  - Step 1: open file replacement dialog pre-filled with original source metadata.
  - Step 2: client uploads replacement file via `POST /api/notebooks/sources/upload` and receives `replacement_file_id`.
  - Step 3: client submits `replacement_file_id` via `requestReupload`.
  - Step 4 (optional): checkbox `Notify instructor/support`.
  - Step 5: if checked (or forced by policy), backend emits `notifyAdmin` and `createSupportTicket` internal events with original file metadata + OCR failure context.
  - Default behavior: plain UI re-upload prompt only; notifications/ticketing are opt-in unless deployment policy forces notification.
  - API contract (authoritative backend):
    - `POST /api/notebooks/sources/upload` -> request: multipart file upload + metadata; response: `{ replacement_file_id, checksum, size_bytes }`.
      - Error response schema (all failures): `{ error_code, message, details?, timestamp? }`.
      - `details` structured union (discriminated by `type`):
        - validation: `{ "type":"validation", "errors":[{"field":"...", "message":"...", "code":"..."}] }`
        - debug: `{ "type":"debug", "trace_id":"...", "internal_code":"...", "backtrace?":"..." }`
        - actionable: `{ "type":"actionable", "user_message":"...", "suggested_action":"..." }`
      - Status/error mapping for multipart upload + metadata validation:
        - `400` -> validation failure (`VALIDATION_FAILED`, `INVALID_METADATA`, `UNSUPPORTED_FILE_TYPE`) before upload acceptance.
        - `401/403` -> auth/authorization failure (`UNAUTHENTICATED`, `FORBIDDEN`).
        - `413` -> size limit exceeded (`INGESTION_FILE_TOO_LARGE`) during file-size guard.
        - `409` -> checksum conflict/mismatch (`CHECKSUM_MISMATCH`) when integrity validation fails.
        - `500` -> storage/backend write failure (`STORAGE_WRITE_FAILED`, `UPLOAD_BACKEND_ERROR`).
      - `details.type` mapping guidance:
        - `VALIDATION_FAILED` / `INVALID_METADATA` / `UNSUPPORTED_FILE_TYPE` -> `validation`
        - `UNAUTHENTICATED` / `FORBIDDEN` -> `actionable`
        - `INGESTION_FILE_TOO_LARGE` / `CHECKSUM_MISMATCH` -> `actionable`
        - `STORAGE_WRITE_FAILED` / `UPLOAD_BACKEND_ERROR` -> `debug`
    - `POST /api/notebooks/sources/:source_id/request-reupload` (`requestReupload`) -> request body: `{ replacement_file_id, reason, ocr_error_code }`; response: `{ request_id, status }`.
    - `POST /api/notebooks/sources/:source_id/retry-now` (`triggerImmediateRetry`)
      - Path params: `source_id` (required), `taskId` (optional query/body linkage for scheduler task).
      - Request body: optional `{ reason?: string, requested_by?: string }`.
      - Success response: `{ accepted: true, source_id, status: "ocr_processing", retry_status: "running", task_id, requested_at, started_at? }`.
      - Auth: Bearer token required; scope `ocr:retry` (or equivalent owner/admin permission).
      - Errors: `400 INVALID_REQUEST`, `401 UNAUTHENTICATED`, `403 FORBIDDEN`, `404 OCR_SOURCE_NOT_FOUND`, `409 OCR_RETRY_NOT_ALLOWED`, `500 OCR_RETRY_FAILED`.
      - Side effects and idempotency: triggers immediate retry execution; idempotent by `(source_id, active_retry_task)` within a short dedupe window.
      - UI guidance: on success set canonical status `ocr_processing` and secondary status `running`; on failure show returned `message` + actionable hint when present.
    - `POST /api/notebooks/sources/:source_id/cancel-retry` (`cancelScheduledRetry`)
      - Path params: `source_id` (required), `taskId` (optional to target specific scheduled job).
      - Request body: optional `{ reason?: string, requested_by?: string }`.
      - Success response: `{ accepted: true, source_id, status: "ocr_processing", retry_status: "failed" | "cancelled", task_id, cancelled_at }`.
      - Auth: Bearer token required; scope `ocr:cancel` (or equivalent owner/admin permission).
      - Errors: `400 INVALID_REQUEST`, `401 UNAUTHENTICATED`, `403 FORBIDDEN`, `404 OCR_SOURCE_NOT_FOUND`, `409 OCR_CANCEL_CONFLICT`, `500 OCR_CANCEL_FAILED`.
      - Side effects and idempotency: cancels pending scheduled retry; repeat calls for already-cancelled jobs are safe and return success with current terminal retry scheduling state.
      - UI guidance: on success clear `retry_scheduled` CTA and refresh source status from backend.
    - Internal endpoints/events (not client-callable):
      - `POST /internal/ocr/notify-admin` (`notifyAdmin`)
        - Required JSON body:
          - `source_id: string`, `notebook_id: string`, `user_id: string`, `ocr_error_code: string`, `reason: string`.
        - Optional JSON body:
          - `replacement_file_id?: string`, `trace_id?: string`, `metadata?: object`.
        - Success response: `{ accepted: true, notification_id: string }`.
        - Auth: internal service JWT with `role=worker` or `scope=internal:ocr:notify`.
        - Required headers: `Authorization`, `Content-Type: application/json`, `X-Request-Id`.
        - Error response schema: shared `{ error_code, message, details? }`.
        - Status -> canonical error mapping:
          - `400` -> `VALIDATION_ERROR`
          - `401` -> `AUTH_REQUIRED`
          - `403` -> `FORBIDDEN`
          - `404` -> `RESOURCE_NOT_FOUND` (`details.resource_type`: `OCR_SOURCE` | `NOTEBOOK` | `USER`)
          - `429` -> `OCR_RATE_LIMITED`
          - `500` -> `NOTIFICATION_FAILED`
        - Example request: `{ "source_id":"src_123","notebook_id":"nb_1","user_id":"u_9","ocr_error_code":"ocr_timeout","reason":"manual_reupload_requested" }`.
        - Example response: `{ "accepted": true, "notification_id": "notif_456" }`.
      - `POST /internal/ocr/create-support-ticket` (`createSupportTicket`)
        - Required JSON body:
          - `source_id: string`, `notebook_id: string`, `request_id: string`, `issue_type: string`, `summary: string`.
        - Optional JSON body:
          - `priority?: "low"|"medium"|"high"`, `ocr_error_code?: string`, `metadata?: object`, `trace_id?: string`.
        - Success response: `{ accepted: true, ticket_id: string }`.
        - Auth: internal service JWT with `role=worker` or `scope=internal:support:create`.
        - Required headers: `Authorization`, `Content-Type: application/json`, `X-Request-Id`.
        - Error response schema: shared `{ error_code, message, details? }`.
        - Status -> canonical error mapping:
          - `400` -> `VALIDATION_ERROR`
          - `401` -> `AUTH_REQUIRED`
          - `403` -> `FORBIDDEN`
          - `404` -> `RESOURCE_NOT_FOUND` (`details.resource_type`: `OCR_SOURCE` | `NOTEBOOK` | `USER`)
          - `429` -> `OCR_RATE_LIMITED`
          - `500` -> `TICKET_CREATION_FAILED`
        - Example request: `{ "source_id":"src_123","notebook_id":"nb_1","request_id":"req_77","issue_type":"ocr_failure_exhausted","summary":"OCR failed after retries" }`.
        - Example response: `{ "accepted": true, "ticket_id": "st_901" }`.
    - Auth: authenticated notebook user for upload/reupload APIs; backend enforces ownership/role checks.
    - Errors (minimum): `OCR_SOURCE_NOT_FOUND`, `OCR_REUPLOAD_FORBIDDEN`, `OCR_POLICY_BLOCKED`, `OCR_RATE_LIMITED`, `VALIDATION_FAILED`.
    - Sync/async behavior: upload and `requestReupload` are synchronous request acceptance; notification/ticket creation is asynchronous via backend-owned workers.
  - Deployment policy definition (server-authoritative, three-state):
    - `tenantConfig.forceNotifications == true` -> force notifications.
    - `tenantConfig.forceNotifications == false` -> do not force notifications (and do not fall back to env flag).
    - `tenantConfig.forceNotifications == null|undefined` -> fallback to `FEATURE_FLAG_FORCE_NOTIFY`.
  - Client may only hint UI state; server enforces final behavior.

3. OCR observability
- Record `ocr_succeeded` (bool), `ocr_reliability_score` (0-1 or 0-100), and `ocr_error_code` telemetry fields for ingestion/query flows.
- OCR unresolved-error definition:
  - `retry_count` counts total OCR attempts (initial attempt starts at `1`).
  - unresolved = `retryable_error_code == true` AND `retry_count < max_retry_count` (default `max_retry_count=3` total attempts).
  - persist `retry_count` per source and use exponential backoff between retries.
  - non-retryable/permanent errors immediately move source to `unavailable_for_search`.
- OCR error mapping (minimum):
  - `ocr_timeout` -> `{ retryable: true, reason: provider timeout }`
  - `ocr_rate_limited` -> `{ retryable: true, reason: provider quota/throttle }`
  - `ocr_provider_unavailable` -> `{ retryable: true, reason: transient provider outage }`
  - `corrupted_file` -> `{ retryable: false, reason: source cannot be parsed }`
  - `unsupported_format` -> `{ retryable: false, reason: unsupported binary/encoding }`
  - `checksum_mismatch` -> `{ retryable: false, reason: integrity mismatch }`

Acceptance:
- OCR fallback success on scanned benchmark >=85%.
- Mark-as-unavailable criteria: source fails OCR reliability threshold after max retries.
- Retry criteria: retry only for scanned/low-text sources with unresolved OCR errors (`retryable error_code` + `retry_count < max_retry_count`).
- Retry exhaustion handling:
  - Exhausted state is reached when `retry_count >= max_retry_count`.
  - User-facing message must be explicit: `OCR failed after {retry_count} attempts. Results may be incomplete.`
  - In exhausted state, UI keeps `Request re-upload` enabled and shows `Retry OCR` as a manual action.
  - Manual retry controls:
    - Track `manual_retry_count`, `max_manual_retries` (default `2`), and `manual_retry_last_at`.
    - First manual retry is allowed immediately (`manual_retry_last_at == null` means no cooldown).
    - Enforce cooldown between manual retries (default `15m`): apply cooldown only when `manual_retry_last_at != null`; disable retry action when `now - manual_retry_last_at < cooldown` and show remaining cooldown countdown (`Xm Ys`) via tooltip/secondary label.
    - Manual retry increments `manual_retry_count` and does not reset automatic `retry_count`.
    - When `manual_retry_count >= max_manual_retries`, transition source to `permanent_failed` (terminal OCR status mapped to canonical `unavailable_for_search`) and render an admin-intervention panel:
      - message: `Automatic and manual OCR retries are exhausted.`
      - primary action: `Request re-upload` (enabled),
      - support/escalation actions: `Create support ticket` and support contact link,
      - optional action: `Request admin review`.
- User-facing retrieval-impact criteria:
  - Define `ocrFailureAffectsRetrieval(queryContext, retrievalCandidates, topKResults)` parameter contract:
    - `queryContext`:
      - `{ query: string, userPreferences?: { language?: string, filters?: string[] }, scope?: { collections?: string[], dateRange?: { from?: string, to?: string } }, retrievalMinResults?: number, retrieved_result_count?: number }`
    - `retrievalCandidates`:
      - `Array<{ id: string, sourceId: string, metadata?: Record<string, any>, ocrStatus: "OK" | "unavailable_for_search" | "UNKNOWN" }>`
    - `topKResults`:
      - `Array<{ resultId: string, sourceId: string, score?: number, rank?: number }>`
    - `retrieved_result_count`:
      - use `queryContext.retrieved_result_count` when provided; otherwise compute as `len(topKResults)`.
    - `K` behavior:
      - backend top-K is fixed by retrieval policy; `retrievalMinResults` is an independent warning threshold.
  - Canonical status reconciliation:
    - retrieval-impact checks operate on canonical `unavailable_for_search` status (not raw `OCR_FAILED`).
    - if backend adapters emit raw OCR statuses, map through `mapSourceStatusToCanonical(status)` before evaluation.
  - Predicate logic:
    - `true` when at least one `unavailable_for_search` source (matched by `sourceId`) appears in final top-K, OR
    - `true` when `retrieved_result_count < retrievalMinResults` and at least one `unavailable_for_search` candidate is present.
  - Config:
    - `retrievalMinResults` (default `3`, configurable),
    - `includeUnavailableForSearchInCandidates` (default `true`, configurable; legacy alias `includeOcrFailedInCandidates`).
  - When `ocrFailureAffectsRetrieval=true`, show incomplete-results warning + retry/re-upload actions.

## 6.6 Memory and Personalization

1. Short-term memory
- Rolling window + compressed summary memory (as defined in modernization plan).

2. Long-term memory (opt-in)
- Session semantic memory across visits.

3. Controls
- Per-chat memory toggle.
- Delete history request support.

Acceptance:
- Memory retrieval hit rate improves follow-up accuracy by >=10 points on benchmark.

## 6.7 Explainability and Trust

1. Citation UX
- Show source title + page range/timestamp.
- Tap to open source at mapped location when available.

2. Confidence UX
- Show “High/Medium/Low confidence”.
- For low confidence: suggest refine/pin/upload/web actions.

Acceptance:
- Citation precision >=90% on manual audit sample.

## 6.8 Safety and Governance

1. Prompt/tool safety
- Strict action allowlist and JSON schema validation.

2. Access safety
- Enforce college/user/resource scope at retrieval time.

3. Abuse controls
- Rate limit, anomaly detection, and audit logs.

## 7. Quality Metrics and SLOs

1. Answer quality
- Contextual follow-up accuracy: >=90%.
- Grounded answer rate (with valid citations): >=92%.

2. Quiz quality
- Valid schema rate: >=98%.
- Placeholder-free papers: 100%.

3. Reliability
- AI request error rate: <=1%.
- Fallback recovery success: >=90%.

4. Latency (first token)
- Cached/local: P95 <=5s.
- Non-cached local: P95 <=7s.
- Web fallback: P95 <=10s.

5. User outcomes
- AI CSAT >=4.4/5.
- 7-day returning AI user rate >=35%.

## 8. Prioritized Roadmap

## Phase A (Critical fixes, 2-3 weeks)
1. Quiz reliability hardening + review UX completion.
2. Follow-up query rewrite + typo/synonym expansion.
3. Query-time OCR retry for weak/no-context outcomes.
4. Confidence + citation normalization in response contract.

## Phase B (Notebook UX, 3-5 weeks)
1. Notebook entity and source management.
2. Scope modes (pinned/course/global).
3. Session memory + summary compression in backend.

## Phase C (Scale and quality, ongoing)
1. Eval harness + regression gate in CI/CD.
2. Reranker improvements and cost/latency tuning.
3. Advanced analytics and adaptive routing.

## 9. Risks and Mitigations

1. OCR cost/latency spikes
- Mitigation: adaptive OCR policy + caching + selective retry.

2. Overly strict grounding causes false “no info”
- Mitigation: semantic rewrite + rerank + controlled web fallback.

3. Model output drift for quiz JSON
- Mitigation: strict validator + repair/regenerate loop.

4. Vendor dependency
- Mitigation: provider abstraction layer and A/B routing support.

## 10. Release Gate Checklist

1. Context benchmark meets target.
2. Quiz E2E pass rate meets target.
3. OCR fallback benchmark passes.
4. Citation and confidence telemetry live.
5. Rollback and on-call playbooks ready.
