# AI Studio Generation Research

Date: 2026-03-18  
Last Updated: 2026-03-26  
Scope: Why AI Studio quiz and flashcards are still failing, why the OCR selector is stale, and why summary quality is still weak even after the OCR fallback fix.

## Version History

- 2026-03-18: Initial investigation and findings.
- 2026-03-26: OCR-first implementation update, cache/versioning notes, and deployment safety guidance.

## Executive Summary

The AI Studio failure is not one single bug. It is a chain problem across extraction, generation, and caching.

The most important findings are:

1. AI Studio quiz and flashcards still use the legacy `aiPhase1` pipeline, not the newer `/generate` job flow.
2. Quiz and flashcards are much more brittle than summary because they require strict JSON arrays, but they are generated with a relatively high default randomness and tight output budgets.
3. The current OCR pipeline is still much weaker than the original intended design. It often accepts mediocre embedded PDF text instead of running stronger OCR.
4. Summary quality is poor because the pipeline flattens and compresses text aggressively before generation.
5. Cached bad outputs can survive even after OCR improvements, because `ai_outputs` caching is keyed only by `file_id + type`, not by OCR version, source text hash, or generation settings.
6. The Flutter OCR provider selector is stale and misleading. The backend already ignores it and forces Gemini.

## Current Request Flow

### Flutter

AI Studio calls:

- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\services\backend_api_service.dart:1678`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\services\backend_api_service.dart:1703`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\services\backend_api_service.dart:1728`

These hit:

- `/api/ai/summary`
- `/api/ai/quiz`
- `/api/ai/flashcards`

### Backend

Those routes still go through the legacy phase-1 controller:

- `D:\StudyspaceProjects\studyspace-backend\src\routes\ai.routes.ts:23`
- `D:\StudyspaceProjects\studyspace-backend\src\routes\ai.routes.ts:24`
- `D:\StudyspaceProjects\studyspace-backend\src\routes\ai.routes.ts:25`

The newer job-based flow exists, but AI Studio is not using it:

- `D:\StudyspaceProjects\studyspace-backend\src\routes\ai.routes.ts:27`

## Finding 1: Quiz and Flashcards Are Strict, Summary Is Tolerant

Summary is plain text. Quiz and flashcards must be valid JSON arrays.

Relevant code:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:274`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:285`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:301`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:354`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:404`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:421`

Why this matters:

- Summary can still render if the model gives rough text.
- Quiz and flashcards fail if the model returns malformed JSON, truncated JSON, or an unexpected structure.
- A single bad chunk can fail the whole request.

The Flutter side confirms this strictness:

- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:682`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:706`

If parsing returns an empty list, Flutter throws:

- `Could not create a valid quiz from the AI response.`
- `Could not create valid flashcards from the AI response.`

## Finding 2: Structured Generation Is Running Too Hot

The shared Gemini model defaults to `temperature: 0.7`:

- `D:\StudyspaceProjects\studyspace-backend\src\config\gemini.ts:15`
- `D:\StudyspaceProjects\studyspace-backend\src\config\gemini.ts:18`

But `generateJsonWithRetry()` does not override temperature. It only sets:

- `responseMimeType`
- `responseSchema`
- `maxOutputTokens`

Relevant code:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:282`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:288`

Summary generation is safer because it explicitly lowers temperature:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:361`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:385`

Impact:

- Summary is more stable.
- Quiz/flashcards are more likely to drift off schema or produce brittle output.

## Finding 3: The Quiz and Flashcard Prompts Are Tight for the Token Budget

Quiz prompt asks for exactly 10 MCQs with 4 options each:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:65`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:72`

Flashcards schema allows up to 25 cards:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:136`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:139`

But the output budgets are still fairly tight:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:42`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:43`

Impact:

- Dense chunks can push quiz/flashcards toward truncation or malformed arrays.
- Summary has more room to degrade gracefully because it is not constrained into JSON.

## Finding 4: OCR Quality Is Still Below the Intended Design

The current OCR implementation does not match the stronger page-aware design originally described.

In the current PDF OCR pipeline:

- `D:\StudyspaceProjects\studyspace-backend\src\ocr\ocrPipeline.ts:37`
- `D:\StudyspaceProjects\studyspace-backend\src\ocr\ocrPipeline.ts:47`
- `D:\StudyspaceProjects\studyspace-backend\src\ocr\ocrPipeline.ts:48`
- `D:\StudyspaceProjects\studyspace-backend\src\ocr\ocrPipeline.ts:49`

The whole document is accepted as `pdf-parse` text if the total embedded text is longer than 50 characters.

That means:

- a mixed PDF with a little embedded text can skip Gemini entirely
- scanned pages can remain badly extracted
- OCR cache can be populated with mediocre text instead of true OCR output

There is a second heuristic in the extraction layer:

- `D:\StudyspaceProjects\studyspace-backend\src\utils\pdfExtract.ts:95`
- `D:\StudyspaceProjects\studyspace-backend\src\utils\pdfExtract.ts:101`
- `D:\StudyspaceProjects\studyspace-backend\src\utils\pdfExtract.ts:277`

OCR only runs when:

- `enableOcr && current.isScanned`
- or `forceOcr === true`

And `isScanned` is just an average-char-per-page heuristic.

Impact:

- weak embedded text can pass as "good enough"
- summaries get poor source material
- quiz/flashcards become even more fragile

## Finding 5: The Fallback OCR Fix Helps, But It Does Not Solve Source Quality End-to-End

The fallback extraction bug was already fixed:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:492`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:494`
- `D:\StudyspaceProjects\studyspace-backend\src\utils\pdfExtract.ts:417`

This fix ensures scanned PDFs can still try OCR even when `ocr_file_id` or `file_sha256` is missing.

That was necessary, but it is not sufficient because:

1. cached OCR text can still be low quality
2. `pdf-parse` still short-circuits Gemini too early for some files
3. the generation layer still compresses and degrades text heavily

## Finding 6: Summary Quality Is Hurt by Lossy Preprocessing

Before generation, the pipeline cleans and flattens text:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:150`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:170`

Then it chunks by word count:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:193`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:205`

Then summary is generated as:

1. summary per chunk
2. summary of the merged summaries

Relevant code:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:354`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:380`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:381`

Impact:

- line structure is lost
- section boundaries are lost
- tables/formulas can be degraded
- the second summarization pass compounds the information loss

This explains why summary can "work" but still feel shallow or wrong.

## Finding 7: Cache Is Making Old Bad Outputs Sticky

The generation cache is keyed only by:

- `file_id`
- `type`

Relevant code:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:534`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:539`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:543`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:597`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:607`

The cache does not include:

- OCR version
- OCR provider
- source text hash
- prompt version
- generation settings

Impact:

- bad summary/quiz/flashcards created earlier can keep coming back
- OCR improvements do not automatically invalidate stale AI outputs
- users can keep seeing poor summary text or broken quiz/flashcards even after backend fixes

This is one of the biggest reasons the feature can still feel "broken" after OCR work.

## Finding 8: `resources.extracted_text` Exists But AI Studio Does Not Use It

There is already an extraction service that stores extracted text into the DB:

- `D:\StudyspaceProjects\studyspace-backend\src\services\extraction.service.ts:19`
- `D:\StudyspaceProjects\studyspace-backend\src\services\extraction.service.ts:51`
- `D:\StudyspaceProjects\studyspace-backend\src\services\extraction.service.ts:63`

But AI Studio generation fetches only:

- `id`
- `title`
- `file_url`
- `video_url`
- `type`
- `ocr_file_id`
- `file_sha256`

Relevant code:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:549`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:551`

Impact:

- even if a resource already has pre-extracted text in the DB, AI Studio ignores it
- generation keeps doing its own weaker extraction path

## Finding 9: The OCR Provider Selector in Flutter Is Dead UI

Flutter still exposes OCR settings and a provider segmented control:

- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:1010`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:1136`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:1149`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:1152`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:1157`

But the backend forces Gemini whenever OCR is enabled:

- `D:\StudyspaceProjects\studyspace-backend\src\controllers\aiPhase1.controller.ts:57`

So:

- `Google` / `Sarvam` options are misleading
- they do not control real backend behavior
- this should be removed or replaced with a single Gemini status UI

## Ranked Root Causes

### Primary

1. Strict JSON generation for quiz/flashcards with brittle parsing
2. Stale `ai_outputs` cache not invalidated after extraction changes
3. Weak OCR acceptance rules that preserve mediocre embedded text

### Secondary

4. Summary-of-summaries design and `cleanText()` flattening
5. AI Studio still using the legacy phase-1 endpoints instead of the newer generation pipeline
6. Dead OCR provider selector in Flutter

## Recommended Fix Order

1. Make AI Studio ignore stale `ai_outputs` when source extraction has materially changed.
   - safest approach: version the cache key or add an extraction/source hash
2. Lower structured-generation randomness for quiz/flashcards.
   - override `temperature` close to `0.1` or `0.2`
3. Validate and repair cached quiz/flashcards before returning them.
   - do not return malformed cached data blindly
4. Improve OCR acceptance logic.
   - do not treat `pdf-parse > 50 chars` as automatically good enough for the whole PDF
5. Prefer stronger extracted text sources in AI Studio.
   - use `resources.extracted_text` when present and high quality
6. Remove the fake provider selector from Flutter.
   - replace it with Gemini-only OCR status and maybe a simple OCR toggle
7. Move AI Studio generation off the legacy phase-1 endpoints, or align that path with the newer generation pipeline.

## Practical Conclusion

The reason quiz and flashcards are still failing is not just "OCR is bad." The deeper problem is:

- source text is still inconsistent
- structured generation is brittle
- bad cache survives fixes

That combination explains the current user experience:

- summary sometimes appears, but weakly
- quiz and flashcards fail more often
- the OCR selector looks configurable, but is not actually real

## Emulator Runtime Check

I also launched the Android emulator and checked the app at runtime.

### Environment observed

- Device: `emulator-5554`
- Foreground app:
  - `me.studyshare.android/.MainActivity`
- Verified from:
  - `dumpsys activity activities`

### What runtime evidence showed

1. The app is not crashing on launch.
   - The resumed activity remains `me.studyshare.android/.MainActivity`.
   - No Flutter crash trace or Dart exception appeared in the current log buffer.

2. The release-build logcat is mostly quiet for AI Studio.
   - Useful Flutter-side errors like `Could not create valid flashcards` are not currently being emitted into logcat in a reliable way from this release session.
   - This reinforces that the main issue is not a client crash, but the quality and shape of the data coming back from the backend pipeline.

3. Some visible resource cards in the home feed are not valid AI Studio candidates at all.
   - Tapping at least one visible card path produced the in-app snackbar:
     - `No file available`
   - That means some surfaced resources have no usable `file_url`, so they can never power PDF extraction or AI Studio generation.
   - This is not the main AI Studio bug, but it does create misleading user flows when resources appear tappable but have no source file behind them.

4. Navigation itself is working.
   - I was able to navigate from the main feed to the syllabus department screen on the emulator.
   - So the current AI Studio problem still points much more strongly to the generation/extraction pipeline than to a general navigation or screen-rendering failure.

### Runtime conclusion

The emulator pass did not reveal a separate client-side crash or rendering bug that explains quiz/flashcard failure. The runtime evidence supports the static diagnosis:

- backend extraction quality is still inconsistent
- quiz/flashcard generation is too brittle
- stale cached outputs can keep bad results alive

So the next fix should stay focused on backend generation quality and cache invalidation, not on Flutter crash handling.

## Live Backend + Current Emulator Failure Capture

After installing the current debug build on the emulator and reproducing the failure again, I checked both:

- Android logcat for `me.studyshare.android`
- live PM2 logs on the production backend

This exposed the concrete production failure path.

### Current Flutter-side behavior

The current debug build still does not log the AI Studio failure payload itself. The main app-side exception visible in logcat is unrelated:

- `HiveError: You need to initialize Hive or provide a path to store the box.`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\services\download_service.dart:61`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\main.dart:439`

That is a real bug, but it is not what causes AI Studio generation to fail.

The AI Studio UI simply catches the thrown backend error and shows the generic failure state:

- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:643`
- `D:\StudyspaceProjects\mystudyspace-app\flutter_application_1\lib\widgets\ai_study_tools_sheet.dart:723`

So the real AI Studio error has to be read from the backend side.

### New Finding 10: Inline OCR Is Failing in Production Because the OCR Model Name Is Undefined

Production backend logs repeatedly show:

```text
[AI Context] Inline OCR failed: Gemini API error 404:
"models/undefined is not found for API version v1beta"
```

This is the most important new production finding.

Root cause:

- `D:\StudyspaceProjects\studyspace-backend\src\ocr\geminiClient.ts:2`

The OCR client builds the Gemini URL using:

- `process.env.GEMINI_MODEL`

But there is no fallback in that file.

So when `GEMINI_MODEL` is missing in production, OCR requests go to:

- `models/undefined:generateContent`

That causes OCR to fail with HTTP 404.

This is inconsistent with the rest of the OCR pipeline, which already assumes a fallback model:

- `D:\StudyspaceProjects\studyspace-backend\src\ocr\ocrPipeline.ts:59`
- `D:\StudyspaceProjects\studyspace-backend\src\ocr\ocrPipeline.ts:85`

Those lines fall back to:

- `gemini-2.5-flash`

But `geminiClient.ts` does not.

Impact:

- scanned PDFs that depend on inline OCR fail in production
- fallback extraction becomes much weaker than intended
- summary can degrade to poor text
- quiz/flashcards get even worse input and fail more often

### New Finding 11: Quiz and Flashcards Are Also Failing Independently With `Invalid JSON response`

Production backend logs also show:

```text
[AI Phase1] Error: Invalid JSON response
[SLOW] POST /quiz - ~18-19s
[SLOW] POST /flashcards - ~19s
```

This confirms the static diagnosis with live evidence:

- quiz/flashcards are failing server-side before Flutter parsing even matters
- the backend itself is rejecting the model output as invalid JSON

Relevant generation code remains:

- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:274`
- `D:\StudyspaceProjects\studyspace-backend\src\services\aiPhase1.service.ts:404`

So the live failure chain is now much clearer:

1. OCR fails for scanned PDFs because the OCR request uses `models/undefined`
2. source text quality becomes weak or partial
3. quiz/flashcards still demand strict JSON
4. the model returns malformed or schema-invalid output
5. backend throws `Invalid JSON response`
6. Flutter shows `AI generation failed`

### Updated Root Cause Ranking

#### Primary

1. Production OCR model config bug in `geminiClient.ts`
2. Strict JSON generation for quiz/flashcards
3. Sticky `ai_outputs` cache
4. Weak OCR acceptance heuristics

#### Secondary

5. Lossy summary preprocessing
6. Legacy phase-1 route usage
7. Dead OCR provider selector in Flutter

### Updated Practical Conclusion

The first fix should no longer start with prompt tuning. The first fix should be:

1. fix OCR model resolution in:
   - `D:\StudyspaceProjects\studyspace-backend\src\ocr\geminiClient.ts`
2. then re-test summary, quiz, and flashcards on the same PDF
3. then harden quiz/flashcard generation and cache invalidation

Without fixing the `models/undefined` OCR bug first, AI Studio will keep failing on any scanned PDF path no matter how much the UI is polished.

### Implementation Update (2026-03-26)

The OCR-first remediation is tracked as implemented in backend modules, with verification notes below.

1. OCR model resolution hardened
   - Target module: `src/ocr/geminiClient.ts`.
   - Claimed behavior: model name normalization, safe fallback resolution, and rejection of `undefined`/`null` tokens.
   - Symbol focus for verification: model resolver path that consumes `GEMINI_OCR_MODEL` and `GEMINI_MODEL`.

2. JSON retry/timeout tuned for faster failure and better observability
   - Target module: `src/services/aiPhase1.service.ts`.
   - Claimed behavior: bounded retry count, per-attempt timeout, non-identical retry variant, and structured retry logs.
   - Symbol focus for verification: JSON generation helper/retry branch used by quiz and flashcards.

3. Quiz/flashcard generation stabilized
   - Target module: `src/services/aiPhase1.service.ts`.
   - Claimed behavior: lower deterministic temperature override for schema-bound JSON generation.

4. Cache hardening and versioning for `ai_outputs`
   - Target module: `src/services/aiPhase1.service.ts` (cache key and cache read path).
   - Claimed behavior: cache key format `type:{version}` (for example `summary:v2`), shape validation on read, invalid-cache regeneration, and bypass via `force=true` or `AI_OUTPUTS_CACHE_BYPASS=true`.

5. OCR acceptance heuristics tightened
   - Target modules: `src/ocr/geminiClient.ts`, OCR pipeline/cache read logic, and AI generation entry path in `src/services/aiPhase1.service.ts`.
   - Claimed behavior: named acceptance rules replacing simple length-only checks.

6. Finding 8 status (`resources.extracted_text`)
   - Status: **Implemented (verification pending cross-repo artifact links)**.
   - Intended handling: `resources.extracted_text` is treated as an input candidate but must pass stricter OCR quality acceptance rules before downstream generation.
   - Trace points to verify: OCR acceptance decision path, cached OCR read path, and generation-prep selection logic.
   - Tracking note: until backend commit/PR links are attached in this document, this item remains in "implemented but evidence links pending" state.

#### Evidence Register (What Is Verifiable In This Repo Today)

- Workspace commit evidence (client/docs repo):
  - `ecfc1b6` - "Fix OCR args and attendance date helpers" (supports OCR argument hardening context).
  - `7baf528` - "fix(ai-studio): update OCR provider label to Gemini" (UI alignment with backend-forced Gemini provider).
- Backend code evidence (required for final sign-off):
  - Add backend commit SHA/PR for `src/ocr/geminiClient.ts` and `src/services/aiPhase1.service.ts` changes.
  - Add CI/test run IDs that exercised summary/quiz/flashcards on a scanned-PDF fixture.
  - Add short before/after diff excerpts for:
    - model normalization logic (`geminiClient.ts`),
    - timeout/retry branch (`aiPhase1.service.ts`),
    - cache key formatter (`type:{version}`),
    - OCR acceptance rule constants/functions.

### Cache Purge Sequencing And Operational Safety

Sequence decision for current LIKE-based purge:

- **Run purge after deploying the cache-version code only if full regeneration is intended.**
  - Reason: the current filter (`type IN (...) OR type LIKE 'summary:%' ...`) matches both legacy keys (`summary`) and versioned keys (`summary:v2`), so running it post-deploy clears old and new rows.
- If the goal is to remove only legacy entries, use a targeted legacy filter (for example exact `type IN ('summary','quiz','flashcards')`) and avoid broad LIKE predicates that also match current versioned keys.

Recommended safe runbook:

```sql
-- 1) Preview impact BEFORE delete
SELECT type, COUNT(*) AS rows_to_delete
FROM ai_outputs
WHERE type IN ('summary', 'quiz', 'flashcards')
   OR type LIKE 'summary:%'
   OR type LIKE 'quiz:%'
   OR type LIKE 'flashcards:%'
GROUP BY type
ORDER BY type;

-- 2) Optional backup (recommended when retention/audit is needed)
CREATE TABLE IF NOT EXISTS ai_outputs_backup_20260326 AS
SELECT *
FROM ai_outputs
WHERE type IN ('summary', 'quiz', 'flashcards')
   OR type LIKE 'summary:%'
   OR type LIKE 'quiz:%'
   OR type LIKE 'flashcards:%';

-- 3) Transactional purge with verification
BEGIN;

DELETE FROM ai_outputs
WHERE type IN ('summary', 'quiz', 'flashcards')
   OR type LIKE 'summary:%'
   OR type LIKE 'quiz:%'
   OR type LIKE 'flashcards:%';

-- 4) Post-delete validation in same transaction
SELECT type, COUNT(*) AS remaining_rows
FROM ai_outputs
WHERE type IN ('summary', 'quiz', 'flashcards')
   OR type LIKE 'summary:%'
   OR type LIKE 'quiz:%'
   OR type LIKE 'flashcards:%'
GROUP BY type
ORDER BY type;

COMMIT;
```

After purge, re-run end-to-end checks for summary, quiz, and flashcards on the same scanned PDF fixture.
