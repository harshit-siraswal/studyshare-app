# StudyShare Performance And Production Scale Audit
Date: 2026-03-26
Scope: Flutter client code paths currently in workspace (startup, navigation, feed loading, chat, notices, service/data access patterns).

## Executive Summary
Current slowness is primarily caused by:
1. Blocking cold-start pipeline before first usable screen.
2. Frequent full-screen remounts and repeated network fetches when switching tabs.
3. N+1 request patterns in resource cards and notices.
4. Fallback query strategies that become expensive at scale.
5. Over-fetching rows/columns and missing pagination in high-volume paths.

These issues are solvable with architecture-level changes (batched endpoints, cached state stores, incremental loading) and a few structural UI changes (state-preserving tab navigation, non-blocking startup).

Critical Finding #0:
- Production telemetry is not sufficiently instrumented yet for startup, navigation, request volume, and frame stability metrics. Phase 1-3 rollout claims are blocked until instrumentation baselines are collected.

## Implementation Progress (2026-03-26)

Completed in app code:
- Non-blocking startup path shipped (app reaches ready state before push init finishes).
- Home tab root remount removed via state-preserving tab container.
- Notices list switched to paginated fetch with load-more behavior.
- Study following-feed startup no longer forces profile refresh.
- Resource cards support deferred remote hydration in heavy lists.
- Shared HTTP client is now default in backend API service.

Completed as interim N+1 mitigation:
- Bookmark state prefetch added at list level before rendering cards.
- Vote state prefetch added with bounded concurrency and cache hydration.
- Combined resource-state prefetch introduced via repository abstraction and wired into Study/Search loaders.
- Repository prefetch now uses a single bulk backend call path (`POST /api/resources/state`) and falls back only when backend compatibility status indicates endpoint unavailability.

Still pending for Phase-2 completion:
- Server-side implementation/deploy of `POST /api/resources/state` in backend repository (client integration is already completed in this app repo).
- Request/latency instrumentation for production SLO tracking (startup, tab switch, requests per screen open).

Backend contract (for backend repo implementation):
- Request body: `{ "resourceIds": ["id1", "id2", ...] }`
- Response body: `{ "states": [{ "resourceId": "...", "isBookmarked": true|false, "userVote": -1|0|1|"upvote"|"downvote"|null, "upvotes": number, "downvotes": number }] }`
- Compatibility behavior by error class:
	- Permanent/structural errors (`404`, `405`, `406`, `415`, `501`): immediately enter session-level fallback to legacy bookmark+vote prefetch path.
	- Transient server errors (`500`, `502`, `503`, `504`): retry with exponential backoff + jitter up to configured max attempts, then fall back to legacy bookmark+vote prefetch path.
	- Client/auth errors (`400`, `401`, `403`): do not fallback; propagate error to caller/UI.

## Critical Findings (High Impact)

### 1) Cold start is blocked by non-essential initialization
Evidence:
- `initApp()` awaits multiple services before app is marked ready: `lib/main.dart` lines around 357-459.
- Push setup is awaited before `AppState.ready`: `lib/main.dart` lines around 476-571.

Why this hurts:
- Users wait for network-dependent services (push token registration, messaging setup) before seeing usable UI.
- On weak networks/devices this creates large time-to-interactive variance.

Production fix:
- Move push initialization and token sync fully to background after first frame/home render.
- Keep only must-have initialization blocking (theme prefs + minimal auth/session bootstrap).

Expected gain:
- Primarily reduces worst-case cold-start variance; average gains depend on device/network and whether FCM token state is already warm.

---

### 2) Tab changes recreate entire screens, forcing reload/rebuild
Evidence:
- Home uses `PageTransitionSwitcher` + `KeyedSubtree(ValueKey(_currentIndex))`: `lib/screens/home/home_screen.dart` around lines 591-603.
- `_getScreen(_currentIndex)` returns new `StudyScreen`, `NoticesScreen`, etc each switch: `lib/screens/home/home_screen.dart` around lines 520-545.

Why this hurts:
- Tab switch causes remount, re-init, and network refetch of heavy screens.
- Perceived as "app slow at every step" during navigation.

Production fix:
- Replace with `IndexedStack` + `AutomaticKeepAliveClientMixin` for tab roots.
- Persist tab state and only animate inner content, not tab root teardown.

Expected gain:
- Near-instant tab switching after first load.

---

### 3) N+1 network pattern in feed cards (bookmark + vote + download)
Evidence:
- Each `ResourceCard` triggers `_checkBookmark()`, `_refreshVoteState()`, `_refreshDownloadState()` in `initState()`: `lib/widgets/resource_card.dart` lines around 60-66.
- Each has async calls per card: `lib/widgets/resource_card.dart` lines around 77-107.

Why this hurts:
- 20 cards can trigger 40+ network calls (+ local I/O) on first paint.
- Scroll jank and delayed interactive controls.

Production fix:
- Add batch endpoint(s): `GET /resources/state?ids=...` returning bookmark+vote for all visible ids.
- Preload card states at list level and pass into card widget.
- Keep download state lookup local and lazily load for visible viewport only.

Expected gain:
- Large reduction in API chatter and first-list render latency.

---

### 4) Study tab startup fans out multiple fetches and duplicates profile calls
Evidence:
- `StudyScreen.initState()` runs `_loadFilters()`, `_loadUserProfile()`, `_loadResources()`, `_loadFollowingFeed()`, `_loadUnreadNotificationCount()`: `lib/screens/study/study_screen.dart` lines around 187-210.
- `_loadFollowingFeed()` calls `_loadUserProfile(forceRefresh: true)` again: `lib/screens/study/study_screen.dart` lines around 301-312.

Why this hurts:
- Redundant profile and feed lookups on entry.
- `forceRefresh: true` explicitly bypasses profile cache, increasing backend load and causing avoidable stale/flicker windows.

Production fix:
- Centralize profile fetch once per session (state container with TTL).
- Defer non-visible tab data until tab is first opened.
- Rate-limit notification unread fetch and avoid repeating on every refresh.
- Audit all `forceRefresh: true` call sites and keep them only for explicit user-initiated refresh flows.

Expected gain:
- Faster first Study render and lower backend load.

---

### 5) Fallback query fan-out can multiply backend load per action
Evidence:
- Relevant scope fallback tries multiple combinations sequentially (up to 6 additional queries): `lib/screens/study/study_screen.dart` lines around 760-796.
- Following/user resource fallback can pull oversized windows then filter client-side: `lib/services/supabase_service.dart` around lines 831-856 and 4794-4813.

Why this hurts:
- At scale, fallback-based query expansion creates expensive read amplification.
- Works around schema/data inconsistency in client instead of server.

Production fix:
- Phase prerequisite: run data audit + canonicalization migration for branch/subject values.
- Then introduce a single ranked query endpoint server-side.
- Remove client fallback fan-out only after migration validation window confirms no content-loss regressions.
- Enforce canonical values + indexed searchable columns in DB.

Expected gain:
- Lower p95 latency and significantly lower DB read volume.

## Major Findings (Medium Impact)

### 6) Notices API fetches all rows without pagination
Evidence:
- `getNotices()` performs `.select().order(...)` with no `range/limit`: `lib/services/supabase_service.dart` around lines 4531-4541.

Risk at scale:
- Notice list response grows unbounded and slows every refresh.

Fix:
- Add cursor/page API and lazy load in UI.

---

### 7) Department follower counts are N+1
Evidence:
- `Future.wait` over departments, each calling `getDepartmentFollowerCount`: `lib/screens/notices/notices_screen.dart` around lines 316-333.
- Count query per department: `lib/services/supabase_service.dart` around lines 4240-4267.

Risk at scale:
- More departments => linear extra queries on notices load.

Fix:
- Add aggregated endpoint returning counts for all departments in one call.

---

### 8) Broad `select()` over-fetches payloads
Evidence:
- Multiple `.select()` with all columns in hot paths: `lib/services/supabase_service.dart` lines around 721, 806, 4536, 4794.

Risk at scale:
- Extra payload size + deserialization overhead + slower list render.

Fix:
- Use explicit column projection for list views and lightweight cards.

---

### 9) Service instantiation pattern fragments networking resources
Evidence:
- `BackendApiService` creates a new `http.Client` by default: `lib/services/backend_api_service.dart` line 50.
- Many direct `BackendApiService()` allocations across screens/services (22 locations).

Risk:
- Connection reuse inefficiency and harder central QoS/observability.

Fix:
- Convert to DI-managed singleton/repository layer with shared HTTP client and interceptors.

---

### 10) Heavy feature/asset surface increases binary and startup pressure
Evidence:
- Broad assets include `assets/videos/`, `assets/animations/`, etc in pubspec.
- Android release has shrink/minify, but no explicit ABI split strategy in current gradle.

Fix:
- Move large optional assets remote or on-demand.
- Use Android App Bundle (AAB) as default production packaging.
- Consider ABI split APKs only for distribution channels that can reliably deliver per-ABI artifacts.

## Practices Not Ready For Large Scale (Current)
1. Client-side fallback logic as primary data compatibility strategy.
2. Per-item API requests in list cards.
3. Unbounded list fetches without pagination.
4. Recreating tab roots on navigation.
5. Startup blocking on non-critical network initialization.
6. Mixed data access paths (backend + direct supabase) in same features, increasing inconsistency and cache misses.

## Additional Backlog Items (From Review)
1. Error/retry behavior under flaky networks for concurrent `Future.wait` paths, including partial-failure handling and user feedback consistency.
2. Widget rebuild scope audit to reduce broad parent `setState()` impact on list-heavy screens.
3. Image caching verification on feed/card surfaces to ensure decoded image reuse and reduced scroll jank.
4. Supabase Realtime subscription lifecycle audit (subscribe/unsubscribe hygiene) to prevent background listener leaks.

## Recommended Production Plan

### Phase 0 (Instrumentation Blocker, required before Phase 1)
1. Add Flutter performance hooks for cold start, navigation span timing, and frame build/raster stability on key screens.
2. Add client request counters and network span events for Study/Notices/AI Chat opens.
3. Add backend endpoint tracing + DB slow query telemetry for resources/notices/follows APIs.
4. Validate metric schemas/contracts end-to-end and set dashboards/alerts before optimization rollout.
5. Collect a minimum 7-day baseline window (>= 1,000 sessions, segmented by network/device tier).

Phase dependency note:
- Phase 1, Phase 2, and Phase 3 execution and validation are blocked until Phase 0 instrumentation and baseline capture are complete.

### Phase 1 (1-3 days, highest ROI)
1. Persist tab roots (`IndexedStack`) and stop remount on tab switch.
2. Make push/Firebase token sync non-blocking after first interactive frame.
3. Add pagination for notices and cap initial fetch size.
4. Remove duplicate profile fetch in Study startup path.

Validation and risk checks for Phase 1:
- Unit/integration tests:
	- Navigation state retention tests for tab switches (state preserved across Home/Chats/Notices/Profile).
	- Startup flow tests ensuring app reaches ready state when optional services (push/home widget) fail.
	- Notices pagination contract tests (first page, next page, empty page behavior).
- Performance benchmarks (before/after):
	- Cold start p50/p95.
	- Warm tab switch latency p50/p95.
	- Requests fired during first Study and Notices screen open.
- Rollout plan:
	- Canary: 5% internal users for 24h.
	- Beta: 25% users for 48h.
	- Production: 100% only if no >5% regression in p95 startup/tab-switch.
- Rollback/mitigation:
	- Feature flags for non-blocking startup and tab persistence.
	- Immediate rollback to previous navigation/startup behavior on crash or startup timeout spikes.
- Monitoring/alerts:
	- Alert if startup p95 regresses >15% from baseline for 30 min.
	- Alert if navigation error/crash rate >0.3% per session.
- Owners and validation time:
	- Mobile owner: Flutter Lead (primary), QA owner: Mobile QA Lead.
	- Estimated validation time: 1.5 engineer-days + 1 QA-day.

### Phase 2 (3-7 days)
1. Introduce repository skeleton (read-through cache + shared transport abstraction) before endpoint rewiring.
2. Introduce batched resource state endpoint integration (votes/bookmarks for visible ids) through repository abstraction; backend must deploy `POST /api/resources/state` before mobile integration can be finalized.
3. Replace fallback fan-out in Study resource loading with one server-ranked query after data normalization.
4. Aggregate department follower counts endpoint.

Phase 2 sequencing clarification:
- This phase assumes backend-side implementation/deploy of `POST /api/resources/state` is completed first (see pending item in Implementation Progress).

Validation and risk checks for Phase 2:
- Unit/integration tests:
	- Endpoint tests for batched state API and moderation/feed rank API.
	- Contract tests for shape compatibility with `ResourceCard` and notices department counters.
	- Regression tests for follow/feed visibility permissions.
- Performance benchmarks (before/after):
	- Requests per feed open.
	- Feed first contentful paint p50/p95.
	- Backend endpoint p95 and DB query duration.
- Rollout plan:
	- Canary: internal + 5% prod traffic with dual-write/dual-read telemetry where feasible.
	- Beta: 25-50% traffic when error budget remains healthy for 48h.
	- Production: full rollout after DB and API p95 targets pass for 72h.
- Rollback/mitigation:
	- Keep legacy endpoint path behind switch for immediate fallback.
	- DB migration rollback script for index/query plan changes.
- Monitoring/alerts:
	- Alert on 4xx/5xx increase >2x baseline.
	- Alert on DB query p95 over threshold for resources/notices/follows.
- Owners and validation time:
	- Backend owner: API Lead, Mobile owner: Flutter Lead, DB owner: Data Engineer.
	- Estimated validation time: 3 engineer-days + 1.5 QA-days.

### Phase 3 (1-2 weeks)
1. Introduce app-level data repository with singleton HTTP client + request dedupe + stale-while-revalidate cache.
2. Normalize DB schema/canonical branch-subject values and add missing indexes.
3. Add full observability: p50/p95 API, cold-start TTI, frame build/raster metrics.

Validation and risk checks for Phase 3:
- Unit/integration tests:
	- Repository cache coherency tests (stale-while-revalidate, invalidation, dedupe).
	- Schema normalization migration tests with backward compatibility reads.
	- End-to-end tests covering AI chat, Study feed, Notices, follow graph under new repository layer.
- Performance benchmarks (before/after):
	- End-to-end TTI and p95 screen-open latency.
	- API p95/p99 and DB p95 under load-test profile.
	- Frame build/raster jank percentage.
- Rollout plan:
	- Canary with shadow metrics and read-compare checks.
	- Beta rollout by cohort/region.
	- Prod rollout gated by observability parity and no elevated error budget burn.
- Rollback/mitigation:
	- Feature flags for repository layer and schema-read compatibility mode.
	- Rollback migration scripts and index revert scripts pre-approved.
- Monitoring/alerts:
	- SLO burn-rate alerts for API p95/p99 and crash-free sessions.
	- Alert on cache hit-rate collapse and unexpected DB read amplification.
- Owners and validation time:
	- Platform owner: Mobile Architecture Lead, Backend owner: API Lead, SRE owner: Observability Engineer.
	- Estimated validation time: 5-7 engineer-days + 2 QA-days.

### Validation & Risk Mitigation

Risk matrix (data-layer focused):

| Change Area | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Replace fallback fan-out with ranked API | High | Medium | Run canary with dual-path telemetry; keep legacy path flag for rollback. |
| Add batched state endpoint for cards | Medium | Medium | Contract tests + strict response schema validation in client. |
| Notices pagination migration | Medium | Low | Backward-compatible pagination defaults and fallback to first page only. |
| Schema normalization/index updates | High | Medium | Online migration plan, precomputed rollback scripts, off-peak deploy window. |
| Repository-level cache introduction | Medium | Medium | Incremental enablement by screen with cache metrics and kill switch. |
| Instrumentation / telemetry pipeline | Medium-High | Medium | End-to-end telemetry contract tests, staged metrics rollout, schema validation, backfill/rollback plan, and health dashboards with alerts. |

Timeline capacity/dependency note:
- The Phase estimates assume one mobile engineer, one backend engineer, and shared QA capacity.
- Phase 2 depends on backend endpoint readiness, DB normalization/migration approval, and repository skeleton readiness before mobile integration can be finalized.
- Phase 3 should not start full rollout until Phase 2 telemetry is stable for at least one full traffic cycle.

## Metrics To Track Before Production Rollout

Measurement methodology:
- Capture a baseline window first (minimum 7 days, at least 1,000 sessions, segmented by device tier and network quality).
- Measure mobile rendering with Flutter DevTools/profile mode and production telemetry hooks.
- Measure API/DB latencies through APM and database tracing dashboards.

| Metric | Current Baseline | Target (SLO) | Tool/Method |
|---|---|---|---|
| Cold start (process start -> first interactive frame) | Not yet instrumented in production telemetry (blocker) | p50 <= 2.5s, p95 <= 4.0s on mid-tier Android | Flutter DevTools startup timeline + release telemetry, sampled per app version daily |
| Warm tab switch latency (Home/Notices/Profile) | Not yet instrumented in production telemetry (blocker) | p50 <= 180ms, p95 <= 350ms | Frame timing traces + custom navigation span events, sampled from 20% sessions |
| Requests per screen open (Study, Notices, AI Chat) | Not yet instrumented in production telemetry (blocker) | Study <= 6, Notices <= 4, AI Chat <= 5 initial requests | Network inspector in QA + client request counters in release telemetry, weekly audit |
| Feed first contentful paint + scroll frame stability | Not yet instrumented in production telemetry (blocker) | FCP p95 <= 1.2s, janky frames <= 3% on feed scroll | Performance overlay + frame build/raster metrics + sampled RUM sessions |
| API p95/p99 + DB query timings (resources/notices/follows) | Partial backend metrics only; no complete endpoint-by-endpoint baseline yet | API p95 <= 600ms, API p99 <= 1200ms, DB p95 <= 250ms for top queries | APM endpoint tracing + DB slow query logs + weekly regression dashboards |
| Auth token refresh rate and forced mid-session re-auth | Not yet instrumented in production telemetry (blocker) | <= 1 forced re-auth per 1,000 active sessions/day | Auth lifecycle telemetry + token refresh error counters, daily monitoring |
| Widget build count per frame on key screens | Not yet instrumented in production telemetry (blocker) | No repeated spikes above frame budget on Home/Study/Notices during common interactions | Flutter DevTools rebuild profiler + sampled automated interaction traces per release |

Validation gate:
- Do not claim optimization completion until each metric has a measured baseline and two consecutive post-change windows of at least 7 days each meeting targets.

## Quick Wins You Can Ship Immediately
1. Stop blocking `AppState.ready` on push setup.
2. Replace keyed tab remount with state-preserving tab container.
3. Limit notices to first page and lazy load next pages.
4. Batch vote/bookmark state for visible card ids.

## Final Assessment
The app is feature-rich but currently optimized for correctness/fallback resilience over throughput. For production scale, prioritize reducing request fan-out, preserving UI state across navigation, and moving compatibility logic out of the client into stable backend contracts.
