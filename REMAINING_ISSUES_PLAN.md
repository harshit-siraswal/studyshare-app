# Plan: Remaining Non-UI Issues

**Date:** 2026-07-12  
**Status:** Plan only — not yet implemented

---

## Issue 1: AI Chat — Notice Source Navigation

### Diagnosis

The Flutter app already has the full plumbing in place:

| Component | Location | What it does |
|---|---|---|
| `RagSource.isNoticeSource` | `ai_chat_screen.dart:143` | Returns `true` when `sourceTable == 'notices'` AND `sourceId` is non-empty |
| `_openNoticeSource(source)` | `ai_chat_screen.dart:2364` | Calls `_openNoticeById` with the source's `sourceId` |
| `_openNoticeById(id)` | `ai_chat_screen.dart:2311` | Fetches the notice via `_supabase.getNotice()`, then pushes `NoticeDetailScreen` |
| Source chip tap handler | `ai_chat_screen.dart:6689` | Calls `_openNoticeSource(s)` when `isNoticeSource == true` |

**The Flutter side is correct.** The failure point is the **backend RAG response** not including `source_table: 'notices'` and `source_id: <notice-uuid>` in its source objects.

When the RAG system retrieves a notice chunk, each source entry in the response must carry:

```json
{
  "file_id": "<chunk-file-id>",
  "source_id": "<notice-uuid>",
  "source_table": "notices",
  "notice_department": "<department-id-or-slug>",
  "title": "Notice title",
  "source_type": "notice"
}
```

Without `source_table: "notices"`, `isNoticeSource` is always `false`, the chip falls into the PDF viewer path, and fails silently (no `fileUrl` → `_showSourceUrlErrorSnackBar`).

### Fix (server-side only)

**File:** Backend RAG handler (`/api/rag/query` and `/api/rag/query/stream`)

1. When building the `sources` array from retrieved chunks, check `chunk.source_table` (or equivalent metadata column). If the chunk came from the `notices` table:
   - Set `source_table: "notices"`
   - Set `source_id: chunk.notice_id` (the UUID of the notice row)
   - Set `notice_department: chunk.department_id` (or `department_slug`)
   - Set `source_type: "notice"`

2. The streaming response's `done` event also sends `sources` — apply the same fix there.

3. No Flutter changes needed. Once the backend sends the correct metadata, tapping a notice citation will call `_openNoticeSource` → `_openNoticeById` → `NoticeDetailScreen`.

### Verification

- Ask AI a question that references a notice (e.g., "what does the exam notice say?")
- Source chip should appear with the notice title
- Tapping it opens `NoticeDetailScreen` with full notice content

---

## Issue 5: Discover Rooms — Slow Loading

### Diagnosis

`DiscoverRoomsScreen` calls `SupabaseService.getChatRooms(filter: 'discover')`.

Inside `getChatRooms`, the `'discover'` filter path goes directly to `_api.listChatRooms()` — an HTTP call to `api.studyshare.in` — skipping Supabase. The cache TTL is only **30 seconds** (`_roomListCacheTtl`).

Problems:
1. **Cold start:** Every app launch waits for the full network round-trip before showing any rooms
2. **Short cache TTL (30s):** Users see the spinner again within seconds of navigating away and back
3. **No disk persistence:** Cache is in-memory only; app restart means a full network fetch
4. **Backend query may be unindexed:** `chat_rooms` filtered by `college_id + is_private + is_active + expiry_date`

### Fix Plan

#### 4a. Stale-while-revalidate in `SupabaseService.getChatRooms` (Flutter)

**File:** `lib/services/supabase_service.dart`, method `getChatRooms`

Change the cache check to **always return stale data immediately** while refreshing in background:

```dart
// BEFORE: only returns cache if fresh
if (!forceRefresh) {
  final cached = _roomListCache[cacheKey];
  if (cached != null &&
      DateTime.now().difference(cached.cachedAt) < _roomListCacheTtl) {
    return cloneRooms(cached.data);
  }
  ...
}

// AFTER: return stale cache immediately, kick off background refresh
if (!forceRefresh) {
  final cached = _roomListCache[cacheKey];
  if (cached != null) {
    // Return stale data immediately; refresh in background
    if (DateTime.now().difference(cached.cachedAt) >= _roomListCacheTtl) {
      unawaited(_refreshRoomListInBackground(cacheKey, fetchRooms));
    }
    return cloneRooms(cached.data);
  }
}
```

Add `_refreshRoomListInBackground` private method that updates the cache and calls a `ValueNotifier` so the discover screen can react.

#### 4b. Disk-persist room list via AppCache

After every successful fetch, write to `AppCache.putJson('rooms:$cacheKey', rooms)` (same pattern as the user profile cache). On cold start, load from disk before awaiting the network.

**File:** `lib/services/supabase_service.dart`

```dart
// On startup / first fetch: try disk cache
final diskData = await AppCache.getJson('rooms:$cacheKey');
if (diskData != null) {
  _roomListCache[cacheKey] = (cachedAt: ..., data: diskData);
}
```

#### 4c. Increase in-memory cache TTL

Change `_roomListCacheTtl` from 30 seconds to **5 minutes**. Discover rooms don't change that often.

```dart
// supabase_service.dart line 42
static const Duration _roomListCacheTtl = Duration(minutes: 5); // was 30s
```

#### 4d. Backend — DB index (server-side)

On the PostgreSQL database, add a composite index if not already present:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chat_rooms_discover
  ON chat_rooms (college_id, is_private, is_active, expiry_date)
  WHERE is_private = false AND is_active = true;
```

This makes the `listChatRooms?filter=discover&college_id=X` query a fast index scan instead of a full table scan.

### Expected Result

- App opens → shimmer shows for < 200ms (disk cache hit) then rooms appear
- Background refresh updates list silently
- Navigate away and back → instant (5-min in-memory cache)
- First-ever load (no disk cache): only then does the full spinner show

---

## Non-UI: PDF Upload Automation Pipeline

### Architecture Overview

```
User uploads PDF
      │
      ▼
Supabase Storage (via /api/resources/upload-url)
      │
      ▼ (Supabase webhook → n8n)
n8n Workflow: "PDF Processing Pipeline"
      │
      ├─── Step 1: OCR Extraction
      │         POST api.studyshare.in/api/internal/ocr
      │         Body: { resource_id, file_url }
      │         Auth: OCR_INTERNAL_API_KEY header
      │         Returns: { extracted_text, ocr_errors }
      │
      ├─── Step 2: AI Generation (parallel)
      │         POST /api/ai/summary   → summary text
      │         POST /api/ai/quiz      → MCQ JSON
      │         POST /api/ai/flashcards → flashcard pairs
      │         Auth: INTERNAL_API_KEY header
      │         All use: { resource_id, use_ocr: true }
      │
      ├─── Step 3: Store AI Outputs
      │         Write summary/quiz/flashcards to Supabase table
      │         `resource_ai_outputs` (resource_id, type, content, created_at)
      │
      └─── Step 4: RAG Chunking + Embedding
                POST /api/internal/index-resource
                Body: { resource_id, ocr_text }
                Auth: INTERNAL_API_KEY header
                Server chunks text → embeds → inserts into pgvector table
```

### n8n Workflow to Build

**Workflow name:** `PDF Processing Pipeline`

**Trigger Node:** Supabase webhook  
- Table: `resources`  
- Event: `INSERT`  
- Filter: `file_type = 'pdf'` OR `file_url LIKE '%.pdf'`

**Node 1 — OCR:** HTTP Request node  
- Method: POST  
- URL: `{{ $env.BACKEND_URL }}/api/internal/ocr`  
- Headers: `{ "x-internal-key": "{{ $env.OCR_INTERNAL_API_KEY }}" }`  
- Body: `{ "resource_id": "{{ $json.id }}", "file_url": "{{ $json.file_url }}" }`  

**Node 2 — AI Generation (3 parallel branches using n8n's Split In Batches or parallel HTTP nodes):**
- Summary: POST `/api/ai/summary` `{ resource_id, use_ocr: true, delivery: 'sync' }`
- Quiz: POST `/api/ai/quiz` `{ resource_id, use_ocr: true }`
- Flashcards: POST `/api/ai/flashcards` `{ resource_id, use_ocr: true }`  
- All with header `x-internal-key: {{ $env.INTERNAL_API_KEY }}`

**Node 3 — Store Outputs:** Supabase node (upsert)  
- Table: `resource_ai_outputs`  
- Columns: `resource_id`, `output_type` (summary/quiz/flashcards), `content` (JSON), `generated_at`

**Node 4 — Index for RAG:** HTTP Request node  
- POST `/api/internal/index-resource`  
- Body: `{ "resource_id": "...", "ocr_text": "..." }`  
- This endpoint on the backend should: chunk the text → embed with NVIDIA NIM or similar → upsert into `resource_chunks` pgvector table

### Backend Endpoints to Add / Verify

| Endpoint | Status | Notes |
|---|---|---|
| `POST /api/internal/ocr` | Likely exists | Verify auth uses `OCR_INTERNAL_API_KEY` |
| `POST /api/ai/summary` (sync mode) | Exists | Already has `delivery: 'sync'` path |
| `POST /api/ai/quiz` | Exists | — |
| `POST /api/ai/flashcards` | Exists | — |
| `POST /api/internal/index-resource` | May need to create | Chunks text and inserts pgvector rows |

### DB Table to Create

```sql
CREATE TABLE IF NOT EXISTS resource_ai_outputs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_id UUID NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
  output_type TEXT NOT NULL CHECK (output_type IN ('summary', 'quiz', 'flashcards')),
  content JSONB NOT NULL,
  generated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (resource_id, output_type)
);

CREATE INDEX idx_resource_ai_outputs_resource ON resource_ai_outputs(resource_id);
```

### n8n Setup Steps

1. Start n8n: `cd n8n && docker compose up -d`
2. Open n8n UI (default: `http://localhost:5678`)
3. Add credentials:
   - `BACKEND_URL = https://api.studyshare.in`
   - `INTERNAL_API_KEY = <value from n8n/.env>`
   - `OCR_INTERNAL_API_KEY = <value from n8n/.env>`
   - Supabase credentials (url + service role key)
4. Build the workflow per the nodes above
5. Export workflow JSON and save to `n8n/backups/n8n_workflows_pdf_pipeline.json`
6. Test with a manual trigger (pass a real resource row)

---

## Non-UI: LLM API Key Wiring (NVIDIA + Groq)

### Current State

The Flutter app never holds or sends LLM API keys. All AI requests go to `api.studyshare.in` via `BackendApiService`. The EC2 server holds the keys in its own `.env` file (not in this repo).

### What to Verify on the Server

SSH into `api.studyshare.in` (EC2 `13.61.19.178`) and check:

```bash
grep -E 'NVIDIA|GROQ|OPENAI|LLM' /path/to/backend/.env
```

Required variables:
```
NVIDIA_API_KEY=nvapi-...        # For NIM embeddings and/or chat completions
GROQ_API_KEY=gsk_...            # For fast inference (Llama 3, Mixtral etc.)
```

### Wiring Check

Verify each AI endpoint routes to the correct provider:

| Endpoint | Recommended Provider | Reason |
|---|---|---|
| `/api/rag/query` (chat, streaming) | Groq (Llama 3 70B) | Low latency streaming |
| `/api/ai/summary` | Groq or NVIDIA NIM | Long-context output |
| `/api/ai/quiz` / `/api/ai/flashcards` | Groq | Structured JSON output, fast |
| Embedding for RAG chunks | NVIDIA NIM (`nvidia/llama-3_2-nv-embedqa-1b-v2` or similar) | High-quality embeddings |

### Rotation / Secret Management

- Keys are NOT committed to this repo (confirmed — only `n8n/.env` has internal keys, no LLM keys)
- Rotation: Update the key in the EC2 `.env` and `pm2 restart all` (or equivalent)
- No Flutter rebuild needed when keys rotate — the app only knows `API_URL`

### n8n ↔ Backend Auth

n8n calls the backend's internal endpoints using `INTERNAL_API_KEY`. The backend verifies this header on all `/api/internal/*` routes. Ensure:
- `n8n/.env`: `INTERNAL_API_KEY=<secret>` is set
- Backend `.env`: same value under `INTERNAL_API_KEY`
- `n8n/.env` note: `OCR_INTERNAL_API_KEY` is deprecated after 2026-09-30 — migrate to `INTERNAL_API_KEY` before then

---

## Summary: What Needs to Happen

| Issue | Where to fix | Effort |
|---|---|---|
| Notice source taps | Backend RAG handler — add `source_table`/`source_id` to notice chunks in response | Small |
| Discover rooms slow | Flutter `supabase_service.dart` — stale-while-revalidate + disk cache + longer TTL; DB index | Medium |
| PDF automation | Build n8n workflow + create `resource_ai_outputs` table + verify/add `/api/internal/index-resource` endpoint | Large |
| LLM API keys | SSH into EC2, verify `.env`, check routing in backend code | Small (audit only) |
