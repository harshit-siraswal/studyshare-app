# KIET Attendance Integration Documentation

## 1. Purpose

This document defines how to integrate the KIET attendance feature set from the original `AmanDevelops/attendance-kiet` project into MyStudySpace at `D:\StudyspaceProjects\mystudyspace-app`.

This is an implementation-grade integration specification, not a marketing overview. It covers:

- analysis of the original GitHub repository first
- mapping to the current MyStudySpace Flutter architecture
- all attendance feature requirements from the source project
- a new low-attendance notification feature for subjects below 75%
- AI access to attendance data inside the existing MyStudySpace AI system
- required frontend, backend, and Supabase changes
- rollout, risk, and testing strategy

## 2. Executive Summary

The original KIET attendance project is a standalone React + Vite client that reads a KIET CyberVidya authentication token via a browser extension, then calls CyberVidya APIs directly from the client to show attendance and schedule data.

MyStudySpace is a Flutter application with these relevant properties:

- college-aware application flow via `collegeId`
- Firebase auth and a custom backend API layer
- Supabase-backed college-scoped data
- existing generic notifications, push notifications, local notifications, and app badges
- an existing AI chat feature that already consumes backend and local context

Because of that difference, MyStudySpace should not embed the original repository as-is. The correct approach is:

1. Reimplement the feature set as a KIET-specific module inside the Flutter app.
2. Replace the browser-extension token model with a mobile- and backend-compatible auth bridge.
3. Persist normalized attendance snapshots in MyStudySpace-owned storage.
4. Reuse the existing backend API, notification infrastructure, and AI entry points.

## 3. Analysis of the Original Repository

Repository analyzed: `https://github.com/AmanDevelops/attendance-kiet`

### 3.1 Technology Stack

The original repository is a standalone web app with:

- React
- TypeScript
- Vite
- Tailwind CSS
- `js-cookie`
- `axios`
- a Chrome/Firefox browser extension for token capture

Observed characteristics:

- single-page client app
- no server-side attendance proxy in the repo
- direct browser requests to CyberVidya endpoints
- token persisted in cookies
- separate extension packaging under `extension/chrome` and `extension/firefox`

### 3.2 Source Features Present in the Original Repo

The original repo currently provides these user-facing features:

1. ERP sign-in handoff using a browser extension.
2. Session token capture from CyberVidya local storage.
3. Session restoration using URL `token` query param.
4. Overall attendance summary.
5. Subject-wise and component-wise attendance cards.
6. Daywise attendance drilldown modal.
7. Student profile header with branch, semester, section, and registration number.
8. Weekly attendance projection based on upcoming schedule.
9. Calendar export to ICS using class schedule data.
10. Logout and session reset.
11. Extension installation guidance for Chrome, Firefox, and Android Firefox Nightly.
12. Terms/disclaimer screens.

### 3.3 Technical Flow in the Original Repo

The original app performs the following flow:

1. User opens the attendance app.
2. App checks for the injected extension marker in the DOM.
3. User is redirected to `https://kiet.cybervidya.net/`.
4. Extension runs on the ERP page.
5. On `/home`, extension reads `authenticationtoken` from browser local storage.
6. Extension redirects back to the app origin with `?token=...`.
7. App stores token in cookies and fetches attendance data.

This is implemented through the browser extension content scripts and client-side URL token handling.

### 3.4 CyberVidya Endpoints Used by the Original Repo

The repository directly calls these CyberVidya endpoints:

1. `GET https://kiet.cybervidya.net/api/attendance/course/component/student`
   - fetches student attendance summary and course/component attendance

2. `GET https://kiet.cybervidya.net/api/student/dashboard/registered-courses`
   - used to fetch `studentId`

3. `POST https://kiet.cybervidya.net/api/attendance/schedule/student/course/attendance/percentage`
   - fetches daywise lecture attendance for a selected course component

4. `GET https://kiet.cybervidya.net/api/student/schedule/class`
   - fetches schedule data used by projection and ICS export

All requests use the header:

`Authorization: GlobalEducation <token>`

### 3.5 Source Data Model from the Original Repo

Important source structures include:

- `StudentDetails`
  - `fullName`
  - `registrationNumber`
  - `sectionName`
  - `branchShortName`
  - `degreeName`
  - `semesterName`
  - `attendanceCourseComponentInfoList`

- `CourseAttendanceInfo`
  - `courseName`
  - `courseCode`
  - `courseId`
  - `attendanceCourseComponentNameInfoList`

- `AttendanceComponentInfo`
  - `courseComponentId`
  - `componentName`
  - `numberOfPeriods`
  - `numberOfPresent`
  - `numberOfExtraAttendance`
  - `presentPercentage`
  - `presentPercentageWith`
  - `isProjected`

- daywise lecture rows
- schedule entries for classes and holidays

### 3.6 Strengths of the Original Repo

- solves KIET attendance visibility well
- simple user flow for web users with extension installed
- covers both attendance and schedule-based planning
- gives enough raw data for meaningful AI summarization later
- already uses the 75% attendance threshold in UI logic

### 3.7 Limitations and Risks of the Original Repo

The original repository cannot be integrated directly into MyStudySpace without redesign because:

1. It is browser-extension dependent.
2. It assumes a web browser environment and DOM marker injection.
3. It stores token client-side in cookies.
4. It directly calls third-party APIs from the client.
5. It is a standalone web shell, not a reusable feature module.
6. It includes repo-specific branding, legal text, and extension instructions that do not map cleanly to Flutter mobile flows.
7. The token handoff via URL query parameter is not appropriate as the long-term transport in MyStudySpace.

### 3.8 Integration Conclusion from the Original Repo Analysis

The original repository should be treated as a feature blueprint and API behavior reference, not as code to embed.

The correct deliverable for MyStudySpace is:

- a KIET attendance feature module implemented natively in Flutter
- a backend-controlled ERP auth bridge
- normalized attendance storage in MyStudySpace infrastructure
- AI and notification integration built on top of the persisted attendance snapshot

## 4. Current MyStudySpace Architecture Relevant to This Feature

The current app is a Flutter application located under:

- `flutter_application_1/`

Verified implementation touchpoints:

- `flutter_application_1/lib/main.dart`
  - app bootstrap
  - Firebase init
  - push notification setup
  - deep-link handling

- `flutter_application_1/lib/screens/auth/college_selection_screen.dart`
  - college selection entry

- `flutter_application_1/lib/models/college.dart`
  - college identity model with `id`, `name`, and `domain`

- `flutter_application_1/lib/screens/home/home_screen.dart`
  - main bottom navigation shell
  - injects `collegeId`, `collegeName`, and `collegeDomain` into screens

- `flutter_application_1/lib/screens/study/study_screen.dart`
  - central college-scoped academic hub
  - already owns notifications badge count and AI entry point

- `flutter_application_1/lib/services/backend_api_service.dart`
  - backend-authenticated API client
  - already owns notifications and AI/RAG-related calls

- `flutter_application_1/lib/services/supabase_service.dart`
  - college-scoped data and resource access
  - already exposes notifications and college data access patterns

- `flutter_application_1/lib/services/push_notification_service.dart`
  - FCM token lifecycle
  - foreground system notification handling

- `flutter_application_1/lib/services/ai_chat_notification_service.dart`
  - local notification channel for AI chat completion events

- `flutter_application_1/lib/services/timer_notification_service.dart`
  - persistent local-notification example already in app

- `flutter_application_1/lib/screens/ai_chat_screen.dart`
  - current AI chat experience
  - already supports college-aware AI entry

- `flutter_application_1/lib/models/notification_model.dart`
  - notification record shape with `type`, `data`, and `actionUrl`

### 4.1 Important Architectural Observations

1. The app already scopes content using `collegeId`.
2. The Study screen is the best current entry point for a KIET-only academic feature.
3. Generic notifications already exist and can be extended with a new attendance type.
4. AI chat already exists and should consume attendance context through backend APIs, not by scraping the client state.
5. The app already has both FCM and local-notification patterns available.

## 5. Product Goal for MyStudySpace

For users whose selected college is KIET, MyStudySpace should provide a secure attendance module that supports:

1. KIET ERP authentication handoff.
2. Attendance sync from CyberVidya.
3. Subject-wise attendance dashboard.
4. Daywise attendance drilldown.
5. Weekly attendance projection.
6. Calendar export.
7. Automatic low-attendance alerts for any subject below 75%.
8. AI access to attendance data for personalized academic guidance.

For non-KIET colleges, the module should remain hidden or show a feature-unavailable state.

## 6. Recommended Integration Strategy

## 6.1 High-Level Product Positioning

Do not add this as a separate app inside MyStudySpace.

Instead, add it as a KIET-only feature under the college-scoped Study experience.

Recommended UX:

1. Show a KIET Attendance card or hero action inside `StudyScreen` when `collegeId` maps to KIET.
2. Open a dedicated `KietAttendanceScreen` from there.
3. Persist synced attendance in MyStudySpace backend and Supabase.
4. Feed low-attendance states into the existing notification center and app badge system.
5. Feed attendance insights into the existing AI chat system.

### 6.2 Why `StudyScreen` Is the Best Entry Point

`StudyScreen` already:

- operates in college context
- shows AI entry points
- uses notification counts and academic resources
- is the strongest conceptual fit for attendance, syllabus, and study planning

This avoids adding a new bottom tab or fragmenting the navigation model in `HomeScreen`.

## 7. Detailed Feature Scope for MyStudySpace

This section lists the full source feature set plus required MyStudySpace additions.

### 7.1 Feature A: KIET ERP Auth Bridge

MyStudySpace must support ERP login and attendance sync without copying the original browser-extension flow directly.

Required capability:

- initiate KIET ERP authentication from the app
- retrieve a valid CyberVidya session or token via a MyStudySpace-controlled bridge
- strip credentials from the app client as early as possible

Recommended implementation:

1. Preferred path:
   - backend-managed auth bridge using a secure WebView or external browser handoff
   - backend exchanges session information and returns a short-lived MyStudySpace attendance session id

2. Fallback path for web only:
   - browser extension support can be added later for Flutter web, but should not be the primary integration path

Do not:

- persist raw CyberVidya token indefinitely in Flutter preferences
- expose the token to AI services
- rely on query-string token transport as the long-term design

### 7.2 Feature B: Attendance Dashboard

Replicate these core views from the source repo:

1. Student profile header
2. Overall attendance percentage
3. Subject list
4. Component-level attendance if multiple components exist
5. threshold-aware highlighting around 75%

Additional MyStudySpace improvements:

- college-consistent design system
- pull-to-refresh sync
- last synced timestamp
- offline cached last snapshot

### 7.3 Feature C: Daywise Attendance Drilldown

For any subject/component, user should be able to see lecture-by-lecture attendance:

- lecture date
- day name
- time slot
- attendance state: present, absent, adjusted

Recommended UI:

- modal sheet or full screen drilldown in Flutter
- filter by recent 30 days or full semester

### 7.4 Feature D: Weekly Attendance Projection

Bring over the source repo's projection concept:

- fetch class schedule
- allow user to mark future classes they may miss
- show projected attendance effect at subject level

Additional MyStudySpace enhancements:

- show subject risk labels: Safe, Warning, Critical
- allow AI to explain projection impact in natural language

### 7.5 Feature E: Calendar Export

Support class schedule export to ICS or calendar integration.

Implementation options:

1. Generate ICS on device in Flutter and share it.
2. Generate ICS via backend and return file.

Minimum requirements:

- export current semester schedule
- include subject, component, faculty, room, and time where available

### 7.6 Feature F: Attendance Sync and Refresh

Users should be able to:

- manually refresh attendance
- auto-refresh on opening the attendance dashboard if data is stale
- recover the last successful snapshot if KIET ERP is temporarily unavailable

### 7.7 Feature G: Low Attendance Notifications Below 75%

This is a new MyStudySpace requirement and must be first-class.

Required behavior:

1. When any subject percentage drops below 75%, trigger an attendance alert.
2. User sees this in:
   - in-app notifications list
   - local notification on device
   - push notification if enabled
3. Duplicate spam must be prevented.
4. If the subject recovers above 75%, future drops can alert again.

Alert examples:

- `Attendance warning: Data Structures is at 72.4%`
- `Critical attendance: Physics Lab is at 63.0%`

### 7.8 Feature H: AI Access to Attendance Data

This is a required expansion beyond the original repo.

The AI should be able to answer questions such as:

- Which subjects are below 75%?
- How many classes can I miss in each subject?
- Which subjects are most at risk this week?
- Summarize my attendance status in simple language.
- Create a recovery plan for low-attendance subjects.
- Compare present attendance with projected attendance.

AI must only access normalized attendance snapshots stored in MyStudySpace systems. It must not access raw CyberVidya credentials or live ERP tokens.

## 8. Proposed UX in MyStudySpace

### 8.1 Entry Placement

Recommended placement:

- inside `StudyScreen` for KIET users only

Recommended entry card:

- title: `KIET Attendance`
- subtitle: `Sync attendance, track risk, and get AI guidance`
- actions:
  - `Open Dashboard`
  - `Sync Now`
  - `Ask AI`

### 8.2 KIET-Only Visibility Rules

Show attendance module only when selected college is KIET.

Visibility rule:

- compare current `collegeId` or `college.domain` to the KIET mapping stored in the colleges table

### 8.3 Screen Structure Recommendation

Recommended new screen tree:

1. `KietAttendanceScreen`
   - summary card
   - sync status banner
   - low-attendance warnings
   - subjects list

2. `KietAttendanceDetailsScreen`
   - per subject view
   - components
   - daywise drilldown

3. `KietAttendanceProjectionScreen`
   - upcoming schedule
   - missed-class scenario planning

4. `KietAttendanceSettingsSheet`
   - notification preferences
   - sync frequency
   - disconnect ERP session

## 9. Recommended Technical Architecture

## 9.1 New Flutter Layering

Add a dedicated attendance feature set under Flutter app code, for example:

- `lib/models/attendance_snapshot.dart`
- `lib/models/attendance_subject.dart`
- `lib/models/attendance_alert.dart`
- `lib/services/attendance_service.dart`
- `lib/services/attendance_alert_service.dart`
- `lib/screens/attendance/kiet_attendance_screen.dart`
- `lib/screens/attendance/kiet_attendance_detail_screen.dart`
- `lib/screens/attendance/kiet_attendance_projection_screen.dart`
- `lib/widgets/attendance/...`

### 9.2 New Backend Responsibilities

Add backend endpoints under the existing backend service instead of calling CyberVidya directly from Flutter.

Recommended backend endpoints:

1. `POST /api/attendance/kiet/auth/start`
   - starts the ERP auth bridge flow

2. `POST /api/attendance/kiet/auth/complete`
   - completes bridge and issues MyStudySpace attendance session

3. `POST /api/attendance/kiet/sync`
   - pulls latest data from CyberVidya and persists normalized snapshot

4. `GET /api/attendance/kiet/summary`
   - returns latest normalized attendance summary for current user

5. `GET /api/attendance/kiet/subjects/:subjectId/daywise`
   - returns lecture-level attendance history

6. `GET /api/attendance/kiet/schedule`
   - returns normalized upcoming schedule for projection and calendar export

7. `GET /api/attendance/kiet/alerts`
   - returns low-attendance alert records

8. `POST /api/attendance/kiet/alerts/read`
   - marks alerts as read

9. `GET /api/attendance/kiet/ai-context`
   - returns compact, normalized attendance context for AI chat

### 9.3 Why Backend Mediation Is Required

Backend mediation is strongly recommended because:

- Flutter mobile cannot depend on the browser extension model
- ERP token handling must be isolated from the client
- AI should use normalized data, not raw ERP responses
- notification generation is easier when attendance snapshots are stored server-side

## 10. Proposed Data Model

Use Supabase for canonical attendance persistence after sync.

### 10.1 New Tables

#### `attendance_accounts`

Purpose:

- links a MyStudySpace user to a KIET attendance identity

Suggested columns:

- `id`
- `user_id`
- `college_id`
- `provider` = `kiet_cybervidya`
- `erp_student_id`
- `registration_number`
- `full_name`
- `branch_code`
- `section_name`
- `semester_name`
- `is_connected`
- `last_synced_at`
- `last_sync_status`
- `last_sync_error`
- `created_at`
- `updated_at`

#### `attendance_snapshots`

Purpose:

- stores snapshot-level sync metadata

Suggested columns:

- `id`
- `attendance_account_id`
- `snapshot_time`
- `overall_percentage`
- `raw_payload_json`
- `sync_source`
- `created_at`

#### `attendance_subjects`

Purpose:

- normalized subject attendance for each snapshot

Suggested columns:

- `id`
- `snapshot_id`
- `course_id`
- `course_code`
- `course_name`
- `component_id`
- `component_name`
- `total_periods`
- `present_periods`
- `extra_attendance`
- `percentage`
- `threshold_status`
- `created_at`

#### `attendance_lectures`

Purpose:

- daywise lecture-level records

Suggested columns:

- `id`
- `attendance_subject_id`
- `lecture_date`
- `day_name`
- `time_slot`
- `attendance_status`
- `created_at`

#### `attendance_schedule_entries`

Purpose:

- schedule entries for projection and calendar export

Suggested columns:

- `id`
- `attendance_account_id`
- `external_schedule_id`
- `course_code`
- `course_name`
- `component_name`
- `faculty_name`
- `class_room`
- `entry_type`
- `lecture_date`
- `start_time`
- `end_time`
- `created_at`

#### `attendance_alerts`

Purpose:

- stores low-attendance alert lifecycle

Suggested columns:

- `id`
- `attendance_account_id`
- `subject_key`
- `course_name`
- `component_name`
- `percentage`
- `threshold_value`
- `severity`
- `status`
- `first_triggered_at`
- `last_triggered_at`
- `resolved_at`
- `notification_record_id`
- `created_at`
- `updated_at`

### 10.2 Reuse of Existing Notification Model

Existing notification records already support:

- `type`
- `title`
- `message`
- `data`
- `actionUrl`

Add a new notification type:

- `attendance_low`

Suggested notification payload:

```json
{
  "type": "attendance_low",
  "title": "Attendance warning",
  "message": "Data Structures is at 72.4%",
  "data": {
    "attendanceAccountId": "...",
    "courseId": 123,
    "courseName": "Data Structures",
    "componentId": 456,
    "componentName": "Theory",
    "percentage": 72.4,
    "threshold": 75,
    "severity": "warning"
  },
  "actionUrl": "/attendance/kiet?subject=123"
}
```

## 11. Notification Design for Below-75% Alerts

## 11.1 Alert Rule

An alert must trigger when:

- `percentage < 75.0`

Severity recommendation:

- `warning` for `70.0 <= percentage < 75.0`
- `critical` for `percentage < 70.0`

### 11.2 Trigger Points

Run alert evaluation on:

1. every successful attendance sync
2. app open if last snapshot is stale and a refresh occurs
3. optional scheduled backend sync job

### 11.3 De-duplication Rules

Avoid duplicate notifications by using `attendance_alerts` state.

Suggested logic:

1. If subject crosses from `>= 75` to `< 75`, create alert and notify.
2. If subject remains `< 75` and last alert is recent, do not notify again.
3. If subject recovers to `>= 75`, mark alert resolved.
4. If subject later drops below 75 again, create a new alert cycle.

### 11.4 Delivery Channels

Use all three existing channels:

1. In-app notification center
   - surfaced through existing notifications UI

2. Local device notification
   - can reuse patterns from `push_notification_service.dart` and `ai_chat_notification_service.dart`

3. Push notification
   - use FCM where user has notifications enabled

### 11.5 User Preferences

Add attendance-specific notification settings:

- enable/disable attendance alerts
- critical-only mode
- quiet hours
- digest vs immediate mode

Store settings per user.

## 12. AI Access Design

## 12.1 Design Principle

AI should consume attendance as structured app-owned data, not by querying CyberVidya directly.

### 12.2 Data Made Available to AI

AI context should include:

- latest overall percentage
- all subjects with current percentages
- below-threshold subjects
- recent trend if snapshots over time are stored
- upcoming classes for projection
- computed risk signals such as `classes_needed_to_reach_75`

### 12.3 Recommended AI Context Endpoint

Add:

- `GET /api/attendance/kiet/ai-context`

Example response:

```json
{
  "collegeId": "kiet",
  "lastSyncedAt": "2026-03-12T10:30:00Z",
  "overallPercentage": 78.2,
  "subjects": [
    {
      "courseName": "Data Structures",
      "componentName": "Theory",
      "percentage": 72.4,
      "belowThreshold": true,
      "classesNeededFor75": 3
    }
  ],
  "projection": {
    "atRiskThisWeek": ["Data Structures"]
  }
}
```

### 12.4 AI Chat Integration Strategy

Use the existing AI stack in `ai_chat_screen.dart` and the current backend API layer.

Recommended behaviors:

1. Add a quick action in attendance UI: `Ask AI about my attendance`.
2. Launch AI chat with pre-attached attendance context.
3. Backend AI layer injects attendance context into prompt construction.
4. AI answers should be scoped to the current user and latest synced snapshot.

### 12.5 AI Use Cases to Support

1. Low-attendance explanation.
2. Subject prioritization.
3. Bunk planning and safe-miss analysis.
4. Weekly recovery plan.
5. Exam strategy prioritization based on low attendance and subject load.

### 12.6 AI Guardrails

Do not allow AI to:

- expose raw ERP token or auth bridge secrets
- claim real-time data when only cached snapshot exists
- operate across other users' attendance data
- infer attendance for unsupported colleges

## 13. Recommended File-Level Integration Plan

This section maps the feature to the current codebase.

### 13.1 Flutter App Changes

#### Existing files to update

1. `flutter_application_1/lib/screens/study/study_screen.dart`
   - add KIET Attendance entry card
   - add unread attendance-risk banner/count if desired
   - add navigation to attendance screen

2. `flutter_application_1/lib/screens/home/home_screen.dart`
   - no major nav restructure required
   - only update if global deep links to attendance need registration

3. `flutter_application_1/lib/services/backend_api_service.dart`
   - add attendance endpoints
   - add alert read/update APIs
   - add AI attendance context API

4. `flutter_application_1/lib/services/supabase_service.dart`
   - add attendance snapshot reads if app needs direct Supabase fetches
   - add attendance alert notification reads if backend does not fully abstract them

5. `flutter_application_1/lib/services/push_notification_service.dart`
   - support `attendance_low` payload routing

6. `flutter_application_1/lib/models/notification_model.dart`
   - add typed parsing helpers if needed for attendance-specific payloads

7. `flutter_application_1/lib/screens/notifications/notification_screen.dart`
   - render attendance alert cards with deep link to attendance dashboard

8. `flutter_application_1/lib/screens/ai_chat_screen.dart`
   - add attendance quick prompts or prefilled context entry points

#### New files to add

1. `flutter_application_1/lib/models/attendance_snapshot.dart`
2. `flutter_application_1/lib/models/attendance_subject.dart`
3. `flutter_application_1/lib/models/attendance_lecture.dart`
4. `flutter_application_1/lib/models/attendance_alert.dart`
5. `flutter_application_1/lib/services/attendance_service.dart`
6. `flutter_application_1/lib/services/attendance_alert_service.dart`
7. `flutter_application_1/lib/screens/attendance/kiet_attendance_screen.dart`
8. `flutter_application_1/lib/screens/attendance/kiet_attendance_detail_screen.dart`
9. `flutter_application_1/lib/screens/attendance/kiet_attendance_projection_screen.dart`
10. `flutter_application_1/lib/widgets/attendance/...`

### 13.2 Backend Changes

In `studyspace-backend`, add:

- attendance auth bridge endpoints
- attendance sync worker/service
- normalized data persistence
- alert generator
- AI attendance context endpoint

Recommended backend modules:

- `src/modules/attendance/`
  - `attendance.controller.ts`
  - `attendance.service.ts`
  - `attendance.sync.service.ts`
  - `attendance.alerts.service.ts`
  - `attendance.ai-context.service.ts`

### 13.3 Supabase Changes

Add migrations for:

- attendance account linkage
- snapshot storage
- subject rows
- lecture rows
- schedule rows
- alerts state

Recommended RLS principle:

- user can read only their own attendance records
- backend service role performs sync writes
- AI context endpoint reads only current authenticated user's attendance data

## 14. Implementation Sequence

### Phase 1: Foundation

1. Define KIET college mapping in existing colleges data.
2. Create new attendance tables and policies.
3. Add backend API contracts.
4. Add Flutter models and service stubs.

### Phase 2: Sync and Summary

1. Implement auth bridge.
2. Implement backend sync.
3. Build attendance dashboard in Flutter.
4. Add manual refresh and last-sync status.

### Phase 3: Deep Features

1. Add daywise drilldown.
2. Add schedule and projection.
3. Add calendar export.

### Phase 4: Notifications

1. Create low-attendance alert evaluator.
2. Add notification records.
3. Add local notification routing.
4. Add FCM push support.
5. Add notification settings UI.

### Phase 5: AI Integration

1. Expose attendance AI context endpoint.
2. Add AI quick actions from attendance screen.
3. Add attendance-aware prompts and responses.

## 15. Security and Privacy Requirements

These requirements are mandatory.

1. Do not store KIET ERP password in MyStudySpace.
2. Do not expose raw CyberVidya token to AI or notification payloads.
3. Do not rely on long-lived client storage of ERP tokens.
4. Remove or rotate attendance session artifacts aggressively.
5. Store only normalized attendance snapshots needed for app features.
6. Clearly disclose that attendance data is fetched from KIET CyberVidya.
7. Allow user to disconnect attendance integration and delete link state.

## 16. Edge Cases and Failure Handling

Handle these scenarios explicitly:

1. ERP session expired during sync.
2. KIET API unavailable.
3. Student has no attendance for a subject yet.
4. Schedule endpoint returns empty.
5. Duplicate subject components.
6. User changes college away from KIET.
7. Multiple devices with same user.
8. Offline app startup after prior successful sync.

Recommended UX:

- show last successful snapshot if live sync fails
- surface `last synced` time
- show `Reconnect ERP` if bridge session expires

## 17. QA Checklist

### Functional

1. KIET-only visibility works.
2. Auth bridge connects successfully.
3. Attendance sync returns correct student profile and subject data.
4. Daywise view matches server data.
5. Projection updates correctly when classes are marked as missed.
6. Calendar export generates valid ICS.
7. Logout/disconnect clears attendance session.

### Notification

1. A new below-75 subject triggers one alert.
2. Reopening the app does not duplicate the same unresolved alert.
3. Recovering above 75 resolves the alert state.
4. Dropping below 75 again triggers a new alert cycle.
5. In-app notification opens the attendance screen.
6. Push notification opens the correct deep link.

### AI

1. AI can summarize current attendance.
2. AI can list below-threshold subjects.
3. AI can answer `how many classes can I miss` based on stored snapshot logic.
4. AI never exposes raw tokens or unsupported private fields.

## 18. Suggested Acceptance Criteria

The KIET attendance integration is complete when:

1. KIET users can connect ERP and sync attendance inside MyStudySpace.
2. Users can view subject-wise, component-wise, and daywise attendance.
3. Users can run weekly projections and export schedule to calendar.
4. Low-attendance alerts appear for any subject below 75%.
5. Attendance alerts are visible in the notification center and via device notifications.
6. AI can answer attendance-aware questions from normalized stored data.
7. No raw ERP password is stored, and raw token exposure is minimized.

## 19. Final Recommendation

Implement this as a KIET-specific academic feature under the existing Study experience, backed by MyStudySpace-controlled sync, storage, notifications, and AI context.

Do not port the original browser-extension architecture directly.

Reuse from the original repo:

- feature behavior
- endpoint semantics
- data shape understanding
- projection and calendar concepts

Do not reuse directly:

- standalone React shell
- browser extension dependency as the primary path
- cookie-based token ownership model
- source branding or repo-specific legal copy

This approach gives MyStudySpace a durable, mobile-compatible, AI-ready, and notification-aware attendance feature while preserving the value of the original attendance project.