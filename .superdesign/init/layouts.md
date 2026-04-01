# Layouts

## `flutter_application_1/lib/screens/ai_chat_screen.dart`
- Description: Full-screen AI chat experience used from study resources, AI studio, and video viewers.

```dart
// Excerpt - see flutter_application_1/lib/screens/ai_chat_screen.dart for full implementation.
class AIChatScreen extends StatefulWidget {
  final String collegeId;
  final String userEmail;
  final String? resourceContext;
  final bool embedded;
  final String? initialPrompt;

  const AIChatScreen({
    super.key,
    required this.collegeId,
    required this.userEmail,
    this.resourceContext,
    this.embedded = false,
    this.initialPrompt,
  });
}
```

## `flutter_application_1/lib/screens/home/home_screen.dart`
- Description: Main app shell with bottom navigation and floating central action.

```dart
// Bottom navigation row excerpt
children: [
  _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
  _buildNavItem(
    1,
    Icons.chat_bubble_outline_rounded,
    Icons.chat_bubble_rounded,
    'Chats',
  ),
  _buildNavItem(2, Icons.campaign_outlined, Icons.campaign_rounded, 'Notices'),
  _buildNavItem(3, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
]
```
