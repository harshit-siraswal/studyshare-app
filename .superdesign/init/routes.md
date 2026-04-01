# Routes

## Main app entry
- File: `flutter_application_1/lib/main.dart`
- Flow: onboarding/auth/college selection -> `HomeScreen`

## AI chat entry points
- `flutter_application_1/lib/screens/study/study_screen.dart`
  - Opens `AIChatScreen` from study resources.
- `flutter_application_1/lib/widgets/ai_study_tools_sheet.dart`
  - Opens `AIChatScreen` from AI Studio.
- `flutter_application_1/lib/screens/viewer/video_player_screen.dart`
  - Embeds `AIChatScreen` beside video context.
- `flutter_application_1/lib/screens/viewer/youtube_player_screen.dart`
  - Embeds `AIChatScreen` for YouTube-linked study context.
