# Components

## `flutter_application_1/lib/widgets/ai_logo.dart`
- Component: `AiLogo`
- Description: Animated StudyShare AI mark used in chat headers and AI identity surfaces.

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';

// Public API excerpt only. See flutter_application_1/lib/widgets/ai_logo.dart
// for the full _AiLogoState animation controller, paint, and transform logic.
class AiLogo extends StatefulWidget {
  final double size;
  final bool animate;

  const AiLogo({
    super.key,
    this.size = 40,
    this.animate = true,
  });

  @override
  State<AiLogo> createState() => _AiLogoState();
}

class _AiLogoState extends State<AiLogo> with SingleTickerProviderStateMixin {
  // Excerpt: full implementation intentionally omitted here.
}
```

## `flutter_application_1/lib/widgets/study_ai_live_activity_card.dart`
- Component: `StudyAiLiveActivityCard`
- Description: Live AI action surface that shows current assistant work, sources, and export readiness.

```dart
import 'package:flutter/material.dart';

import '../models/study_ai_live_activity.dart';

class StudyAiLiveActivityCard extends StatelessWidget {
  final String title;
  final List<AiLiveActivityStep> steps;
  final AiAnswerOrigin? answerOrigin;
  final bool isRunning;
  final bool showExport;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;
  final VoidCallback? onExport;

  const StudyAiLiveActivityCard({
    super.key,
    required this.title,
    required this.steps,
    this.answerOrigin,
    this.isRunning = false,
    this.showExport = false,
    this.onOpenPdf,
    this.onOpenUrl,
    this.onOpenVideo,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = isRunning ? 'Running' : 'Idle';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Text('Status: $statusText'),
            Text('Steps: ${steps.length}'),
            if (answerOrigin != null) Text('Origin: ${answerOrigin!.name}'),
            if (showExport && onExport != null)
              TextButton(onPressed: onExport, child: const Text('Export')),
          ],
        ),
      ),
    );
  }
}
```
