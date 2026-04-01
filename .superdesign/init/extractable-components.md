# Extractable Components

## Categories
- `basic`: Stable, reusable UI building blocks with clear props and low coupling.
- `advanced`: Reusable components with richer behavior/state orchestration and broader integration surface.
- `experimental`: Components still evolving; extract only when a design flow explicitly needs them.

## StudyAiLiveActivityCard
- Source: `flutter_application_1/lib/widgets/study_ai_live_activity_card.dart`
- Category: basic (see [Categories](#categories))
- Description: Shows the assistant's current actions, source chips, and export readiness.
- Extraction priority: high
- Estimated effort: medium
- Prop types (implementation-aligned):
	- `title: String`
	- `steps: List<AiLiveActivityStep>`
	- `answerOrigin: AiAnswerOrigin?`
	- `isRunning: bool`
	- `showExport: bool`
	- `onOpenPdf: void Function(String fileId, int? page)?`
	- `onOpenUrl: void Function(String url)?`
	- `onOpenVideo: void Function(String url, String? timestamp)?`
	- `onExport: VoidCallback?`
- Hardcoded: StudyShare live-activity label, timeline treatment, chip styles, export CTA treatment

## AiLogo
- Source: `flutter_application_1/lib/widgets/ai_logo.dart`
- Category: basic (see [Categories](#categories))
- Description: Animated AI brand mark for assistant surfaces.
- Extraction priority: medium
- Estimated effort: large
- Extractable props:
	- `size: double`
	- `animate: bool`
- Hardcoded: StudyShare S-mark drawing logic and blue gradient treatment

### AiLogo Generalization Decision
- Chosen option: **(c) externalize brand assets to configuration**, while keeping animation behavior in `AiLogo`.
- Parameterization candidates if full generic mode is later required:
	- Path geometry/path constants for the S-mark.
	- Gradient color stops and opacity values.
	- Stroke widths and glow/highlight constants.
	- Animation timings/curves tied to current brand pulse behavior.
- Complexity assessment: **high** because geometry, gradients, and animation timing are intertwined in a custom painter-style presentation.
- Recommendation: keep current StudyShare brand visual hardcoded by default for consistency, and move brand-specific path/gradient constants to a dedicated config/asset layer only if multi-brand support becomes a roadmap requirement.
