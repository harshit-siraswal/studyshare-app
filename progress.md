Original prompt: Continue the StudySpace fixes by resolving AI Studio generation failures, background generation persistence, attendance schedule/projection issues, and replacing the AI Studio loading mini-games with stronger arcade-style games after doing graph-based diagnosis and EC2 log review.

- 2026-04-16: Confirmed production backend still throws `operator does not exist: uuid ~~* unknown` on `/api/departments/following`; local backend already has the `.eq(...)` fix, so deployment is still required.
- 2026-04-16: Added backend AI background job support for legacy Phase 1 endpoints (`summary`, `quiz`, `flashcards`) by queueing into `ai_runs` and `ai_generation_jobs`, returning `202`, and letting the worker process queued text jobs through `generateAiOutput(...)`.
- 2026-04-16: Wired Flutter AI Studio to queue background jobs, persist pending job ids locally, resume polling after reopen, and load completed results back into the sheet with local persistence.
- 2026-04-16: Updated attendance schedule rendering so grouped weekly/day views stop repeating the date inside each class card; adjusted projection math to use the upcoming scheduled class window instead of penalizing only selected misses.
- 2026-04-16: Replaced the old AI Studio loading toys with three arcade-style games inside `AiLoadingGameCard`: `Sky Hop`, `Brick Blitz`, and `Dino Dash`.

TODOs
- Deploy the updated backend to EC2 and verify `/api/ai/*` background flow plus the department follow endpoint on production.
- Run a real Flutter/web/device smoke test for AI Studio queue/resume and the new loading card interactions.
- Verify whether the AI chat notice-source chips still fail due to backend source metadata on production, since the app-side open handler already exists.
