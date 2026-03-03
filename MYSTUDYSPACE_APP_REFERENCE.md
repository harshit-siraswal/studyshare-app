# MyStudySpace App Reference (Mobile + AI)

Last updated: March 1, 2026

This document is a practical technical reference for the `mystudyspace-app` Flutter project, with extra depth on AI capabilities.

## 1. Product Snapshot

MyStudySpace is a college-scoped study platform with:
- Study resources (notes, PYQs, videos, syllabus)
- Social graph (follow/following)
- Chatrooms and threaded discussion
- Notices and announcements
- Profile, bookmarks, saved posts
- AI Studio (in-resource AI) and AI Chat (cross-resource assistant)

Core product rule:
- Data is college-scoped wherever possible (resources, notices, feeds, moderation).

## 2. System Architecture (Mobile App)

Primary app location:
- `flutter_application_1/`

Main layers:
- UI/screens/widgets in `lib/screens` and `lib/widgets`
- Data/service clients in `lib/services`
- Domain models in `lib/models`

Key service responsibilities:
- `BackendApiService`: backend HTTP API client for privileged operations and AI endpoints.
- `SupabaseService`: Supabase query layer + compatibility fallbacks.
- `AuthService`: Firebase auth/session behavior.
- `CloudinaryService`: attachment uploads.
- `SummaryPdfService`: AI summary/report/question paper export to PDF.

External dependencies used by mobile:
- Backend API (`AppConfig.apiUrl`, fallback URLs supported)
- Supabase (DB and query layer)
- Firebase Auth + FCM
- Cloudinary (file hosting)
- Optional n8n sidecar for async AI workloads (as documented in `N8N_AI_AUTOMATION_IMPLEMENTATION_GUIDE.md`)

## 3. Core App Features (Non-AI)

### 3.1 Auth and Profile
- College-aware sign-in flows.
- Role model includes: `READ_ONLY`, `COLLEGE_USER`, `MODERATOR`, `ADMIN`, `TEACHER`.
- Effective role can be elevated to `TEACHER` when `admin_key` exists on profile (`AppUser.fromJson`, role resolvers in `StudyScreen` and `SupabaseService`).

### 3.2 Study Hub
- Main tabs: For You / Following / Syllabus.
- Resources are fetched from `resources` table with filter support (semester, branch, subject, type, search, sort).
- Approved-only resource fetching is default for student-facing lists.

### 3.3 Following Feed
- `SupabaseService.getFollowingFeed(...)` uses multi-path logic:
  1. Backend `getFollowing()`
  2. ID-based follow relation fallback
  3. Email-based follow relation fallback
- Feed returns approved resources by followed uploaders.

### 3.4 Teacher/Admin Moderation Paths
- Teacher/admin in app can access moderation behavior in study flows.
- Resource moderation uses backend admin endpoint:
  - `PATCH /api/admin/resources/{resourceId}/status`
  - bearer auth with `admin_key`
- Teacher/admin syllabus upload path exists in `SupabaseService.uploadSyllabus(...)`.
- Notices posting path exists in `SupabaseService.postNotice(...)` and notices screens.

### 3.5 Chatrooms and Saved Posts
- Rooms, posts, comments, votes, reporting via backend API.
- Saved posts uses backend-first contract (`/api/chat/saved`) with Supabase schema fallbacks.
- Saved-post normalization handles multiple response key variants (`messageId`, `postId`, snake/camel variants).

### 3.6 Notices and Bookmarks
- Notice listing, detail, comments, likes, and bookmark/save flows.
- Bookmark APIs are backend-based (`/api/bookmarks...`) with local mapping for resource/notice types.

## 4. AI Features (Deep Dive)

### 4.1 AI Studio (Resource-scoped AI from PDF Viewer)

Entry point:
- `PdfViewerScreen` opens `AiStudyToolsSheet`.

Supported AI Studio actions:
- Summary
- Quiz (MCQ list)
- Flashcards
- Chat (opens `AIChatScreen` with `ResourceContext` pinned to the selected resource)

Studio API endpoints:
- `POST /api/ai/summary`
- `POST /api/ai/quiz`
- `POST /api/ai/flashcards`
- `POST /api/ai/find` (find in extracted/OCR text)

Studio request controls:
- `file_id`, `college_id`
- OCR toggles: `use_ocr`, `force_ocr`, `ocr_provider`
- regeneration/caching controls: `force`, response `cached`
- video support via `video_url`

Studio local persistence:
- `AiOutputLocalService` stores generated summary/quiz/flashcards in `SharedPreferences`.
- Per-resource, per-output-type keying.

Studio export:
- Summary can be exported as PDF and shared using `SummaryPdfService` + `share_plus`.

### 4.2 AI Chat (Cross-resource + Attachments + Actions)

Entry points:
- Standalone AI Chat from app navigation.
- AI Chat from Studio with `ResourceContext` for pinned-file chat.

AI Chat behavior highlights:
- Streams response chunks in UI.
- Maintains structured history (`role`, `content`) for context.
- Supports file attachments (`pdf`, `image`) uploaded via Cloudinary.
- Stores chat sessions locally (`AiChatLocalService`, `ChatSessionRepository`) with message metadata and source citations.
- Includes long-response notifications (`AiChatNotificationService`).

Primary AI Chat endpoint usage:
- Preferred stream route: `POST /api/rag/query/stream`
- Non-stream fallback: `POST /api/rag/query`

Important fallback behavior for stream 404/unsupported:
- If stream route returns unsupported statuses (`404`, `405`, `406`, `415`, `501`), app marks stream unavailable and automatically falls back to non-stream endpoint.
- Non-stream response is converted into a synthetic stream so UI behavior remains consistent.
- This directly addresses failures such as:
  - `RAG stream request failed (404): Route POST /api/rag/query/stream not found`

RAG request payload includes:
- `question`
- `college_id`
- `file_id` (when resource-pinned)
- `allow_web`
- OCR controls
- `attachments[]`
- `history[]`
- `filters` (semester/branch/subject from context)

Citation/source handling:
- Backend metadata chunks can include `sources[]` and `no_local`.
- UI renders source chips/cards per answer.
- Assistant text is sanitized to strip raw URL/source blocks from visible answer text when needed.

### 4.3 AI Chat Intent Actions

The app has explicit intent handling for two artifact-style flows:

1. Question paper / quiz generation
- Detects quiz/question-paper intent from prompt patterns.
- Resolves semester/branch from resource context, user profile, or dialog fallback.
- Optionally infers subject from attachments via RAG.
- Generates structured question-paper JSON.
- Applies anti-placeholder/quality checks and retry strategy.
- Stores result as `AiQuestionPaper` and shows a `Start Quiz` action.
- Opens full-screen `AiQuestionPaperQuizScreen`.

2. Summary report export
- Detects summary+file intent.
- Calls RAG with attachment context and report instruction.
- Saves result to PDF on device via `SummaryPdfService`.

### 4.4 Full-screen AI Quiz Engine

`AiQuestionPaperQuizScreen` features:
- One-question-at-a-time flow with progress bar.
- Option selection and score computation.
- "View Theory" bottom sheet using per-question source metadata.
- PDF export of full generated paper + answer/explanation/source lines.

### 4.5 OCR Search in Viewer

In `PdfViewerScreen`:
- Native PDF text search is attempted first.
- If no result, OCR fallback search can run via `POST /api/ai/find`.
- OCR matches are shown in a dedicated bottom sheet.

## 5. AI Scalability Expectations (100s of Documents)

Current product direction in repo docs (`AI_CHAT_MODERNIZATION_PLAN.md`):
- Explicit split:
  - AI Studio = pinned resource workflows
  - AI Chat = open assistant with memory/retrieval
- Recommended retrieval stack:
  - metadata filtering + vector + keyword + reranking
- Retrieval priority order:
  1. pinned resource
  2. turn attachments
  3. profile/campus constrained resources
  4. broader campus resources by topic
  5. internet fallback when confidence is below policy
- Structured outputs expected:
  - `sources[]` for citations
  - `actions[]` for UI actions

Internet fallback expectation:
- App already sends `allow_web: true` for normal chat.
- Backend should return explicit source metadata when web fallback is used.
- Client supports `no_local` metadata to indicate local corpus miss.

## 6. n8n Integration Boundary (Important)

Per `N8N_AI_AUTOMATION_IMPLEMENTATION_GUIDE.md`:
- Good for:
  - async ingestion
  - long-running quiz/report artifact workflows
  - notifications and housekeeping
- Not good for:
  - per-token live streaming chat
  - primary low-latency retrieval ranking in active chat

Recommended operating model:
- Backend handles live RAG chat and streaming.
- n8n handles async jobs and callbacks.

## 7. API Surface Used by Mobile (High-impact routes)

AI routes:
- `POST /api/ai/summary`
- `POST /api/ai/quiz`
- `POST /api/ai/flashcards`
- `POST /api/ai/find`
- `POST /api/rag/query`
- `POST /api/rag/query/stream`

Resource/moderation routes:
- `POST /api/resources`
- `POST /api/votes`
- `PATCH /api/admin/resources/{id}/status`

Notices routes:
- `GET /api/notices`
- `GET/POST/DELETE /api/notices/{id}/comments`
- `POST /api/notices/{id}/like`

Social/follow routes:
- `POST /api/follow/request`
- `GET /api/follow/status/{email}`
- `GET /api/follow/followers`
- `GET /api/follow/following`
- `POST /api/follow/approve/{requestId}`
- `POST /api/follow/reject/{requestId}`

Chat/saved routes:
- `POST /api/chat/messages`
- `POST /api/chat/comments`
- `PUT /api/chat/messages/{id}/vote`
- `POST /api/chat/saved`
- `GET /api/chat/saved`

Bookmarks routes:
- `GET /api/bookmarks`
- `POST /api/bookmarks`
- `DELETE /api/bookmarks/item/{itemId}`
- `GET /api/bookmarks/check/{itemId}`

## 8. Teacher/Admin Mapping from Dashboard Context

Based on `<repo-root>/admin-studyspace` docs and code:
- Admin dashboard supports resource moderation, notice management, syllabus upload, and user moderation.
- Mobile app role logic treats users with `admin_key` as teacher-capable in many flows.
- Mobile moderation endpoint aligns with dashboard/admin path style (`/api/admin/resources/.../status`).
- Teacher-facing expectations in mobile should mirror dashboard capabilities:
  - approve/reject/retract resources
  - post notices
  - upload syllabus

## 9. Operational Notes

Configuration:
- Backend URL and fallback URLs are environment-configurable through dart defines.
- Supabase and other keys should be injected via secure env configuration.

Observability targets recommended in AI modernization plan:
- stage timings (intent/retrieve/rerank/generate)
- fallback rate
- citation coverage
- quiz parse success
- no-local-hit and web-fallback rates

## 10. AI Health Checklist (Quick Regression)

After backend deployment, validate these in app:
1. Open AI Chat and ask normal question; confirm answer appears and citations render when available.
2. Simulate stream endpoint missing; confirm automatic fallback to `/api/rag/query` still returns answer.
3. Send message with PDF/image attachment; verify upload + OCR-assisted response path.
4. Request question paper generation; verify "Start Quiz" button opens full-screen quiz.
5. Request summary report export; verify PDF is saved on device.
6. Open PDF viewer search and test OCR fallback (`/api/ai/find`) on no-native-hit query.
7. In AI Studio, generate summary/quiz/flashcards and verify local save/load of generated outputs.

## 11. Relevant Source Files

AI and viewer:
- `flutter_application_1/lib/screens/ai_chat_screen.dart`
- `flutter_application_1/lib/widgets/ai_study_tools_sheet.dart`
- `flutter_application_1/lib/screens/viewer/pdf_viewer_screen.dart`
- `flutter_application_1/lib/screens/ai_question_paper_quiz_screen.dart`
- `flutter_application_1/lib/models/ai_question_paper.dart`
- `flutter_application_1/lib/widgets/kinetic_dots_loader.dart`

Data/services:
- `flutter_application_1/lib/services/backend_api_service.dart`
- `flutter_application_1/lib/services/supabase_service.dart`
- `flutter_application_1/lib/services/ai_output_local_service.dart`
- `flutter_application_1/lib/services/ai_chat_local_service.dart`
- `flutter_application_1/lib/services/chat_session_repository.dart`
- `flutter_application_1/lib/config/app_config.dart`

Roles/profile:
- `flutter_application_1/lib/models/user.dart`
- `flutter_application_1/lib/screens/study/study_screen.dart`

Project docs used:
- `FEATURE_DOCUMENTATION.md`
- `AI_CHAT_MODERNIZATION_PLAN.md`
- `N8N_AI_AUTOMATION_IMPLEMENTATION_GUIDE.md`
- `<repo-root>/admin-studyspace/PRD.md`
- `<repo-root>/admin-studyspace/TRD.md`


