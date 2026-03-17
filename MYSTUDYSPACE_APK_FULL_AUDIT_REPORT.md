# Studyshare APK — Full Audit Report (Functionality + Database + UI/UX)

**Date:** 2026-01-28  
**Scope:** Android APK (Flutter app) vs existing Web app (`<PROJECT_ROOT>/Studyshare`)  
**Current status (reported):** “Only able to view resources; almost all other actions fail (loading / PostgREST errors / non-functional UI).”

---

## Executive Summary

Your **database security model** (as implemented in `Studyshare` SQL files) is:
- **Firebase Auth** is the identity provider (NOT Supabase Auth).
- **Frontend clients (website + APK) use Supabase anon key for READ operations**.
- **All WRITE operations must go through a privileged backend (service-role / admin client)**.
- RLS is intentionally designed to **block direct writes** from anon clients (defense-in-depth).

### What’s going wrong in the APK
1. The APK is still performing some **direct Supabase writes** (insert/update/delete) for features like bookmarks/likes/comments/rooms/posts — these **must not happen** in this architecture.
2. Some APK features are using a **schema that doesn’t match the current DB** (example: `room_post_comments.post_id` vs backend’s `message_id` model).
3. The APK’s new security layer (Firebase token + reCAPTCHA + backend) is not integrated consistently across **every write path**, causing “loading forever” and partial breakage.
4. UI layout issues (black gaps + system nav overlap) are caused by **inconsistent SafeArea/bottom padding** and/or double-padding patterns in different screens.
5. Bottom bar issues include **hit target sizing**, icon alignment, and consistent center FAB behavior across devices with gesture vs button navigation.

---

## Repository Sources Used (Ground Truth)

### Web / Architecture / SQL (Studyshare)
Located at: `<PROJECT_ROOT>/Studyshare`

Key files used in this audit:
- `UNIFIED_RLS.sql` — defines the **core security architecture**
- `BACKEND_SCHEMA.sql` — backend-required tables and policies
- `NOTICE_COMMENTS_SETUP.sql` — notice comments table and RLS
- `CHATROOM_COMPLETE_FIX.sql` — join code / chat room schema enhancements
- `FIX_BOOKMARKS_FK.sql` — required FKs for PostgREST relationship caching
- `FIX_ALL_LIKES_RLS.sql` — likes table read-only policy
- `src/lib/api.ts` — website’s backend API client (Firebase token + recaptcha)
- `.env` — includes `VITE_API_URL` and reCAPTCHA site key

### Flutter / APK (studyshare-app)
Located at: `<PROJECT_ROOT>/studyshare-app`

Note: Replace `<PROJECT_ROOT>` with your local workspace root (for example
`D:\Projects` or `~/dev`). If you need per-developer overrides, store them in a
config or `.env` rather than hardcoding absolute paths.

Key files referenced:
- `flutter_application_1/lib/services/supabase_service.dart`
- `flutter_application_1/lib/services/backend_api_service.dart`
- `flutter_application_1/lib/services/recaptcha_service.dart`
- `flutter_application_1/lib/screens/home/home_screen.dart`
- `flutter_application_1/lib/screens/notices/notices_screen.dart`
- `flutter_application_1/lib/screens/notices/notice_detail_screen.dart`
- `flutter_application_1/lib/screens/chatroom/chatroom_list_screen.dart`
- `flutter_application_1/lib/screens/chatroom/chatroom_screen.dart`
- `flutter_application_1/lib/screens/chatroom/post_detail_screen.dart`
- `flutter_application_1/lib/screens/profile/profile_screen.dart`
- `flutter_application_1/lib/screens/profile/edit_profile_screen.dart`
- `flutter_application_1/lib/widgets/upload_resource_dialog.dart`
- `flutter_application_1/lib/config/app_config.dart`

---

## Database Architecture (from Studyshare SQL) — What the App MUST follow

### Identity model
From `UNIFIED_RLS.sql`:
- **Firebase Auth** is used.
- Supabase is used as data store.
- Frontend uses **anon key** (read only).
- Backend uses **service role** (bypasses RLS) for writes.

### Core security model
From `UNIFIED_RLS.sql`, `NOTICE_COMMENTS_SETUP.sql`, `BACKEND_SCHEMA.sql`:
- RLS enabled on most tables.
- Policies allow `SELECT` widely for public reads.
- Policies often **deny INSERT/UPDATE/DELETE** from frontend.

### Important implication
In this architecture, the APK must:
- Use Supabase client for **SELECT-only** queries.
- Use backend API for **all writes** (create room, post message, add comment, bookmark/like, upload resource, update profile).

If the APK performs direct Supabase writes, you will see errors like:
- `42501 Unauthorized / violates row-level security policy`
- PostgREST schema cache errors if FK/columns mismatch (`PGRST204`, missing relationship errors)

---

## Functional Audit (by Feature)

### 1) Authentication (Google / Email)
**Expected:** sign in works, user profile loads, role derived by college email domain or user_roles override.

**Observed failures (reported historically):**
- crashes / broken login flows (previously)
- downstream writes failing due to RLS after login

**Likely root causes:**
- Missing/invalid Firebase configuration or token retrieval
- Backend expects Firebase ID token but app sometimes calls API without it

**Fix direction:**
- Ensure every privileged backend request includes:
  - `Authorization: Bearer <firebaseIdToken>`
  - `recaptchaToken` for endpoints that require it

---

### 2) Resources Feed (the only working feature)
**Expected:** resources list loads; filtering/search works; view details; download/open.

**Why it works:** Resources are read via Supabase `SELECT` and your RLS allows read access.

**Still broken paths:**
- Upload resource (should go through backend + recaptcha)
- Vote on resource (if votes are write-protected by RLS)
- Bookmark resource (bookmarks are RLS protected)

**Fix direction:**
- Route upload/vote/bookmark to backend endpoints only.
- Confirm backend endpoints exist for:
  - create resource: `POST /api/resources`
  - vote: `POST /api/votes` (website has it)
  - bookmarks: `POST /api/bookmarks` / delete endpoints (website has it)

---

### 3) Bookmarks (Resources + Notices) — PostgREST errors
**Expected:** user can bookmark/ unbookmark items; bookmarks list loads.

**Observed:** PostgREST errors when trying to bookmark.

**Root causes:**
1. Direct Supabase write to `bookmarks` is blocked by RLS (expected).
2. PostgREST relationship errors occur if `FIX_BOOKMARKS_FK.sql` is not applied (missing FK constraints).
   - Without FK, PostgREST can’t perform join-based `select('resource_id, resources(*)')`.

**Fix direction:**
- **All bookmark writes** must go through backend `/api/bookmarks`.
- Ensure DB has FK constraints by applying `FIX_BOOKMARKS_FK.sql` (this is database schema integrity; not “changing RLS”).
- For read-only clients, prefer backend `/api/bookmarks` as well (website does), because it can return “enriched” bookmark content safely.

---

### 4) Notices
**Expected:**
- notices list loads
- notice detail loads
- notice comments thread/reply works
- notice share as PNG with watermark

**Observed:**
- comments fail (RLS 42501 / unauthorized)
- share behavior missing (must be PNG + watermark `viastudyshare`)

**Root causes:**
- DB `notice_comments` is designed **read-only for frontend** (`NOTICE_COMMENTS_SETUP.sql`)
- Therefore comment POST must go through backend: `/api/notices/:id/comments` (website has it).

**Fix direction (app):**
- Use backend for:
  - posting notice comment (with recaptcha + firebase token)
  - deleting comment (if supported)
  - likes (if supported)
- Keep Supabase for reads only.

**Share as PNG + watermark requirement (must be re-added):**
- Implement “Share” as:
  1. Render a “share card” widget (notice content + author + date + optional media thumbnail)
  2. Add watermark text: **`viastudyshare`** (bottom-right, semi-transparent)
  3. Capture as image via `screenshot` package
  4. Share using `share_plus`

---

### 5) Chat Rooms (Rooms)
**Expected:**
- create room
- join room
- post message (reddit-style room_messages)
- comment on post/message
- vote / save post

**Observed:**
- “loading” on post actions
- RLS errors for create room / post / comment
- schema mismatch errors:
  - `PGRST204 Could not find post_id column of room_post_comments`

**Root causes:**
1. RLS: chat tables are read-only for frontend (`UNIFIED_RLS.sql`).
2. Schema mismatch:
   - backend and DB likely use a `message_id` relationship (per website `api.ts` types and endpoints),
   - but Flutter uses `post_id` in `room_post_comments`.

**Fix direction:**
- Use backend endpoints from website (`src/lib/api.ts`):
  - `POST /api/chat/rooms`
  - `POST /api/chat/messages`
  - `GET /api/chat/comments/:messageId`
  - `POST /api/chat/comments`
  - `PUT /api/chat/messages/:id/vote` (if implemented)
  - `POST /api/chat/saved` (if implemented)
- Ensure Flutter uses **the same identifiers**:
  - message id field naming (`messageId`) not `post_id`
- Fix joins and PostgREST queries: avoid direct writes; avoid selecting joins that require missing FKs unless DB has them.

---

### 6) Profile
**Expected:**
- display user photo + name + email
- edit profile (name/photo/bio)
- follow/followers lists

**Observed:**
- profile photo not loaded
- edit profile “not functional”

**Root causes:**
1. Profile data is a backend concept in your architecture:
   - website uses `GET /api/users/profile` and `PUT /api/users/profile`.
2. Flutter must not attempt to write profile fields directly to `users` table via anon.
3. “Not functional” typically indicates:
   - backend request missing firebase token or recaptcha token,
   - or request is not sent (e.g., missing BuildContext for recaptcha),
   - or API returns non-JSON / errors not surfaced.

**Fix direction:**
- Always fetch profile from backend.
- Ensure edit profile update uses backend and includes:
  - firebase token
  - recaptcha token
- Upload avatar using Cloudinary first, then update profile with `profile_photo_url`.

---

## UI/UX Audit

### A) “20% of screen black” (persistent)
**Symptom:** A large portion of each page remains black/empty.

**Most likely causes:**
1. Double-padding bottom (parent + child) leaving empty space with dark background.
2. Nested `Scaffold`/`SafeArea` + `Padding` mismatch.
3. A `Container` with fixed height not matching available space.

**Fix approach:**
- Choose ONE consistent strategy:
  - Either:
    - parent (`HomeScreen`) adds no padding, children handle safe area, OR
    - parent adds padding, children do not.
- Audit every tab screen:
  - `StudyScreen`, `NoticesScreen`, `ChatroomListScreen`, `ProfileScreen`
  - ensure they do not “over-add” bottom padding when embedded.

---

### B) System navigation overlap (gesture vs button navigation)
**Symptom:** On devices with 3-button nav, content is hidden behind system bar.

**Fix approach:**
- Use `SafeArea(bottom: false)` and manually add:
  - `MediaQuery.of(context).viewPadding.bottom` (system nav) — **not** `padding.bottom` in some cases
  - plus bottom bar height
  - plus small buffer.
- Avoid mixing `viewInsets` (keyboard) into screen padding except input bars.

Recommended constant:
- Bottom app bar height: ~60
- Extra buffer: 8
- Effective bottom padding: `MediaQuery.of(context).viewPadding.bottom + 60 + 8`

---

### C) Bottom bar alignment + icons
**Required behavior:**
- All icons aligned and same size
- Center “+” FAB bigger and centered
- Touch targets large and consistent (minimum 48×48)

**Fix approach:**
- For each nav item use a fixed hit box (e.g., 72×60) and center the icon.
- Ensure FAB doesn’t shift tap targets by overlaying wrong `SizedBox` gap.
- Confirm `FloatingActionButtonLocation.centerDocked` and bottom bar layout matches.

---

## Security Audit (Required)

### reCAPTCHA
**Requirement:** add reCAPTCHA v3 on mobile and “improve security everywhere.”

**Correct model (from website):**
- reCAPTCHA token generated on client
- sent to backend (`recaptchaToken`)
- backend verifies token server-side with secret
- backend allows/denies request

**APK considerations:**
- reCAPTCHA v3 is web-first; mobile needs WebView or an equivalent server-side scoring workaround.
- If WebView fails or hangs, it causes “loading forever.”

**Fix approach:**
- Add a timeout for reCAPTCHA token generation and show error.
- Keep a strict rule: no token → no write request.

---

## Verification Checklist (what must work before release)

### Read-only (non college email) user
- Can:
  - view resources
  - view notices
  - view rooms list
  - view profiles
- Cannot:
  - create room
  - join room (if required)
  - post message
  - comment (notices/rooms)
  - upload resources
  - vote/bookmark/follow

### Verified college email user
- Can:
  - all read-only permissions +
  - create room
  - post in rooms
  - comment in rooms
  - comment on notices
  - bookmark resources + notices
  - follow users (if enabled)
  - update profile (name/photo/bio)
  - share notice as PNG with watermark

---

## Required Fix Plan (Engineering Steps)

### Phase 1 — Restore core functionality
1. Identify every write path in Flutter and route through backend endpoints (do not write to Supabase directly).
2. Standardize chat post/comment schema to backend:
   - message-based identifiers, not `post_id` where DB uses `message_id`
3. Make bookmarks read/write go through backend `/api/bookmarks`.
4. Ensure profile read/write go through backend `/api/users/profile`.

### Phase 2 — UI layout stabilization
1. Remove any double bottom padding across tab screens.
2. Ensure system nav safe area is handled consistently:
   - `viewPadding.bottom + bottomBarHeight + buffer`
3. Ensure bottom bar hit targets and alignment are consistent.

### Phase 3 — Security hardening
1. Add reCAPTCHA token generation timeouts, retries, and error UI.
2. Ensure backend verifies reCAPTCHA token.
3. Add rate limiting (backend) for all writes.

### Phase 4 — Share as PNG with watermark
1. Create share card widget with watermark `viastudyshare`
2. Capture via screenshot
3. Share via `share_plus`

---

## Appendix — Key DB Tables (as referenced in SQL)

### resources
- used for resources feed; RLS read allowed; writes via backend only.

### bookmarks
- requires FK constraints:
  - `bookmarks.resource_id -> resources.id`
  - `bookmarks.notice_id -> notices.id`
  (see `FIX_BOOKMARKS_FK.sql`)

### notices
- notice feed (read allowed)

### notice_comments
- `notice_id TEXT`, `college_id TEXT`, `user_email`, `user_name`, `content`
- RLS read-only; inserts denied (see `NOTICE_COMMENTS_SETUP.sql`)

### chat_rooms
- includes `join_code` for private rooms (see `CHATROOM_COMPLETE_FIX.sql`)

### room_messages
- used as “posts” in rooms (reddit-style), read-only from frontend

### room_post_comments
- read-only from frontend; schema must match backend relationship (message-based)

---

## DOCX Export Instructions

### Option A (fast): Word / Google Docs
1. Open this file in VS Code / Cursor.
2. Copy all content.
3. Paste into Microsoft Word or Google Docs.
4. Export:
   - Word: **File → Save As → `.docx`**
   - Google Docs: **File → Download → Microsoft Word (.docx)**

### Option B (automatic .docx generation)
If you want me to generate a real `.docx` file automatically, approve installing `python-docx` locally and I’ll generate:
- `Studyshare_APK_Audit_Report.docx`



