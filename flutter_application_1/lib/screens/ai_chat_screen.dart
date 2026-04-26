import 'package:collection/collection.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../config/theme.dart';
import '../models/ai_question_paper.dart';
import '../models/department_account.dart';
import '../models/resource.dart';
import '../models/study_ai_live_activity.dart';
import '../services/auth_service.dart';
import '../services/ai_chat_notification_service.dart';
import '../services/analytics_service.dart';
import '../services/backend_api_service.dart';
import '../services/ai_chat_local_service.dart';
import '../services/chat_session_repository.dart';
import '../services/summary_pdf_service.dart';
import '../services/supabase_service.dart';
import '../controllers/ai_chat_animation_controller.dart';
import '../widgets/ai_chat_message_bubble.dart';
import '../widgets/ai_loading_game_card.dart';
import '../widgets/ai_logo.dart';
import '../widgets/onboarding_overlay.dart';
import '../widgets/paywall_dialog.dart';
import '../widgets/study_ai_live_activity_card.dart';
import '../utils/ai_token_budget_utils.dart';
import '../utils/ai_question_paper_parser.dart';
import '../utils/link_navigation_utils.dart';
import 'ai_question_paper_quiz_screen.dart';
import 'notices/notice_detail_screen.dart';
import 'viewer/pdf_viewer_screen.dart';
import 'viewer/web_source_viewer_screen.dart';
import '../utils/youtube_link_utils.dart';

bool _looksLikePdfSourceUrl(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('.pdf') ||
      normalized.contains('/pdf') ||
      normalized.contains('application/pdf');
}

class RagSource {
  final String fileId;
  final String? sourceId;
  final String? sourceTable;
  final String? noticeDepartment;
  final String title;
  final String? subject;
  final String sourceType;
  final int? startPage;
  final int? endPage;
  final String? timestamp;
  final double? score;
  final String? fileUrl;
  final String? videoUrl;
  final bool isPrimary;

  RagSource({
    required this.fileId,
    this.sourceId,
    this.sourceTable,
    this.noticeDepartment,
    required this.title,
    this.subject,
    this.sourceType = 'pdf',
    this.startPage,
    this.endPage,
    this.timestamp,
    this.score,
    this.fileUrl,
    this.videoUrl,
    this.isPrimary = false,
  });

  factory RagSource.fromJson(Map<String, dynamic> json) {
    final pages = json['pages'] as Map<String, dynamic>?;
    final start = pages?['start'];
    final end = pages?['end'];
    final resolvedSubject = json['subject']?.toString().trim();
    final resolvedFileUrl =
        json['file_url']?.toString() ??
        json['source_url']?.toString() ??
        json['url']?.toString() ??
        json['href']?.toString();
    final resolvedVideoUrl =
        json['video_url']?.toString() ?? json['youtube_url']?.toString();
    final resolvedSourceId = json['source_id']?.toString().trim();
    final resolvedSourceTable = json['source_table']?.toString().trim();
    final resolvedNoticeDepartment = json['notice_department']
        ?.toString()
        .trim();
    final explicitType = json['source_type']?.toString().trim().toLowerCase();
    final inferredType = explicitType?.isNotEmpty == true
        ? explicitType!
        : ((resolvedVideoUrl?.toLowerCase().contains('youtu') ?? false) ||
                  (resolvedFileUrl?.toLowerCase().contains('youtu') ?? false)
              ? 'youtube'
              : ((resolvedFileUrl != null && resolvedFileUrl.isNotEmpty)
                    ? (_looksLikePdfSourceUrl(resolvedFileUrl) ? 'pdf' : 'web')
                    : 'pdf'));
    return RagSource(
      fileId: json['file_id']?.toString() ?? '',
      sourceId: resolvedSourceId != null && resolvedSourceId.isNotEmpty
          ? resolvedSourceId
          : null,
      sourceTable: resolvedSourceTable != null && resolvedSourceTable.isNotEmpty
          ? resolvedSourceTable
          : null,
      noticeDepartment:
          resolvedNoticeDepartment != null &&
              resolvedNoticeDepartment.isNotEmpty
          ? resolvedNoticeDepartment
          : null,
      title: json['title']?.toString() ?? 'Source',
      subject: resolvedSubject != null && resolvedSubject.isNotEmpty
          ? resolvedSubject
          : null,
      sourceType: inferredType,
      startPage: start is int ? start : int.tryParse(start?.toString() ?? ''),
      endPage: end is int ? end : int.tryParse(end?.toString() ?? ''),
      timestamp: json['timestamp']?.toString(),
      score: (json['score'] is num) ? (json['score'] as num).toDouble() : null,
      fileUrl: resolvedFileUrl,
      videoUrl: resolvedVideoUrl,
      isPrimary: json['is_primary'] == true,
    );
  }

  bool get isNoticeSource =>
      sourceTable?.trim().toLowerCase() == 'notices' &&
      (sourceId?.trim().isNotEmpty ?? false);
}

enum _QuestionPaperRetryReason {
  invalidJson,
  placeholderContent,
  groundingFailure,
}

class OcrErrorInfo {
  final String name;
  final String url;
  final String provider;
  final String code;
  final String message;

  const OcrErrorInfo({
    required this.name,
    required this.url,
    required this.provider,
    required this.code,
    required this.message,
  });

  factory OcrErrorInfo.fromJson(Map<String, dynamic> json) {
    return OcrErrorInfo(
      name: json['name']?.toString() ?? 'Attachment',
      url: json['url']?.toString() ?? '',
      provider: json['provider']?.toString() ?? 'ocr',
      code: json['code']?.toString() ?? 'ocr_failed',
      message: json['message']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'provider': provider,
      'code': code,
      'message': message,
    };
  }
}

class AIChatMessage {
  final bool isUser;
  String content;
  List<RagSource> sources;
  RagSource? primarySource;
  bool cached;
  bool noLocal;
  double? retrievalScore;
  double? llmConfidenceScore;
  double? combinedConfidence;
  bool ocrFailureAffectsRetrieval;
  List<OcrErrorInfo> ocrErrors;
  AiQuestionPaper? quizActionPaper;
  AiAnswerOrigin? answerOrigin;
  List<AiLiveActivityStep> liveSteps;
  String? liveTitle;
  bool showLiveExport;

  AIChatMessage({
    required this.isUser,
    required this.content,
    this.sources = const [],
    this.primarySource,
    this.cached = false,
    this.noLocal = false,
    this.retrievalScore,
    this.llmConfidenceScore,
    this.combinedConfidence,
    this.ocrFailureAffectsRetrieval = false,
    this.ocrErrors = const [],
    this.quizActionPaper,
    this.answerOrigin,
    this.liveSteps = const [],
    this.liveTitle,
    this.showLiveExport = false,
  });
}

class _ChatAttachment {
  final String name;
  final String url;
  final bool isPdf;
  final String? fileId;
  final String? resourceId;
  final String? noticeId;
  final String? subject;
  final String? semester;
  final String? branch;

  const _ChatAttachment({
    required this.name,
    required this.url,
    required this.isPdf,
    this.fileId,
    this.resourceId,
    this.noticeId,
    this.subject,
    this.semester,
    this.branch,
  });
}

class _QuestionPaperRequestConfig {
  final String semester;
  final String branch;

  const _QuestionPaperRequestConfig({
    required this.semester,
    required this.branch,
  });
}

class _PendingQuestionPaperRequest {
  final String originalPrompt;
  final String? subject;
  final String? semester;

  const _PendingQuestionPaperRequest({
    required this.originalPrompt,
    this.subject,
    this.semester,
  });
}

class _NoticeRequestContext {
  final List<String> noticeIds;
  final bool preferNoticeSources;

  const _NoticeRequestContext({
    this.noticeIds = const <String>[],
    this.preferNoticeSources = false,
  });
}

class _ResolvedQuestionPaperRequest {
  final String generationPrompt;
  final String userVisible;
  final String subject;
  final _QuestionPaperRequestConfig config;
  final bool pinnedScopeOnly;
  final bool preferTopicOnlyScope;

  const _ResolvedQuestionPaperRequest({
    required this.generationPrompt,
    required this.userVisible,
    required this.subject,
    required this.config,
    required this.pinnedScopeOnly,
    required this.preferTopicOnlyScope,
  });
}

class _LongResponseTracker {
  Timer? timer;
  bool didCrossThreshold = false;
}

/// Context for pinning a RAG chat to a specific resource/PDF.
class ResourceContext {
  final String? fileId;
  final String title;
  final String? subject;
  final String? semester;
  final String? branch;
  final String? videoUrl;

  const ResourceContext({
    this.fileId,
    required this.title,
    this.subject,
    this.semester,
    this.branch,
    this.videoUrl,
  });

  /// Human-readable label shown in the context banner.
  String get label {
    final parts = <String>[];
    if (semester != null && semester!.isNotEmpty) parts.add('Sem $semester');
    if (branch != null && branch!.isNotEmpty) parts.add(branch!);
    if (subject != null && subject!.isNotEmpty) parts.add(subject!);
    return parts.isEmpty ? title : parts.join(' | ');
  }
}

class AIChatScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;
  final String? initialPrompt;
  final bool embedded;

  /// Optional: if set, all RAG queries are pinned to this resource.
  final ResourceContext? resourceContext;

  const AIChatScreen({
    super.key,
    required this.collegeId,
    this.collegeName = '',
    this.initialPrompt,
    this.resourceContext,
    this.embedded = false,
  });

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen>
    with TickerProviderStateMixin {
  static const String _aiCoachMarksSeenKey = 'ai_chat_coach_marks_v1_seen';
  static const int _minLowTokenThreshold = 4000;

  final AnalyticsService _analytics = AnalyticsService.instance;
  final BackendApiService _api = BackendApiService();
  final AuthService _auth = AuthService();
  final SupabaseService _supabase = SupabaseService();
  final AiChatNotificationService _aiNotificationService =
      AiChatNotificationService.instance;
  final ChatSessionRepository _sessionRepository = ChatSessionRepository();
  final SummaryPdfService _summaryPdfService = SummaryPdfService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final AiChatAnimationControllerBundle _animations;

  bool _isLoading = false;
  bool _isSendAttemptInProgress = false;
  DateTime? _lastSendTriggeredAt;
  String? _lastSendFingerprint;
  DateTime? _lastSendFingerprintAt;
  final List<AIChatMessage> _messages = [];
  final List<_ChatAttachment> _attachments = [];
  final List<_ChatAttachment> _stickyAttachments = [];
  bool _isUploadingAttachment = false;
  bool _isOcrActionLoading = false;
  List<LocalAiChatSession> _sessions = [];
  String? _activeSessionId;
  bool _isHistoryLoading = true;
  bool _showEntrySplash = true;
  final Queue<String> _typingQueue = Queue<String>();
  Timer? _typingTimer;
  Completer<void>? _typingDrainCompleter;
  AIChatMessage? _typingMessage;
  bool _streamTypingDone = false;
  bool _typingScrollScheduled = false;
  static const Duration _typingTick = Duration(milliseconds: 16);
  static const Duration _longResponseThreshold = Duration(seconds: 12);
  final Set<_LongResponseTracker> _activeLongResponseTrackers =
      <_LongResponseTracker>{};
  bool _notifyOnLongResponses = true;
  bool _showCoachMarks = false;
  bool _showAiTokenLowBanner = false;
  bool _userDismissedTokenBanner = false;
  bool _isAiTokenStatusLoading = false;
  bool _allowWebMode = false;
  bool _searchAllPdfs = false;
  String? _lastPrimarySourceFileId;
  bool _hasText = false;
  DateTime? _lastAiTokenTopUpSnackBarAt;
  String? _lastAiTokenTopUpSnackBarMessage;
  DateTime? _lastSourceLinkSnackBarAt;
  bool _isOpeningSourceLink = false;
  bool _aiTokenStatusLoaded = false;
  int _aiTokenRemainingTokens = 0;
  int _aiTokenBudgetTokens = 0;
  int _aiTokenLowThreshold = _minLowTokenThreshold;
  _QuestionPaperRequestConfig? _cachedQuestionPaperConfig;
  _PendingQuestionPaperRequest? _pendingQuestionPaperRequest;
  Map<String, dynamic>? _cachedProfileFilters;
  bool _didQueueInitialPrompt = false;

  final GlobalKey _coachHistoryKey = GlobalKey(debugLabel: 'ai_chat_history');
  final GlobalKey _coachAttachKey = GlobalKey(debugLabel: 'ai_chat_attach');
  final GlobalKey _coachInputKey = GlobalKey(debugLabel: 'ai_chat_input');
  final GlobalKey _coachSendKey = GlobalKey(debugLabel: 'ai_chat_send');
  final GlobalKey _coachNewChatKey = GlobalKey(debugLabel: 'ai_chat_new_chat');

  static const List<String> _suggestions = [
    'Summarize Unit 2 from my latest PDF.',
    'Give me 5 MCQs on Operating Systems with answers.',
    'Explain stack vs queue with a real-world example.',
    'List key formulas from my notes for quick revision.',
  ];
  static const List<String> _noContextPhrases = [
    "couldn't find enough relevant information",
    'could not find enough relevant information',
    "couldn't locate",
    'could not locate',
    'unable to find',
    'no relevant information',
    'no relevant content found',
    'no relevant',
  ];

  bool get _isStudioChat => widget.resourceContext != null;

  String get _chatTitle => _isStudioChat ? 'AI Studio' : 'AI Chat';

  Map<String, Object?> _baseAnalyticsParameters() {
    return <String, Object?>{
      'studio_chat': _isStudioChat,
      'embedded': widget.embedded,
      'has_resource': widget.resourceContext != null,
      'has_video_context':
          widget.resourceContext?.videoUrl?.trim().isNotEmpty == true,
    };
  }

  Future<void> _trackAiChatOpened() async {
    final screenName = _isStudioChat ? 'ai_studio_chat' : 'ai_chat';
    await _analytics.trackScreenView(screenName: screenName);
    await _analytics.logEvent(
      '${screenName}_open',
      parameters: _baseAnalyticsParameters(),
    );
  }

  String _classifyAiChatError(String message) {
    final lowered = message.toLowerCase();
    if (lowered.contains('token') &&
        (lowered.contains('limit') || lowered.contains('balance'))) {
      return 'token_limit';
    }
    if (lowered.contains('socket') ||
        lowered.contains('host lookup') ||
        lowered.contains('network')) {
      return 'network';
    }
    if (lowered.contains('timeout')) return 'timeout';
    if (lowered.contains('ocr')) return 'ocr';
    if (lowered.contains('stream')) return 'stream';
    return 'unknown';
  }

  AnimationController get _splashAnimationController =>
      _animations.splashController;
  Animation<double> get _iconScaleAnimation => _animations.iconScaleAnimation;
  Animation<Offset> get _iconSlideAnimation => _animations.iconSlideAnimation;
  Animation<double> get _splashTitleAnimation =>
      _animations.splashTitleAnimation;
  Animation<Offset> get _titleSlideAnimation => _animations.titleSlideAnimation;
  Animation<double> get _splashSubtitleAnimation =>
      _animations.splashSubtitleAnimation;
  Animation<Offset> get _subtitleSlideAnimation =>
      _animations.subtitleSlideAnimation;
  AnimationController get _suggestionsController =>
      _animations.suggestionsController;
  List<CurvedAnimation> get _suggestionAnimations =>
      _animations.suggestionAnimations;
  List<CurvedAnimation> get _suggestionFadeAnimations =>
      _animations.suggestionFadeAnimations;
  AnimationController get _entrySplashController =>
      _animations.entrySplashController;
  Animation<double> get _entrySplashScale => _animations.entrySplashScale;
  Animation<double> get _entrySplashFade => _animations.entrySplashFade;

  @override
  void initState() {
    super.initState();
    _animations = AiChatAnimationControllerBundle(
      vsync: this,
      suggestionCount: _suggestions.length,
      onEntrySplashComplete: () {
        if (!mounted) return;
        setState(() => _showEntrySplash = false);
      },
    );

    _aiNotificationService.initialize();
    unawaited(_trackAiChatOpened());
    _prepareCoachMarks();
    _refreshAiTokenStatus();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });

    // Defer splash animation until after stored sessions load
    _loadStoredSessions();
  }

  /// Injects an AI greeting when chat is opened with a pinned resource.
  void _injectResourceGreeting() {
    final ctx = widget.resourceContext;
    if (ctx == null) return;

    final parts = <String>[];
    if (ctx.subject != null && ctx.subject!.isNotEmpty) {
      parts.add(ctx.subject!);
    }
    if (ctx.semester != null && ctx.semester!.isNotEmpty) {
      parts.add('Semester ${ctx.semester}');
    }
    if (ctx.branch != null && ctx.branch!.isNotEmpty) {
      parts.add(ctx.branch!);
    }

    final meta = parts.isEmpty ? '' : ' (${parts.join(', ')})';

    final greeting =
        'I have loaded "${ctx.title}"$meta. Ask me anything from this document - I will answer based on its contents. If I need to search beyond your notes, I will let you know.';

    setState(() {
      _messages.add(AIChatMessage(isUser: false, content: greeting));
    });
  }

  @override
  void dispose() {
    for (final tracker in _activeLongResponseTrackers) {
      tracker.timer?.cancel();
      tracker.timer = null;
    }
    _activeLongResponseTrackers.clear();
    _resetTypingRenderer();
    _animations.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _prepareCoachMarks() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_aiCoachMarksSeenKey) ?? false;
    if (!mounted || seen) return;
    await prefs.setBool(_aiCoachMarksSeenKey, true);
    setState(() => _showCoachMarks = true);
  }

  void _replayCoachMarks() {
    if (!mounted) return;
    setState(() => _showCoachMarks = true);
  }

  void _onCoachMarksComplete() {
    if (!mounted) return;
    setState(() => _showCoachMarks = false);
  }

  List<OnboardingStep> _buildAiCoachSteps() {
    return [
      OnboardingStep(
        title: 'Chat History',
        description:
            'Open your previous AI conversations and continue from where you left off.',
        icon: Icons.history_rounded,
        targetKey: _coachHistoryKey,
      ),
      OnboardingStep(
        title: 'Attach Notes Or PYQs',
        description:
            'Add PDF or image files so AI can answer from your uploaded study material.',
        icon: Icons.attach_file_rounded,
        targetKey: _coachAttachKey,
      ),
      OnboardingStep(
        title: 'Type Your Prompt',
        description:
            'Ask for summaries, explanations, question paper generation, or practice quizzes.',
        icon: Icons.edit_note_rounded,
        targetKey: _coachInputKey,
      ),
      OnboardingStep(
        title: 'Send Request',
        description:
            'Tap send to let StudyShare think through your notes before answering.',
        icon: Icons.arrow_upward_rounded,
        targetKey: _coachSendKey,
      ),
      OnboardingStep(
        title: 'Start Fresh Chat',
        description:
            'Use this to clear current messages and begin a new conversation thread.',
        icon: Icons.add_comment_outlined,
        targetKey: _coachNewChatKey,
      ),
    ];
  }

  String _sanitizePromptFragment(String text, {int maxLength = 280}) {
    final compact = text
        .replaceAll('\r', '\n')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.isEmpty) return '';
    return compact.length > maxLength
        ? '${compact.substring(0, maxLength).trim()}...'
        : compact;
  }

  String _sanitizeAssistantAnswerText(String raw) {
    final sourceHeaderPattern = RegExp(
      r'^(?:sources?|references?|citations?)\s*:?\s*$',
      caseSensitive: false,
    );
    final sourceBulletPattern = RegExp(
      r'^(?:[-*•]|\[\d+\])\s+',
      caseSensitive: false,
    );

    final lines = raw.replaceAll('\r', '').split('\n');
    final cleaned = <String>[];
    var skippingSourceBlock = false;

    for (final line in lines) {
      final trimmed = line.trim();
      final lower = trimmed.toLowerCase();
      if (trimmed.isEmpty) {
        cleaned.add(line);
        continue;
      }

      final looksLikeUrl =
          lower.contains('http://') || lower.contains('https://');
      if (sourceHeaderPattern.hasMatch(trimmed)) {
        skippingSourceBlock = true;
        continue;
      }
      if (skippingSourceBlock) {
        if (looksLikeUrl || sourceBulletPattern.hasMatch(trimmed)) {
          continue;
        }
        skippingSourceBlock = false;
      }
      cleaned.add(line);
    }

    final normalized = cleaned.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return normalized.trim();
  }

  List<Map<String, String>> _buildStructuredHistory({
    String? pendingUserPrompt,
    int maxMessages = 14,
  }) {
    final history = <Map<String, String>>[];

    for (final message in _messages) {
      final raw = message.isUser
          ? _extractPromptFromUserVisible(message.content)
          : message.content;
      final cleaned = _sanitizePromptFragment(raw, maxLength: 900);
      if (cleaned.isEmpty) continue;
      history.add(<String, String>{
        'role': message.isUser ? 'user' : 'assistant',
        'content': cleaned,
      });
    }

    final pending = _sanitizePromptFragment(
      pendingUserPrompt ?? '',
      maxLength: 900,
    );
    if (pending.isNotEmpty) {
      history.add(<String, String>{'role': 'user', 'content': pending});
    }

    if (history.length <= maxMessages) return history;
    return history.sublist(history.length - maxMessages);
  }

  bool _promptLooksNoticeFocused(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    if (RegExp(
      r'\b(notice|notices|announcement|announcements|notification|notifications|circular|deadline|last date|mock test|codetantra|code clash|winner|winners|registration|rank list|complete before|event|workshop|seminar|competition|quiz from notice|questions from notice)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    return RegExp(
          r'\b(platform|portal|attempt|completion|schedule)\b',
        ).hasMatch(normalized) &&
        RegExp(
          r'\b(mock test|test|exam|notice|announcement|event|codetantra)\b',
        ).hasMatch(normalized);
  }

  bool _promptLooksLikeNoticeCarryForward(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;

    final hasReference = RegExp(
      r'\b(it|that|this|those|them|same|previous|above|again|more)\b',
    ).hasMatch(normalized);
    final looksLikeFollowUpQuestion =
        RegExp(r'^(what|when|why|how|where|which)\b').hasMatch(normalized) ||
        normalized.contains('?');
    final looksLikeCarryForwardQuiz =
        _isQuestionPaperContinuationIntent(prompt) ||
        RegExp(
          r'\b(generate|create|make|give|prepare)\b.*\b(more|another|next|same)\b',
        ).hasMatch(normalized);

    return looksLikeCarryForwardQuiz ||
        (hasReference &&
            (looksLikeFollowUpQuestion || normalized.length <= 120));
  }

  List<String> _collectRecentNoticeIds({
    int? beforeMessageIndex,
    int maxAssistantMessages = 6,
    int maxIds = 6,
  }) {
    final seen = <String>{};
    final ids = <String>[];
    final startIndex = beforeMessageIndex == null
        ? _messages.length - 1
        : math.min(beforeMessageIndex - 1, _messages.length - 1);
    var assistantMessagesScanned = 0;

    for (var index = startIndex; index >= 0; index--) {
      final message = _messages[index];
      if (message.isUser) continue;
      assistantMessagesScanned++;

      for (final source in message.sources) {
        final noticeId = source.isNoticeSource
            ? source.sourceId?.trim() ?? ''
            : '';
        if (noticeId.isEmpty || !seen.add(noticeId)) continue;
        ids.add(noticeId);
        if (ids.length >= maxIds) {
          return ids;
        }
      }

      if (assistantMessagesScanned >= maxAssistantMessages && ids.isNotEmpty) {
        break;
      }
    }

    return ids;
  }

  _NoticeRequestContext _buildNoticeRequestContext({
    required String prompt,
    int? beforeMessageIndex,
    bool forQuestionPaper = false,
  }) {
    final recentNoticeIds = _collectRecentNoticeIds(
      beforeMessageIndex: beforeMessageIndex,
    );
    final explicitNoticePrompt = _promptLooksNoticeFocused(prompt);
    final carryForwardPrompt =
        recentNoticeIds.isNotEmpty &&
        _promptLooksLikeNoticeCarryForward(prompt);
    final questionPaperFollowUp =
        forQuestionPaper &&
        recentNoticeIds.isNotEmpty &&
        (_isQuestionPaperIntent(prompt: prompt, hasAttachments: false) ||
            _isQuestionPaperContinuationIntent(prompt) ||
            prompt.toLowerCase().contains('same notice'));
    final preferNoticeSources =
        explicitNoticePrompt || carryForwardPrompt || questionPaperFollowUp;

    if (!preferNoticeSources) {
      return const _NoticeRequestContext();
    }

    return _NoticeRequestContext(
      noticeIds: recentNoticeIds,
      preferNoticeSources: true,
    );
  }

  String _buildRagPrompt({
    required String userPrompt,
    required bool hasAttachments,
    bool preferLocalOnly = false,
    bool searchAllPdfs = false,
    bool preferNoticeSources = false,
  }) {
    final cleaned = userPrompt.trim();
    final hasVideoTranscriptContext = (widget.resourceContext?.videoUrl ?? '')
        .trim()
        .isNotEmpty;
    if (cleaned.isNotEmpty && preferLocalOnly) {
      final localScope = preferNoticeSources
          ? 'the local StudyShare context, including relevant notices/announcements and uploaded or pinned study material'
          : 'the local StudyShare context, including uploaded or pinned study material';
      if (searchAllPdfs) {
        return '$cleaned\n\n'
            'Important: Search only within $localScope. Search across all '
            'available study materials in your subject or semester instead of '
            'staying pinned to one file when needed. Do not add outside '
            'web/general info. If nothing relevant is found locally, say that '
            'clearly.';
      }
      if (hasVideoTranscriptContext) {
        return '$cleaned\n\n'
            'Important: Use only the currently open video transcript plus any '
            'relevant local StudyShare context. Do not add outside web/general '
            'info. If the local context does not contain the answer, say that '
            'clearly.';
      }
      return '$cleaned\n\n'
          'Important: Use only $localScope. Do not add outside web/general '
          'info. If the local context does not contain the answer, say that '
          'clearly.';
    }
    if (cleaned.isNotEmpty && hasVideoTranscriptContext) {
      return '$cleaned\n\n'
          'Primary context: the transcript of the video currently open in '
          'StudyShare.';
    }
    if (cleaned.isNotEmpty) return cleaned;
    if (hasVideoTranscriptContext) {
      return 'Please answer using the transcript of the currently open video.';
    }
    if (hasAttachments) {
      return 'Please analyze the attached files and help me study.';
    }
    return userPrompt;
  }

  bool _promptRequiresLocalContext(String prompt) {
    final normalized = prompt.toLowerCase();
    return normalized.contains('from pdf') ||
        normalized.contains('from my pdf') ||
        normalized.contains('from notes') ||
        normalized.contains('from my notes') ||
        normalized.contains('based on pdf') ||
        normalized.contains('based on notes') ||
        normalized.contains('use my pdf') ||
        normalized.contains('use my notes') ||
        normalized.contains('from attached');
  }

  bool _isPdfOverviewPrompt(String prompt) {
    final normalized = prompt.toLowerCase();
    return normalized.contains('what is this pdf about') ||
        normalized.contains('what is this document about') ||
        normalized.contains('what does this pdf cover') ||
        normalized.contains('what does this document cover') ||
        normalized.contains('which topics does this cover') ||
        normalized.contains('what topics does this cover') ||
        normalized.contains('outline this pdf') ||
        normalized.contains('outline this document') ||
        normalized.contains('summary of this pdf');
  }

  bool _promptRequestsAllPdfs(String prompt) {
    final normalized = prompt.toLowerCase();
    return normalized.contains('other pdf') ||
        normalized.contains('another pdf') ||
        normalized.contains('different pdf') ||
        normalized.contains('wrong pdf') ||
        normalized.contains('not the correct pdf') ||
        normalized.contains('not the right pdf') ||
        normalized.contains('this is not the pdf') ||
        normalized.contains('galat pdf') ||
        normalized.contains('galat book') ||
        normalized.contains('doosri pdf') ||
        normalized.contains('dusri pdf') ||
        normalized.contains('dusra notes') ||
        normalized.contains('doosra notes') ||
        normalized.contains('aa wali nahi') ||
        normalized.contains('doosri aali') ||
        normalized.contains('dusri aali') ||
        normalized.contains('yeh na chahiye') ||
        normalized.contains('badal de') ||
        normalized.contains('aur aali dikh') ||
        normalized.contains('theek nahi yeh') ||
        normalized.contains('other prf') ||
        normalized.contains('other notes') ||
        normalized.contains('another note') ||
        normalized.contains('search all pdf') ||
        normalized.contains('search all notes') ||
        normalized.contains('all pdfs') ||
        normalized.contains('all notes');
  }

  bool _shouldSearchAllPdfsForPrompt(String prompt) {
    return _searchAllPdfs || _promptRequestsAllPdfs(prompt);
  }

  String _extractAcademicTopicHint(String prompt) {
    final normalized = prompt.trim();
    if (normalized.isEmpty) return '';

    final extractedQuizTopic = _extractTopicFromPrompt(normalized);
    if (extractedQuizTopic.isNotEmpty) {
      return extractedQuizTopic;
    }

    final patterns = <RegExp>[
      RegExp(
        r'^(?:what\s+is|define|explain|describe|briefly\s+explain|brief\s+note\s+on|short\s+note\s+on|tell\s+me(?:\s+in\s+brief)?\s+about|give\s+me(?:\s+a)?\s+brief\s+(?:on|about)|overview\s+of|introduction\s+to)\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(r'(?:about|on|of)\s+(.+)$', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;
      final candidate = _normalizeQuestionPaperSubjectHint(
        match.group(1)?.trim() ?? '',
      );
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }

    return '';
  }

  bool _shouldRelaxProfileAcademicScope(String prompt) {
    final normalized = prompt.trim();
    if (normalized.isEmpty) return false;
    if (_extractSemesterFromPrompt(normalized) != null) return false;
    if (_shouldSearchAllPdfsForPrompt(normalized)) return false;
    if (_referencesCurrentStudyMaterial(normalized)) return false;
    if ((widget.resourceContext?.fileId ?? '').trim().isNotEmpty) return false;
    if ((widget.resourceContext?.videoUrl ?? '').trim().isNotEmpty) {
      return false;
    }

    final topicHint = _extractAcademicTopicHint(normalized);
    if (topicHint.isEmpty) return false;
    if (topicHint.split(' ').where((part) => part.isNotEmpty).length > 6) {
      return false;
    }

    final loweredTopic = topicHint.toLowerCase();
    if (RegExp(
      r'\b(this|that|these|those|my|current|attached|uploaded)\b',
    ).hasMatch(loweredTopic)) {
      return false;
    }

    return true;
  }

  bool _shouldForceEnglish(String prompt) {
    final normalized = prompt.toLowerCase();
    return normalized.contains('reply in english') ||
        normalized.contains('answer in english') ||
        normalized.contains('english only') ||
        normalized.contains('in english');
  }

  String _detectDialectIntensity(String prompt) {
    final normalized = prompt.toLowerCase();
    if (normalized.contains('strong haryanvi') ||
        normalized.contains('kadak haryanvi') ||
        normalized.contains('hard haryanvi') ||
        normalized.contains('full haryanvi') ||
        normalized.contains('pure haryanvi') ||
        normalized.contains('desi haryanvi')) {
      return 'strong';
    }
    return 'light';
  }

  Map<String, dynamic>? _buildContextFilters() {
    final resource = widget.resourceContext;
    if (resource == null) return null;
    final filters = <String, dynamic>{};
    if ((resource.semester ?? '').trim().isNotEmpty) {
      filters['semester'] = resource.semester!.trim();
    }
    if ((resource.branch ?? '').trim().isNotEmpty) {
      filters['branch'] = resource.branch!.trim();
    }
    if ((resource.subject ?? '').trim().isNotEmpty) {
      filters['subject'] = resource.subject!.trim();
    }
    return filters.isEmpty ? null : filters;
  }

  Future<Map<String, dynamic>?> _buildContextFiltersForRequest({
    bool ignoreSubject = false,
    String? prompt,
  }) async {
    final contextFilters = _buildContextFilters();
    if (contextFilters != null && contextFilters.isNotEmpty) {
      if (ignoreSubject) {
        final trimmed = Map<String, dynamic>.from(contextFilters);
        trimmed.remove('subject');
        return trimmed;
      }
      return contextFilters;
    }

    final shouldRelaxProfileScope =
        (prompt ?? '').trim().isNotEmpty &&
        _shouldRelaxProfileAcademicScope(prompt!);

    if (_cachedProfileFilters != null && _cachedProfileFilters!.isNotEmpty) {
      if (shouldRelaxProfileScope) {
        return null;
      }
      final normalized = Map<String, dynamic>.from(_cachedProfileFilters!);
      // Profile subject is often stale/noisy for open-ended chat prompts.
      // Keep semester/branch as soft scope, but let the prompt subject win.
      normalized.remove('subject');
      if (ignoreSubject) {
        normalized.remove('subject');
      }
      return normalized.isEmpty ? null : normalized;
    }

    final email = _auth.userEmail?.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;

    try {
      final info = await _supabase.getUserInfo(email);
      if (info == null || info.isEmpty) return null;

      final filters = <String, dynamic>{};
      final semester = info['semester']?.toString().trim() ?? '';
      final branch =
          (info['branch'] ?? info['department'])?.toString().trim() ?? '';

      if (semester.isNotEmpty) filters['semester'] = semester;
      if (branch.isNotEmpty) filters['branch'] = branch;

      _cachedProfileFilters = filters.isEmpty ? null : filters;
      if (shouldRelaxProfileScope) {
        return null;
      }
      return _cachedProfileFilters == null
          ? null
          : Map<String, dynamic>.from(_cachedProfileFilters!);
    } catch (e) {
      debugPrint('AI chat profile filters lookup failed: $e');
      return null;
    }
  }

  bool _isSummaryExportIntent({
    required String prompt,
    required bool hasAttachments,
  }) {
    if (!hasAttachments) return false;
    final normalized = prompt.toLowerCase();
    final asksSummary =
        normalized.contains('summary') ||
        normalized.contains('report') ||
        normalized.contains('notes');
    final asksFileOutput =
        normalized.contains('pdf') ||
        normalized.contains('document') ||
        normalized.contains('file') ||
        normalized.contains('export');
    return asksSummary && asksFileOutput;
  }

  String _extractTopicFromPrompt(String prompt) {
    final normalized = prompt.trim();
    final matches = [
      RegExp(
        r'(?:quiz|mcq|question paper|test)\s+(?:on|for|about|from|of)\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(r'(?:on|for|about|of)\s+(.+)$', caseSensitive: false),
    ];
    for (final pattern in matches) {
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;
      final captured = match.group(1)?.trim() ?? '';
      final normalizedSubject = _normalizeQuestionPaperSubjectHint(captured);
      if (normalizedSubject.isNotEmpty) {
        return normalizedSubject;
      }
    }
    return '';
  }

  String _normalizeQuestionPaperSubjectHint(String raw) {
    final trimmed = raw
        .replaceAll(RegExp(r'[.?!]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (trimmed.isEmpty) return '';
    final lowered = trimmed.toLowerCase();
    if (RegExp(
      r'^(this|that|these|those|same|current)\s+(pdf|file|notes?|material|document)s?$',
    ).hasMatch(lowered)) {
      return '';
    }

    final withoutQualifiers = trimmed
        .replaceAll(
          RegExp(r'^(?:of|for|about|on|from)\s+', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(?:from|using|with)\s+(?:this|that|these|those|my|the|same|current)\s+(?:pdf|file|notes?|material|document)s?\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(?:semester|sem)\s*[1-8]\b|\b[1-8](?:st|nd|rd|th)?\s*semester\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(?:cse|ece|eee|civil|mechanical|chemical|it|aiml|ai-ml|ai/ml)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(?:pdf|file|notes?|material|document|uploaded|attached|current|same)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\bsubject\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final cleaned = withoutQualifiers
        .replaceAll(RegExp(r'^[,;:\-]+|[,;:\-]+$'), '')
        .trim();
    if (cleaned.isEmpty) return '';
    if (cleaned.split(' ').length > 6) return '';
    return cleaned;
  }

  String? _extractSemesterFromPrompt(String prompt) {
    final match = RegExp(
      r'\b([1-8])(?:st|nd|rd|th)?\s*semester\b|\bsemester\s*([1-8])\b|\bsem\s*([1-8])\b',
      caseSensitive: false,
    ).firstMatch(prompt);
    final value = match?.group(1) ?? match?.group(2) ?? match?.group(3);
    return value?.trim().isNotEmpty == true ? value!.trim() : null;
  }

  bool _referencesCurrentStudyMaterial(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    return RegExp(
      r'\b(this|that|these|those|same|current|attached|uploaded|my)\s+(pdf|file|notes?|material|document)s?\b',
    ).hasMatch(normalized);
  }

  bool _looksLikeQuestionPaperClarificationReply(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (RegExp(
      r'^(cancel|skip|leave it|never mind|ignore)$',
    ).hasMatch(normalized)) {
      return false;
    }
    return _extractSemesterFromPrompt(prompt) != null ||
        _referencesCurrentStudyMaterial(prompt) ||
        _normalizeQuestionPaperSubjectHint(prompt).isNotEmpty;
  }

  String _buildQuestionPaperClarificationMessage({
    required bool needsSubject,
    required bool needsSemester,
    String? subject,
  }) {
    if (needsSubject && needsSemester) {
      return 'I can generate that test, but I need the topic or subject and the semester first. Reply like "Polymers, semester 1".';
    }
    if (needsSubject) {
      return 'I can generate that test once you tell me the topic, subject, or exact PDF to use. Reply like "Polymers" or open the PDF and ask again.';
    }
    final resolvedSubject = (subject ?? '').trim();
    if (resolvedSubject.isNotEmpty) {
      return 'I found the topic as $resolvedSubject. Which semester should I use for the test? Reply like "semester 1".';
    }
    return 'Which semester should I use for this test? Reply like "semester 1".';
  }

  Future<void> _queueQuestionPaperClarification({
    required String userVisible,
    required String originalPrompt,
    required String clarificationMessage,
    required List<_ChatAttachment> turnAttachments,
    String? subject,
    String? semester,
  }) async {
    final userMessage = AIChatMessage(isUser: true, content: userVisible);
    final assistantMessage = AIChatMessage(
      isUser: false,
      content: clarificationMessage,
    );

    if (mounted) {
      setState(() {
        _messages.add(userMessage);
        _messages.add(assistantMessage);
        _pendingQuestionPaperRequest = _PendingQuestionPaperRequest(
          originalPrompt: originalPrompt,
          subject: subject,
          semester: semester,
        );
        _rememberAttachmentsForContext(turnAttachments);
        _controller.clear();
        _attachments.clear();
        _isLoading = false;
      });
    }

    await _persistCurrentSession();
    await _scrollToBottom();
  }

  Future<_ResolvedQuestionPaperRequest?> _resolveQuestionPaperRequest({
    required String userPrompt,
    required String userVisible,
    required List<_ChatAttachment> effectiveAttachments,
    required List<_ChatAttachment> turnAttachments,
    required bool isFreshQuestionPaperRequest,
  }) async {
    final hasPinnedScope =
        !_shouldSearchAllPdfsForPrompt(userPrompt) &&
        (widget.resourceContext != null ||
            effectiveAttachments.isNotEmpty ||
            _referencesCurrentStudyMaterial(userPrompt));
    final pending = !isFreshQuestionPaperRequest
        ? _pendingQuestionPaperRequest
        : null;
    final basePrompt = pending?.originalPrompt ?? userPrompt;

    var resolvedSubject = _normalizeQuestionPaperSubjectHint(
      _extractTopicFromPrompt(userPrompt),
    );
    var resolvedSemester = _extractSemesterFromPrompt(userPrompt) ?? '';

    if (resolvedSubject.isEmpty && (pending?.subject ?? '').trim().isNotEmpty) {
      resolvedSubject = pending!.subject!.trim();
    }
    if (resolvedSemester.isEmpty &&
        (pending?.semester ?? '').trim().isNotEmpty) {
      resolvedSemester = pending!.semester!.trim();
    }

    if (resolvedSubject.isEmpty &&
        pending != null &&
        !RegExp(r'[?]').hasMatch(userPrompt)) {
      resolvedSubject = _normalizeQuestionPaperSubjectHint(userPrompt);
    }

    if (resolvedSubject.isEmpty &&
        (widget.resourceContext?.subject ?? '').trim().isNotEmpty) {
      resolvedSubject = widget.resourceContext!.subject!.trim();
    }

    if (resolvedSubject.isEmpty && effectiveAttachments.isNotEmpty) {
      final attachmentPayload = _toAttachmentPayload(effectiveAttachments);
      final inferred = await _inferSubjectFromAttachments(
        attachments: attachmentPayload,
      );
      final normalized = _normalizeQuestionPaperSubjectHint(inferred);
      if (normalized.isNotEmpty) {
        resolvedSubject = normalized;
      }
    }

    final config = await _resolveQuestionPaperConfig(
      allowFallback: hasPinnedScope,
    );
    final hasExplicitSemester = resolvedSemester.trim().isNotEmpty;

    final needsSubject = !hasPinnedScope && resolvedSubject.isEmpty;
    final needsSemester = false;

    if (needsSubject || needsSemester) {
      await _queueQuestionPaperClarification(
        userVisible: userVisible,
        originalPrompt: basePrompt,
        clarificationMessage: _buildQuestionPaperClarificationMessage(
          needsSubject: needsSubject,
          needsSemester: needsSemester,
          subject: resolvedSubject,
        ),
        turnAttachments: turnAttachments,
        subject: resolvedSubject,
        semester: resolvedSemester,
      );
      return null;
    }

    final preferTopicOnlyScope =
        resolvedSubject.trim().isNotEmpty &&
        !hasPinnedScope &&
        !hasExplicitSemester;
    final effectiveSemester = preferTopicOnlyScope
        ? ''
        : (_normalizeAcademicFilterValue(
                resolvedSemester.isNotEmpty
                    ? resolvedSemester
                    : (config?.semester ?? ''),
                semesterOnly: true,
              ) ??
              config?.semester ??
              widget.resourceContext?.semester?.trim() ??
              '');
    final effectiveBranch = preferTopicOnlyScope
        ? ''
        : (_normalizeAcademicFilterValue(
                config?.branch ?? widget.resourceContext?.branch?.trim() ?? '',
              ) ??
              widget.resourceContext?.branch?.trim() ??
              '');

    _pendingQuestionPaperRequest = null;
    final scopeParts = <String>[
      if (resolvedSubject.trim().isNotEmpty) 'Topic ${resolvedSubject.trim()}',
      if (effectiveSemester.trim().isNotEmpty) 'semester $effectiveSemester',
      if (effectiveBranch.trim().isNotEmpty) 'branch $effectiveBranch',
    ];
    final resolvedScopePrompt =
        '$basePrompt\n\nResolved scope: ${scopeParts.isNotEmpty ? scopeParts.join(', ') : 'current attached study material'}.';

    return _ResolvedQuestionPaperRequest(
      generationPrompt: resolvedScopePrompt,
      userVisible: userVisible,
      subject: resolvedSubject.trim(),
      config: _QuestionPaperRequestConfig(
        semester: effectiveSemester,
        branch: effectiveBranch,
      ),
      pinnedScopeOnly: hasPinnedScope,
      preferTopicOnlyScope: preferTopicOnlyScope,
    );
  }

  Future<_QuestionPaperRequestConfig?> _resolveQuestionPaperConfig({
    bool allowFallback = true,
  }) async {
    final cached = _cachedQuestionPaperConfig;
    if (cached != null) {
      final looksLikeGenericFallback =
          cached.semester.trim() == '1' &&
          cached.branch.trim().toLowerCase() == 'general';
      if (allowFallback || !looksLikeGenericFallback) {
        return cached;
      }
    }

    final fromContextSemester = widget.resourceContext?.semester?.trim() ?? '';
    final fromContextBranch = widget.resourceContext?.branch?.trim() ?? '';
    if (fromContextSemester.isNotEmpty && fromContextBranch.isNotEmpty) {
      final resolved = _QuestionPaperRequestConfig(
        semester: fromContextSemester,
        branch: fromContextBranch,
      );
      _cachedQuestionPaperConfig = resolved;
      return resolved;
    }

    final email = _auth.userEmail?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      try {
        final info = await _supabase.getUserInfo(email);
        final semester = info?['semester']?.toString().trim() ?? '';
        final branch =
            (info?['branch'] ?? info?['department'])?.toString().trim() ?? '';
        if (semester.isNotEmpty && branch.isNotEmpty) {
          final resolved = _QuestionPaperRequestConfig(
            semester: semester,
            branch: branch,
          );
          _cachedQuestionPaperConfig = resolved;
          return resolved;
        }
      } catch (e) {
        debugPrint('Question-paper profile lookup failed, using defaults: $e');
      }
    }

    if (!allowFallback) {
      return null;
    }

    const fallback = _QuestionPaperRequestConfig(
      semester: '1',
      branch: 'General',
    );
    _cachedQuestionPaperConfig = fallback;
    return fallback;
  }

  Future<void> _scrollToBottom({
    bool animated = true,
    Duration delay = const Duration(milliseconds: 50),
  }) async {
    var probeCount = 0;
    while (!_scrollController.hasClients && probeCount < 4) {
      probeCount++;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!_scrollController.hasClients) return;
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!_scrollController.hasClients) return;
    final targetOffset = _scrollController.position.maxScrollExtent;
    if (animated) {
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    _scrollController.jumpTo(targetOffset);
  }

  void _resetTypingRenderer() {
    _typingTimer?.cancel();
    _typingTimer = null;
    _typingQueue.clear();
    _typingMessage = null;
    _streamTypingDone = false;
    _typingScrollScheduled = false;
    _completeTypingDrainIfDrained();
  }

  void _ensureTypingDrainCompleter() {
    _typingDrainCompleter ??= Completer<void>();
  }

  void _completeTypingDrainIfDrained() {
    if (_typingQueue.isNotEmpty || _typingTimer != null) return;
    final completer = _typingDrainCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _typingDrainCompleter = null;
  }

  void _scheduleTypingScroll() {
    if (_typingScrollScheduled) return;
    _typingScrollScheduled = true;
    Future.delayed(const Duration(milliseconds: 90), () async {
      _typingScrollScheduled = false;
      await _scrollToBottom(animated: false, delay: Duration.zero);
    });
  }

  void _enqueueTypedChunk(AIChatMessage message, String text) {
    if (text.isEmpty) return;
    _ensureTypingDrainCompleter();
    _typingMessage = message;
    _typingQueue.addAll(text.characters);
    _ensureTypingPump();
  }

  void _ensureTypingPump() {
    if (_typingTimer != null) return;
    _ensureTypingDrainCompleter();
    _typingTimer = Timer.periodic(_typingTick, (timer) {
      if (!mounted || _typingMessage == null) {
        timer.cancel();
        _typingTimer = null;
        _completeTypingDrainIfDrained();
        return;
      }

      if (_typingQueue.isEmpty) {
        if (_streamTypingDone) {
          timer.cancel();
          _typingTimer = null;
          _completeTypingDrainIfDrained();
        }
        return;
      }

      final message = _typingMessage!;
      final charsPerTick = _typingQueue.length > 240
          ? 7
          : (_typingQueue.length > 140 ? 5 : 3);
      final writeCount = math.min(charsPerTick, _typingQueue.length);
      final buffer = StringBuffer();
      for (var i = 0; i < writeCount; i++) {
        buffer.write(_typingQueue.removeFirst());
      }

      if (buffer.isNotEmpty) {
        setState(() {
          message.content += buffer.toString();
        });
        _scheduleTypingScroll();
      }

      if (_typingQueue.isEmpty && _streamTypingDone) {
        timer.cancel();
        _typingTimer = null;
        _completeTypingDrainIfDrained();
      }
    });
  }

  Future<void> _waitForTypingDrain() async {
    if (_typingQueue.isEmpty && _typingTimer == null) {
      _completeTypingDrainIfDrained();
      return;
    }
    _ensureTypingDrainCompleter();
    final completer = _typingDrainCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  String get _storageEmail {
    final email = _auth.userEmail;
    if (email == null || email.trim().isEmpty) return 'guest';
    return email.trim().toLowerCase();
  }

  String _newSessionId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _deriveSessionTitle(List<AIChatMessage> messages) {
    final firstUser = messages.firstWhere(
      (message) => message.isUser && message.content.trim().isNotEmpty,
      orElse: () => AIChatMessage(isUser: true, content: 'New chat'),
    );
    final normalized = firstUser.content
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return 'New chat';
    return normalized.length > 52
        ? '${normalized.substring(0, 52).trim()}...'
        : normalized;
  }

  LocalAiChatMessage _toLocalMessage(AIChatMessage message) {
    final quizPayload = message.quizActionPaper?.toJson();
    final orderedSources = _mergePrimarySource(
      message.primarySource,
      message.sources,
    );
    return LocalAiChatMessage(
      isUser: message.isUser,
      content: message.content,
      sources: orderedSources
          .map(
            (source) => {
              'file_id': source.fileId,
              if (source.sourceId?.trim().isNotEmpty ?? false)
                'source_id': source.sourceId,
              if (source.sourceTable?.trim().isNotEmpty ?? false)
                'source_table': source.sourceTable,
              if (source.noticeDepartment?.trim().isNotEmpty ?? false)
                'notice_department': source.noticeDepartment,
              'title': source.title,
              'source_type': source.sourceType,
              'is_primary':
                  message.primarySource != null &&
                  source.fileId.isNotEmpty &&
                  message.primarySource!.fileId.isNotEmpty &&
                  source.fileId == message.primarySource!.fileId,
              'pages': {'start': source.startPage, 'end': source.endPage},
              'timestamp': source.timestamp,
              'score': source.score,
              'file_url': source.fileUrl,
              'video_url': source.videoUrl,
            },
          )
          .toList(),
      cached: message.cached,
      noLocal: message.noLocal,
      answerOrigin: message.answerOrigin?.wireValue,
      liveTitle: message.liveTitle,
      liveSteps: message.liveSteps
          .map((step) => step.toCompactJson())
          .toList(growable: false),
      showLiveExport: message.showLiveExport,
      retrievalScore: message.retrievalScore,
      llmConfidenceScore: message.llmConfidenceScore,
      combinedConfidence: message.combinedConfidence,
      ocrFailureAffectsRetrieval: message.ocrFailureAffectsRetrieval,
      ocrErrors: message.ocrErrors.map((e) => e.toJson()).toList(),
      actionType: quizPayload == null ? null : 'start_quiz',
      actionPayload: quizPayload,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  AIChatMessage _fromLocalMessage(LocalAiChatMessage message) {
    AiQuestionPaper? quizActionPaper;
    if (message.actionType == 'start_quiz' && message.actionPayload != null) {
      try {
        quizActionPaper = AiQuestionPaper.fromJson(message.actionPayload!);
      } catch (e) {
        debugPrint('Failed to restore quiz action from history: $e');
      }
    }
    final sources = message.sources
        .map((source) => RagSource.fromJson(source))
        .toList();
    final liveSteps = message.liveSteps
        .map((step) => AiLiveActivityStep.fromJson(step))
        .toList(growable: false);
    return AIChatMessage(
      isUser: message.isUser,
      content: message.content,
      sources: sources,
      primarySource: sources.firstWhereOrNull((s) => s.isPrimary),
      cached: message.cached,
      noLocal: message.noLocal,
      answerOrigin: AiAnswerOriginX.fromWireValue(message.answerOrigin),
      liveSteps: liveSteps,
      liveTitle: message.liveTitle,
      showLiveExport: message.showLiveExport,
      retrievalScore: message.retrievalScore,
      llmConfidenceScore: message.llmConfidenceScore,
      combinedConfidence: message.combinedConfidence,
      ocrFailureAffectsRetrieval: message.ocrFailureAffectsRetrieval,
      ocrErrors: message.ocrErrors
          .map((entry) => OcrErrorInfo.fromJson(entry))
          .toList(),
      quizActionPaper: quizActionPaper,
    );
  }

  bool _shouldShowLiveActivityCard(
    AIChatMessage message,
    bool isStreamingAssistantMessage,
  ) =>
      message.showLiveExport ||
      (message.liveSteps.isNotEmpty &&
          (isStreamingAssistantMessage || message.content.trim().isEmpty));

  bool _shouldShowCollapsedLiveTrace(
    AIChatMessage message,
    bool isStreamingAssistantMessage,
  ) =>
      !message.isUser &&
      !message.showLiveExport &&
      message.liveSteps.isNotEmpty &&
      message.content.trim().isNotEmpty &&
      !isStreamingAssistantMessage;

  String _buildCollapsedLiveTraceLabel(AIChatMessage message) {
    final usesNoticeSources = message.sources.any(
      (source) => source.isNoticeSource,
    );
    final prefix = switch (message.answerOrigin) {
      AiAnswerOrigin.webOnly => 'Used web results from',
      AiAnswerOrigin.notesPlusWeb =>
        usesNoticeSources
            ? 'Used local StudyShare and web results from'
            : 'Used notes and web results from',
      AiAnswerOrigin.insufficientNotes =>
        usesNoticeSources
            ? 'Used the closest matching local sources from'
            : 'Used the closest matching notes from',
      AiAnswerOrigin.notesOnly || null =>
        usesNoticeSources
            ? 'Used local StudyShare sources from'
            : 'Used notes from',
    };
    final sourceTitles =
        _activitySourcesFromRagSources(message.sources, limit: 2)
            .map((source) => source.title.trim())
            .where((title) => title.isNotEmpty)
            .toList();
    if (sourceTitles.isEmpty) {
      return prefix.replaceFirst(' from', '');
    }
    final extraCount = message.sources.length - sourceTitles.length;
    final extraLabel = extraCount > 0 ? ' +$extraCount more' : '';
    return '$prefix ${sourceTitles.join(' + ')}$extraLabel';
  }

  Widget _buildCollapsedLiveTrace(
    AIChatMessage message,
    bool isDark,
    bool isCompact,
  ) {
    final textColor = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _buildCollapsedLiveTraceLabel(message),
              style: GoogleFonts.inter(
                fontSize: isCompact ? 10.8 : 11.2,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AiLiveSourceKind _sourceKindFromRagSource(RagSource source) {
    if (source.isNoticeSource) return AiLiveSourceKind.notice;
    final normalized = source.sourceType.trim().toLowerCase();
    if (normalized == 'web') return AiLiveSourceKind.web;
    if (normalized == 'youtube' || normalized == 'video') {
      return AiLiveSourceKind.video;
    }
    return AiLiveSourceKind.notes;
  }

  List<AiLiveActivitySource> _activitySourcesFromRagSources(
    List<RagSource> sources, {
    int limit = 3,
  }) {
    final seen = <String>{};
    final activitySources = <AiLiveActivitySource>[];

    for (final source in sources) {
      final kind = _sourceKindFromRagSource(source);
      final key = [
        source.fileId.trim(),
        source.sourceId?.trim() ?? '',
        source.title.trim(),
        source.startPage?.toString() ?? '',
        kind.wireValue,
      ].join('|');
      if (seen.contains(key)) continue;
      seen.add(key);
      activitySources.add(
        AiLiveActivitySource(
          title: source.title,
          kind: kind,
          page: source.startPage,
          timestamp: source.timestamp,
          url: kind == AiLiveSourceKind.notes
              ? source.fileUrl
              : (source.videoUrl ?? source.fileUrl),
          fileId: source.fileId.trim().isEmpty ? null : source.fileId.trim(),
          sourceId: source.sourceId?.trim().isEmpty == false
              ? source.sourceId!.trim()
              : null,
          sourceTable: source.sourceTable,
          departmentId: source.noticeDepartment,
        ),
      );
      if (activitySources.length >= limit) break;
    }

    return activitySources;
  }

  String _activityTitleForAnswerOrigin(AiAnswerOrigin? origin) {
    switch (origin) {
      case AiAnswerOrigin.webOnly:
        return 'Web search completed';
      case AiAnswerOrigin.notesPlusWeb:
        return 'Merged local sources with web context';
      case AiAnswerOrigin.insufficientNotes:
        return 'Local source scan completed';
      case AiAnswerOrigin.notesOnly:
      case null:
        return 'Local retrieval completed';
    }
  }

  List<AiLiveActivityStep> _buildLiveAnswerSteps({
    required AiAnswerOrigin? answerOrigin,
    required List<RagSource> sources,
    required bool noLocal,
    required bool answerCompleted,
  }) {
    final activitySources = _activitySourcesFromRagSources(sources);
    final AiLiveActivityStatus retrievalStatus;
    switch (answerOrigin) {
      case AiAnswerOrigin.insufficientNotes:
        retrievalStatus = activitySources.isNotEmpty
            ? AiLiveActivityStatus.warning
            : AiLiveActivityStatus.failed;
        break;
      case AiAnswerOrigin.webOnly:
      case AiAnswerOrigin.notesPlusWeb:
      case AiAnswerOrigin.notesOnly:
        retrievalStatus = AiLiveActivityStatus.completed;
        break;
      case null:
        if (activitySources.isNotEmpty) {
          retrievalStatus = AiLiveActivityStatus.completed;
        } else if (noLocal) {
          retrievalStatus = AiLiveActivityStatus.failed;
        } else {
          retrievalStatus = AiLiveActivityStatus.active;
        }
        break;
    }

    final answerStatus = answerCompleted
        ? AiLiveActivityStatus.completed
        : AiLiveActivityStatus.active;

    return [
      AiLiveActivityStep(
        id: 'retrieve',
        title: _activityTitleForAnswerOrigin(answerOrigin),
        status: retrievalStatus,
        description: answerOrigin == AiAnswerOrigin.insufficientNotes
            ? 'Only a partial grounding match was found in the current local sources.'
            : null,
        sources: activitySources,
      ),
      AiLiveActivityStep(
        id: 'answer',
        title: 'Response generation',
        status: answerStatus,
        description: answerCompleted
            ? 'The answer is fully prepared and ready to read.'
            : 'Drafting the final answer from the gathered context.',
      ),
    ];
  }

  List<AiLiveActivityStep> _markLiveAnswerStatus(
    List<AiLiveActivityStep> steps,
    AiLiveActivityStatus status,
  ) {
    return steps
        .map(
          (step) => step.id == 'answer' ? step.copyWith(status: status) : step,
        )
        .toList(growable: false);
  }

  RagSource? _findSourceForLiveOpen(AIChatMessage message, String fileId) {
    if (message.primarySource?.fileId == fileId) {
      return message.primarySource;
    }
    return message.sources.firstWhereOrNull(
      (source) => source.fileId == fileId,
    );
  }

  Future<void> _openLivePdfSource(
    AIChatMessage message,
    String fileId,
    int? page,
  ) async {
    final source = _findSourceForLiveOpen(message, fileId);
    final rawUrl = (source?.fileUrl ?? '').trim();

    // If the source has no URL the chunk was stored without one —
    // show a clear message rather than the generic "invalid URL" text.
    if (rawUrl.isEmpty) {
      if (!mounted) return;
      final title = source?.title ?? 'this source';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF link unavailable for "$title". '
            'Try re-uploading the file to restore access.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final target = _normalizeExternalUrl(rawUrl);
    final uri = _buildExternalLaunchUri(target);
    if (uri == null) {
      _showSourceUrlErrorSnackBar(source?.title ?? 'PDF source');
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          pdfUrl: uri.toString(),
          title: source?.title ?? 'Source',
          resourceId: fileId,
          collegeId: widget.collegeId,
          initialPage: page ?? 1,
        ),
      ),
    );
  }

  DepartmentAccount _fallbackNoticeDepartmentAccount(String departmentId) {
    final normalized = departmentId.trim();
    if (normalized.isEmpty) {
      return DepartmentAccount.unknown();
    }
    final label = normalized.toUpperCase();
    return DepartmentAccount(
      id: normalized,
      name: '$label Department',
      handle: '@${normalized.toLowerCase()}',
      avatarLetter: label[0],
      color: AppTheme.primary,
    );
  }

  Future<void> _openNoticeById(String noticeId, {RagSource? source}) async {
    final normalizedNoticeId = noticeId.trim();
    if (normalizedNoticeId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notice link is unavailable right now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final notice = await _supabase.getNotice(
      normalizedNoticeId,
      collegeId: widget.collegeId,
    );
    if (!mounted) return;
    if (notice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The notice linked to "${source?.title ?? 'this source'}" could not be loaded.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final departmentId =
        (source?.noticeDepartment ??
                notice['department']?.toString() ??
                notice['department_id']?.toString() ??
                '')
            .trim();
    final account =
        await _supabase.getDepartmentProfile(departmentId) ??
        _fallbackNoticeDepartmentAccount(departmentId);
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoticeDetailScreen(
          notice: notice,
          account: account,
          collegeId: widget.collegeId,
        ),
      ),
    );
  }

  Future<void> _openNoticeSource(RagSource source) async {
    await _openNoticeById(source.sourceId?.trim() ?? '', source: source);
  }

  Future<void> _openLiveNoticeSource(String noticeId) async {
    await _openNoticeById(noticeId);
  }

  Future<void> _openLiveWebSource(String url) async {
    final uri = _buildExternalLaunchUri(_normalizeExternalUrl(url));
    if (uri == null) {
      _showSourceUrlErrorSnackBar('Web source');
      return;
    }
    await _openWebSourceInAppOrExternal(uri: uri, sourceTitle: 'Web source');
  }

  Future<void> _openLiveVideoSource(String url, String? timestamp) async {
    final normalized = _normalizeExternalUrl(url);
    if (normalized.isEmpty) {
      _showSourceUrlErrorSnackBar('Video source');
      return;
    }
    final uri = _buildExternalLaunchUri(normalized);
    if (uri == null) {
      _showSourceUrlErrorSnackBar('Video source');
      return;
    }

    var opened = false;
    if (mounted) {
      try {
        opened = await openStudyShareLink(
          context,
          rawUrl: normalized,
          title: 'Video source',
          collegeId: widget.collegeId,
          subject: widget.resourceContext?.subject,
          semester: widget.resourceContext?.semester,
          branch: widget.resourceContext?.branch,
          fallbackBaseUrl: AppConfig.apiUrl,
        );
      } catch (e) {
        debugPrint('openStudyShareLink failed for live activity source: $e');
      }
    }

    if (!opened) {
      await _openExternalSourceLink(uri: uri, sourceTitle: 'Video source');
    }
  }

  List<AiLiveActivitySource> _activitySourcesFromAttachmentMaps(
    List<Map<String, dynamic>> attachments, {
    int limit = 3,
  }) {
    final seen = <String>{};
    final activitySources = <AiLiveActivitySource>[];
    for (final attachment in attachments) {
      final title = attachment['name']?.toString().trim() ?? 'Study material';
      final rawUrl = attachment['url']?.toString().trim() ?? '';
      final fileId = attachment['file_id']?.toString().trim().isNotEmpty == true
          ? attachment['file_id']!.toString().trim()
          : (attachment['resource_id']?.toString().trim().isNotEmpty == true
                ? attachment['resource_id']!.toString().trim()
                : null);
      final normalizedType = attachment['type']?.toString().toLowerCase() ?? '';
      final kind =
          rawUrl.toLowerCase().contains('youtu') ||
              normalizedType == 'youtube' ||
              normalizedType == 'video'
          ? AiLiveSourceKind.video
          : (normalizedType == 'web'
                ? AiLiveSourceKind.web
                : AiLiveSourceKind.notes);
      final key = '$title|${kind.wireValue}|$rawUrl';
      if (seen.contains(key)) continue;
      seen.add(key);
      activitySources.add(
        AiLiveActivitySource(
          title: title,
          kind: kind,
          url: rawUrl.isEmpty ? null : rawUrl,
          fileId: fileId,
        ),
      );
      if (activitySources.length >= limit) break;
    }
    return activitySources;
  }

  String _buildQuestionPaperLiveTitle({
    required String inferredSubject,
    required _QuestionPaperRequestConfig config,
  }) {
    final subject = inferredSubject.trim();
    if (subject.isNotEmpty) {
      return 'Generating a $subject paper';
    }
    if (config.semester.trim().isNotEmpty || config.branch.trim().isNotEmpty) {
      final parts = <String>[
        if (config.semester.trim().isNotEmpty) 'Sem ${config.semester.trim()}',
        if (config.branch.trim().isNotEmpty) config.branch.trim().toUpperCase(),
      ];
      return 'Generating ${parts.join(' ')} paper';
    }
    return 'Generating your question paper';
  }

  List<AiLiveActivityStep> _buildQuestionPaperLiveSteps({
    required String notesDescription,
    List<AiLiveActivitySource> noteSources = const [],
  }) {
    return [
      const AiLiveActivityStep(
        id: 'qp_context',
        title: 'Resolved paper context',
        status: AiLiveActivityStatus.pending,
      ),
      AiLiveActivityStep(
        id: 'qp_notes',
        title: 'Loaded supporting sources',
        status: AiLiveActivityStatus.pending,
        description: notesDescription,
        sources: noteSources,
      ),
      const AiLiveActivityStep(
        id: 'qp_generate',
        title: 'Drafted question paper',
        status: AiLiveActivityStatus.pending,
      ),
      const AiLiveActivityStep(
        id: 'qp_validate',
        title: 'Validated quiz structure',
        status: AiLiveActivityStatus.pending,
      ),
      const AiLiveActivityStep(
        id: 'qp_ready',
        title: 'Ready to export',
        status: AiLiveActivityStatus.pending,
      ),
    ];
  }

  List<AiLiveActivityStep> _updateLiveStepList(
    List<AiLiveActivityStep> steps,
    String stepId, {
    AiLiveActivityStatus? status,
    String? description,
    List<AiLiveActivitySource>? sources,
  }) {
    return steps
        .map((step) {
          if (step.id != stepId) return step;
          return step.copyWith(
            status: status ?? step.status,
            description: description ?? step.description,
            sources: sources ?? step.sources,
          );
        })
        .toList(growable: false);
  }

  List<AiLiveActivityStep> _upsertLiveEventList(
    List<AiLiveActivityStep> steps,
    String stepId,
    AiLiveActivityEvent event,
  ) {
    return steps
        .map((step) {
          if (step.id != stepId) return step;
          final updatedEvents = [...step.events];
          final existingIndex = updatedEvents.indexWhere(
            (item) => item.id == event.id,
          );
          if (existingIndex >= 0) {
            updatedEvents[existingIndex] = event;
          } else {
            updatedEvents.add(event);
          }
          return step.copyWith(events: updatedEvents);
        })
        .toList(growable: false);
  }

  Future<void> _exportQuestionPaperFromMessage(AIChatMessage message) async {
    final paper = message.quizActionPaper;
    if (paper == null) return;
    try {
      final file = await _summaryPdfService.saveQuestionPaperPdf(
        paper: paper,
        subtitle: 'AI Test Paper',
        watermarkText: 'StudyShare Test',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved and ready to share: ${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'StudyShare test paper: ${paper.title}',
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Failed to export question paper PDF: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to download PDF. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _supportsLiveQuestionPaperGame(AIChatMessage message) {
    if (message.isUser) return false;
    if (message.quizActionPaper != null) return true;
    return message.liveSteps.any((step) => step.id.startsWith('qp_'));
  }

  Future<void> _openQuestionPaperGameSheet(AIChatMessage message) async {
    if (!mounted) return;
    final loadingMessage = message.quizActionPaper == null
        ? 'Question paper is still generating. Beat the arcade score while you wait.'
        : 'Question paper is ready. Try to beat the loading-game high score too.';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: AiLoadingGameCard(
            loadingMessage: loadingMessage,
            headline: 'Live side quest',
            subheadline: 'Dice open the arcade only for question-paper runs.',
          ),
        ),
      ),
    );
  }

  double? _toNullableDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  RagSource? _parsePrimarySource(dynamic raw) {
    if (raw is! Map) return null;
    return RagSource.fromJson(Map<String, dynamic>.from(raw));
  }

  List<RagSource> _mergePrimarySource(
    RagSource? primary,
    List<RagSource> sources,
  ) {
    if (primary == null) return sources;
    final merged = <RagSource>[primary];
    for (final source in sources) {
      // Only skip if both fileIds are non-empty and equal
      if (primary.fileId.isNotEmpty &&
          source.fileId.isNotEmpty &&
          source.fileId == primary.fileId) {
        continue;
      }
      merged.add(source);
    }
    return merged;
  }

  Future<RagSource?> _pickSourceForOcrAction(List<RagSource> sources) async {
    final candidates = sources
        .where((s) => s.fileId.trim().isNotEmpty)
        .toList();
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    return showModalBottomSheet<RagSource>(
      context: context,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                'Select source',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              ...candidates.map((source) {
                return ListTile(
                  title: Text(
                    source.title,
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: source.startPage != null
                      ? Text(
                          'Pages ${source.startPage}-${source.endPage ?? source.startPage}',
                        )
                      : null,
                  onTap: () => Navigator.pop(sheetContext, source),
                );
              }),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Future<void> _retryOcrForMessage(AIChatMessage msg) async {
    if (_isOcrActionLoading) return;
    final source = await _pickSourceForOcrAction(msg.sources);
    if (source == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No source available for OCR retry.')),
      );
      return;
    }

    setState(() => _isOcrActionLoading = true);
    try {
      await _api.retryNotebookSourceNow(sourceId: source.fileId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR retry started for "${source.title}".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isOcrActionLoading = false);
    }
  }

  Future<void> _cancelOcrRetryForMessage(AIChatMessage msg) async {
    if (_isOcrActionLoading) return;
    final source = await _pickSourceForOcrAction(msg.sources);
    if (source == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No source available to cancel retry.')),
      );
      return;
    }

    setState(() => _isOcrActionLoading = true);
    try {
      await _api.cancelNotebookSourceReupload(sourceId: source.fileId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retry cancelled for "${source.title}".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isOcrActionLoading = false);
    }
  }

  Future<void> _requestReuploadForMessage(AIChatMessage msg) async {
    if (_isOcrActionLoading) return;
    final source = await _pickSourceForOcrAction(msg.sources);
    if (source == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No source available for re-upload.')),
      );
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'ppt',
        'pptx',
        'doc',
        'docx',
        'txt',
        'md',
        'png',
        'jpg',
        'jpeg',
        'tiff',
        'bmp',
        'gif',
      ],
    );

    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final filePath = file.path;
    if (filePath == null || filePath.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read file path for upload. Try again.'),
        ),
      );
      return;
    }

    setState(() => _isOcrActionLoading = true);
    try {
      final upload = await _api.uploadNotebookSource(
        filePath: filePath,
        collegeId: widget.collegeId,
        notebookId: _activeSessionId,
        title: file.name,
        sourceScope: 'ai_chat_reupload',
        subject: source.subject ?? widget.resourceContext?.subject,
      );
      final replacementFileId = upload['replacement_file_id']?.toString() ?? '';
      if (replacementFileId.isEmpty) {
        throw Exception('Upload did not return replacement_file_id.');
      }
      await _api.requestNotebookSourceReupload(
        sourceId: source.fileId,
        replacementFileId: replacementFileId,
        reason: 'manual_reupload_from_ai_chat',
        ocrErrorCode: 'ocr_failed',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Re-upload request submitted for "${source.title}".'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isOcrActionLoading = false);
    }
  }

  Future<void> _persistCurrentSession() async {
    final sessionId = _activeSessionId ?? _newSessionId();
    final now = DateTime.now().toIso8601String();
    final session = LocalAiChatSession(
      id: sessionId,
      title: _deriveSessionTitle(_messages),
      updatedAt: now,
      messages: _messages.map(_toLocalMessage).toList(),
      contextAttachments: _serializeStickyAttachments(),
    );

    final updated = await _sessionRepository.upsertSession(
      userEmail: _storageEmail,
      collegeId: widget.collegeId,
      session: session,
      existingSessions: _sessions,
    );

    if (!mounted) return;
    setState(() {
      _activeSessionId = sessionId;
      _sessions = updated;
    });
  }

  Future<void> _loadStoredSessions() async {
    final loaded = await _sessionRepository.loadSessions(
      userEmail: _storageEmail,
      collegeId: widget.collegeId,
    );

    if (!mounted) return;
    setState(() {
      _sessions = loaded;
      _isHistoryLoading = false;
      if (loaded.isNotEmpty) {
        final latest = loaded.first;
        _activeSessionId = latest.id;
        _messages
          ..clear()
          ..addAll(latest.messages.map(_fromLocalMessage));
        _stickyAttachments
          ..clear()
          ..addAll(_deserializeStickyAttachments(latest.contextAttachments));
      } else {
        _activeSessionId = _newSessionId();
        _stickyAttachments.clear();
        _pendingQuestionPaperRequest = null;
      }
    });

    // If opened with a resource context, always start fresh so history
    // from unrelated sessions is not shown.
    if (widget.resourceContext != null) {
      _activeSessionId = _newSessionId();
      _messages.clear();
      _clearStickyContext();
      _pendingQuestionPaperRequest = null;
      _injectResourceGreeting();
    } else if (_messages.isEmpty && mounted) {
      _splashAnimationController.forward().then((_) {
        if (_messages.isEmpty && mounted) {
          _suggestionsController.forward();
        }
      });
    }

    await _scrollToBottom();
    _queueInitialPromptIfNeeded();
  }

  void _queueInitialPromptIfNeeded() {
    final prompt = widget.initialPrompt?.trim();
    if (_didQueueInitialPrompt || prompt == null || prompt.isEmpty) {
      return;
    }
    _didQueueInitialPrompt = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _controller.text = prompt;
      await _sendMessage();
    });
  }

  Future<void> _startNewChat() async {
    if (_messages.isNotEmpty) {
      await _persistCurrentSession();
    }

    if (!mounted) return;
    setState(() {
      _activeSessionId = _newSessionId();
      _messages.clear();
      _attachments.clear();
      _clearStickyContext();
      _pendingQuestionPaperRequest = null;
      _controller.clear();
    });

    // Reset and replay splash animations for the empty chat
    _splashAnimationController.reset();
    _suggestionsController.reset();
    _splashAnimationController.forward().then((_) {
      if (_messages.isEmpty && mounted) {
        _suggestionsController.forward();
      }
    });
  }

  Future<void> _openSession(LocalAiChatSession session) async {
    if (_messages.isNotEmpty) {
      await _persistCurrentSession();
    }

    if (!mounted) return;
    setState(() {
      _activeSessionId = session.id;
      _messages
        ..clear()
        ..addAll(session.messages.map(_fromLocalMessage));
      _attachments.clear();
      _stickyAttachments
        ..clear()
        ..addAll(_deserializeStickyAttachments(session.contextAttachments));
      _pendingQuestionPaperRequest = null;
      _controller.clear();
    });
    await _scrollToBottom();
  }

  Future<void> _deleteSession(String sessionId) async {
    final result = await _sessionRepository.deleteSession(
      userEmail: _storageEmail,
      collegeId: widget.collegeId,
      sessionId: sessionId,
      existingSessions: _sessions,
    );

    if (!mounted) return;
    setState(() {
      _sessions = result.sessions;
      if (_activeSessionId == sessionId) {
        _activeSessionId = _newSessionId();
        _messages.clear();
        _clearStickyContext();
        _pendingQuestionPaperRequest = null;
      }
    });

    if (!result.deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session was already removed.')),
      );
    }
  }

  void _openHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        return SafeArea(
          child: Container(
            height: MediaQuery.of(sheetCtx).size.height * 0.78,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        'Previous Chats',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
                          await _startNewChat();
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('New Chat'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _sessions.isEmpty
                      ? Center(
                          child: Text(
                            'No saved chats yet',
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: _sessions.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final session = _sessions[index];
                            final isActive = session.id == _activeSessionId;
                            final updatedAt =
                                DateTime.tryParse(session.updatedAt) ??
                                DateTime.now();
                            final subtitle = session.messages.isNotEmpty
                                ? session.messages.last.content
                                : 'No messages';

                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                Navigator.pop(sheetCtx);
                                await _openSession(session);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppTheme.primary.withValues(alpha: 0.14)
                                      : (isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.05,
                                              )
                                            : Colors.grey.shade50),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isActive
                                        ? AppTheme.primary.withValues(
                                            alpha: 0.5,
                                          )
                                        : (isDark
                                              ? Colors.white12
                                              : Colors.grey.shade200),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            session.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.black54,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${updatedAt.day}/${updatedAt.month}/${updatedAt.year} ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppTheme.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      onPressed: () =>
                                          _deleteSession(session.id),
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _LongResponseTracker _startLongResponseTracker(String taskLabel) {
    final tracker = _LongResponseTracker();
    _activeLongResponseTrackers.add(tracker);
    if (!_notifyOnLongResponses) return tracker;
    tracker.timer = Timer(_longResponseThreshold, () {
      tracker.didCrossThreshold = true;
      if (!mounted || !_isLoading) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$taskLabel is taking longer than usual.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
    return tracker;
  }

  Future<void> _finishLongResponseTracker({
    required _LongResponseTracker tracker,
    required String notificationTitle,
    required String notificationBody,
  }) async {
    try {
      tracker.timer?.cancel();
      tracker.timer = null;
      if (!_notifyOnLongResponses || !tracker.didCrossThreshold) return;
      await _aiNotificationService.notifyAnswerReady(
        title: notificationTitle,
        body: notificationBody,
      );
    } finally {
      _activeLongResponseTrackers.remove(tracker);
    }
  }

  void _toggleLongResponseNotifications() {
    setState(() => _notifyOnLongResponses = !_notifyOnLongResponses);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _notifyOnLongResponses
              ? 'Long-response notifications enabled'
              : 'Long-response notifications disabled',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isQuestionPaperIntent({
    required String prompt,
    required bool hasAttachments,
  }) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final hasQuizKeyword = RegExp(
      r'\b(quiz|mcq|question paper|questionpaper|mock test|exam paper|practice test|test|assessment)\b',
    ).hasMatch(normalized);
    if (!hasQuizKeyword) return false;

    final explicitQuizIntent =
        RegExp(
          r'\b(make|create|generate|build|prepare|give|start)\s+(?:me\s+)?(?:a\s+)?(?:quick\s+)?(quiz|mcq|question paper|mock test|practice test|test|assessment)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(ask|test)\s+me\s+(?:\d+\s+)?(?:questions?|mcqs?|quiz)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(?:questions?|mcqs?)\s+(?:on|for|about|from)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(quiz|mcq|question paper|mock test|practice test|test|assessment)\s+(?:on|for|about|from)\b',
        ).hasMatch(normalized) ||
        normalized.contains('test me on');

    if (explicitQuizIntent) return true;
    if (hasAttachments) return true;

    return normalized.contains('quiz') ||
        normalized.contains('mcq') ||
        normalized.contains('question paper') ||
        normalized.contains('mock test') ||
        normalized.contains('practice test');
  }

  bool _hasActiveQuestionPaperResponse() {
    for (final message in _messages.reversed) {
      if (message.isUser) return false;
      if (message.quizActionPaper != null) return true;
    }
    return false;
  }

  bool _isQuestionPaperContinuationIntent(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;

    return RegExp(
          r'^(continue|next|more|another|proceed|keep going|go on)\b',
        ).hasMatch(normalized) ||
        normalized == 'continue quiz' ||
        normalized == 'continue the quiz' ||
        normalized == 'continue question paper' ||
        normalized == 'continue test';
  }

  /// Fallback UI for manual question-paper configuration when auto-detection
  /// from resource context is incomplete. Currently unused because
  /// [_buildQuestionPaperRequest] infers values automatically.
  // TODO(question-paper): Re-enable when user-editable QP config is exposed.
  // ignore: unused_element
  Future<_QuestionPaperRequestConfig?> _showQuestionPaperConfigDialog() async {
    final semesterController = TextEditingController(
      text: widget.resourceContext?.semester ?? '',
    );
    final branchController = TextEditingController(
      text: widget.resourceContext?.branch ?? '',
    );

    try {
      return await showDialog<_QuestionPaperRequestConfig>(
        context: context,
        builder: (dialogContext) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Text(
              'Question Paper Setup',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: semesterController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Semester',
                    hintText: 'e.g., 5',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: branchController,
                  decoration: const InputDecoration(
                    labelText: 'Branch',
                    hintText: 'e.g., CSE',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final semester = semesterController.text.trim();
                  final branch = branchController.text.trim();
                  if (semester.isEmpty || branch.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Semester and branch are required.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    _QuestionPaperRequestConfig(
                      semester: semester,
                      branch: branch,
                    ),
                  );
                },
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
    } finally {
      semesterController.dispose();
      branchController.dispose();
    }
  }

  String _extractRagAnswer(Map<String, dynamic> response) {
    return response['answer']?.toString() ??
        response['response']?.toString() ??
        response['data']?.toString() ??
        '';
  }

  String? _extractPrimarySourceFileId(Map<String, dynamic> response) {
    final direct = response['primary_source_file_id']?.toString().trim();
    if (direct != null &&
        direct.isNotEmpty &&
        !_isTransientPrimarySourceId(direct)) {
      return direct;
    }
    final data = response['data'];
    if (data is Map) {
      final nested = data['primary_source_file_id']?.toString().trim();
      if (nested != null &&
          nested.isNotEmpty &&
          !_isTransientPrimarySourceId(nested)) {
        return nested;
      }
    }
    return null;
  }

  bool _responseIndicatesNoLocal(Map<String, dynamic> response) {
    if (response['no_local'] == true ||
        response['insufficient_grounding'] == true) {
      return true;
    }
    final data = response['data'];
    if (data is Map &&
        (data['no_local'] == true || data['insufficient_grounding'] == true)) {
      return true;
    }
    return false;
  }

  bool _responseIndicatesInsufficientGrounding(Map<String, dynamic> response) {
    if (response['insufficient_grounding'] == true) return true;
    final answerOrigin = response['answer_origin']?.toString().toLowerCase();
    if (answerOrigin == 'insufficient_notes' ||
        answerOrigin == 'insufficientnotes') {
      return true;
    }
    final data = response['data'];
    if (data is Map) {
      if (data['insufficient_grounding'] == true) return true;
      final nestedAnswerOrigin = data['answer_origin']
          ?.toString()
          .toLowerCase();
      if (nestedAnswerOrigin == 'insufficient_notes' ||
          nestedAnswerOrigin == 'insufficientnotes') {
        return true;
      }
    }
    return false;
  }

  bool _responseUsesWebContent(Map<String, dynamic> response) {
    final retrievalMode = response['retrieval_mode']?.toString().toLowerCase();
    if (retrievalMode == 'web') return true;

    final answerOrigin = response['answer_origin']?.toString().toLowerCase();
    return answerOrigin == 'web_only' || answerOrigin == 'notes_plus_web';
  }

  void _guardUnexpectedWebResponse({
    required bool allowWeb,
    required Map<String, dynamic> response,
  }) {
    if (allowWeb || !_responseUsesWebContent(response)) return;

    throw StateError(
      'Web research is off, so this answer was blocked because it came from '
      'the web instead of your notes.',
    );
  }

  bool _looksLikeNoContextAnswer(String answer) {
    final normalized = answer.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return _noContextPhrases.any(normalized.contains);
  }

  Map<String, dynamic>? _decodeJsonMapFromText(String raw) {
    return decodeStructuredJsonMap(raw);
  }

  Future<String> _inferSubjectFromAttachments({
    required List<Map<String, dynamic>> attachments,
  }) async {
    if (attachments.isEmpty) return widget.resourceContext?.subject ?? '';
    final contextFilters = await _buildContextFiltersForRequest(
      ignoreSubject: true,
      prompt: 'identify subject from attached study material',
    );
    try {
      final response = await _api.queryRag(
        question:
            'Identify the exact academic subject from attached notes. '
            'Return strict JSON only: {"subject":"<subject name>"}',
        collegeId: widget.collegeId,
        sessionId: _activeSessionId,
        fileId: null,
        videoUrl: widget.resourceContext?.videoUrl,
        allowWeb: false,
        useOcr: true,
        forceOcr: true,
        attachments: attachments,
        filters: contextFilters,
        languageHint: 'en',
      );
      final answer = _extractRagAnswer(response);
      final decoded = _decodeJsonMapFromText(answer);
      final fromJson = decoded?['subject']?.toString().trim() ?? '';
      if (fromJson.isNotEmpty) return fromJson;
      final firstLine = answer.split('\n').first.trim();
      if (firstLine.isNotEmpty) return firstLine;
    } catch (e) {
      debugPrint('Subject inference failed: $e');
    }
    return widget.resourceContext?.subject ?? '';
  }

  String _attachmentTypeFromUrl(String url) {
    final normalized = url.toLowerCase();
    if (normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.webp')) {
      return 'image';
    }
    return 'pdf';
  }

  String _normalizeQuestionPaperLookupText(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), '')
        .replaceAll(RegExp(r'[^a-z0-9+#]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _tokenizeQuestionPaperLookupWords(String raw) {
    const ignored = <String>{
      'a',
      'an',
      'the',
      'and',
      'or',
      'from',
      'for',
      'of',
      'on',
      'about',
      'with',
      'using',
      'quiz',
      'test',
      'paper',
      'question',
      'questions',
      'notes',
      'note',
      'pdf',
      'file',
      'document',
      'material',
      'subject',
      'semester',
      'branch',
      'generate',
    };
    return _normalizeQuestionPaperLookupText(raw)
        .split(' ')
        .where((token) => token.length > 1 && !ignored.contains(token))
        .toList(growable: false);
  }

  double _scoreQuestionPaperResource(
    Resource resource, {
    required String query,
    String? preferredSemester,
    String? preferredBranch,
  }) {
    final normalizedQuery = _normalizeQuestionPaperLookupText(query);
    final titleText = _normalizeQuestionPaperLookupText(resource.title);
    final subjectText = _normalizeQuestionPaperLookupText(
      resource.subject ?? '',
    );
    final semesterText = _normalizeQuestionPaperLookupText(
      resource.semester ?? '',
    );
    final branchText = _normalizeQuestionPaperLookupText(resource.branch ?? '');
    final chapterText = _normalizeQuestionPaperLookupText(
      resource.chapter ?? '',
    );
    final topicText = _normalizeQuestionPaperLookupText(resource.topic ?? '');
    final searchable = [
      titleText,
      subjectText,
      semesterText,
      branchText,
      chapterText,
      topicText,
    ].where((part) => part.isNotEmpty).join(' ');
    final queryTokens = _tokenizeQuestionPaperLookupWords(query);

    var score = 0.0;
    if (normalizedQuery.isNotEmpty) {
      if (titleText == normalizedQuery) score += 9;
      if (subjectText == normalizedQuery) score += 7;
      if (titleText.contains(normalizedQuery)) score += 5;
      if (subjectText.contains(normalizedQuery)) score += 4;
      if (searchable.contains(normalizedQuery)) score += 2;
      if (RegExp(
        '\\b${RegExp.escape(normalizedQuery)}\\b',
      ).hasMatch(titleText)) {
        score += 2.5;
      }
    }

    if (queryTokens.isNotEmpty) {
      final titleHits = queryTokens
          .where((token) => titleText.contains(token))
          .length;
      final subjectHits = queryTokens
          .where((token) => subjectText.contains(token))
          .length;
      final searchableHits = queryTokens
          .where((token) => searchable.contains(token))
          .length;
      score += (titleHits / queryTokens.length) * 4.2;
      score += (subjectHits / queryTokens.length) * 2.5;
      score += (searchableHits / queryTokens.length) * 1.6;
    }

    final normalizedPreferredSemester =
        _normalizeAcademicFilterValue(
          preferredSemester ?? '',
          semesterOnly: true,
        ) ??
        '';
    final normalizedPreferredBranch =
        _normalizeAcademicFilterValue(preferredBranch ?? '') ?? '';
    if (normalizedPreferredSemester.isNotEmpty &&
        semesterText.contains(normalizedPreferredSemester.toLowerCase())) {
      score += 0.9;
    }
    if (normalizedPreferredBranch.isNotEmpty &&
        branchText.contains(normalizedPreferredBranch.toLowerCase())) {
      score += 0.6;
    }

    if (resource.fileUrl.trim().toLowerCase().contains('.pdf')) {
      score += 0.2;
    }

    return score;
  }

  List<Resource> _pickQuestionPaperResources(
    List<Resource> resources, {
    required String query,
    String? preferredSemester,
    String? preferredBranch,
    int limit = 6,
  }) {
    if (resources.isEmpty) return const [];
    final scored = resources
        .map(
          (resource) => (
            resource: resource,
            score: _scoreQuestionPaperResource(
              resource,
              query: query,
              preferredSemester: preferredSemester,
              preferredBranch: preferredBranch,
            ),
            subjectKey: _normalizeQuestionPaperLookupText(
              resource.subject ?? '',
            ),
          ),
        )
        .where((entry) => entry.score > 0)
        .toList();
    if (scored.isEmpty) {
      return resources.take(limit).toList(growable: false);
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final subjectGroups =
        <
          String,
          List<({Resource resource, double score, String subjectKey})>
        >{};
    for (final entry in scored) {
      final groupKey = entry.subjectKey.isNotEmpty
          ? entry.subjectKey
          : _normalizeQuestionPaperLookupText(entry.resource.title);
      subjectGroups
          .putIfAbsent(
            groupKey,
            () => <({Resource resource, double score, String subjectKey})>[],
          )
          .add(entry);
    }

    final rankedGroups = subjectGroups.entries.map((entry) {
      final ordered = [...entry.value]
        ..sort((a, b) => b.score.compareTo(a.score));
      final aggregate =
          ordered.take(3).fold<double>(0, (sum, item) => sum + item.score) +
          (ordered.length * 0.35);
      return (key: entry.key, aggregate: aggregate, items: ordered);
    }).toList()..sort((a, b) => b.aggregate.compareTo(a.aggregate));

    final topGroup = rankedGroups.first;
    final shouldPreferGroupedSelection =
        rankedGroups.length == 1 ||
        topGroup.items.length >= 2 ||
        topGroup.aggregate >=
            (rankedGroups.length > 1 ? rankedGroups[1].aggregate + 1.5 : 0);
    final selected = shouldPreferGroupedSelection
        ? topGroup.items.map((entry) => entry.resource)
        : scored.map((entry) => entry.resource);

    return selected
        .where((resource) => resource.fileUrl.trim().isNotEmpty)
        .take(limit)
        .toList(growable: false);
  }

  String _normalizeExternalUrl(String rawUrl) {
    return normalizeExternalUrl(rawUrl);
  }

  Uri? _buildExternalLaunchUri(String rawUrl) {
    final direct = buildExternalUri(rawUrl);
    if (direct != null) return direct;

    final trimmed = rawUrl.trim();
    if (trimmed.startsWith('/')) {
      final base = Uri.tryParse(AppConfig.apiUrl);
      if (base != null && base.host.isNotEmpty) {
        final resolved = base.resolve(trimmed).toString();
        return buildExternalUri(resolved);
      }
    }
    return null;
  }

  Future<void> _openExternalSourceLink({
    required Uri uri,
    required String sourceTitle,
  }) async {
    if (!mounted) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) return;
    final fallbackLaunched = await launchUrl(uri);
    if (fallbackLaunched || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open $sourceTitle')));
  }

  int _toSafeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<int> _resolveEffectiveAiBudget(Map<String, dynamic> profile) async {
    final snapshot = await AiTokenBudgetSnapshot.fromProfileWithLocalPremium(
      profile,
    );
    return snapshot.currentBudget;
  }

  bool _looksLikeTokenLimitError(String message) {
    final lowered = message.toLowerCase();
    return (lowered.contains('token') &&
            (lowered.contains('limit') ||
                lowered.contains('quota') ||
                lowered.contains('insufficient') ||
                lowered.contains('exceed') ||
                lowered.contains('remaining') ||
                lowered.contains('balance'))) ||
        (lowered.contains('credit') &&
            (lowered.contains('limit') || lowered.contains('insufficient')));
  }

  bool _looksLikeHighTrafficError(String message) {
    final lowered = message.toLowerCase();
    return lowered.contains('rate limit') ||
        lowered.contains('too many requests') ||
        lowered.contains('http 429') ||
        lowered.contains('high traffic');
  }

  String _presentAiErrorMessage(
    String message, {
    String fallback = 'StudyShare could not complete this AI request.',
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return fallback;
    if (_looksLikeTokenLimitError(trimmed)) {
      return _buildAiTokenShortageMessage();
    }
    if (_looksLikeHighTrafficError(trimmed)) {
      return 'StudyShare is seeing high traffic right now. Please try again in a moment.';
    }
    return trimmed;
  }

  bool _isTransientPrimarySourceId(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return true;
    return normalized.startsWith('inline_') ||
        normalized.startsWith('attachment_') ||
        normalized.contains(':chunk:') ||
        normalized.contains(':ocr:');
  }

  Future<void> _refreshAiTokenStatus({bool forceRefresh = false}) async {
    if (_isAiTokenStatusLoading || !_auth.isSignedIn) return;
    _isAiTokenStatusLoading = true;
    try {
      final profile = await _supabase.getCurrentUserProfile(
        forceRefresh: forceRefresh,
        maxAttempts: forceRefresh ? 2 : 1,
      );
      if (!mounted || profile.isEmpty) return;

      final budget = await _resolveEffectiveAiBudget(profile);
      final used = _toSafeInt(profile['ai_token_used']).clamp(0, budget);
      var remaining = _toSafeInt(profile['ai_token_remaining']);
      final derivedRemaining = budget > 0
          ? (budget - used).clamp(0, budget).toInt()
          : 0;
      if (remaining < 0 || remaining > budget) {
        remaining = derivedRemaining;
      }
      final threshold = math.max(
        _minLowTokenThreshold,
        budget > 0 ? (budget * 0.1).round() : _minLowTokenThreshold,
      );

      final prevBudget = _aiTokenBudgetTokens;
      final prevRemaining = _aiTokenRemainingTokens;
      setState(() {
        _aiTokenStatusLoaded = true;
        _aiTokenBudgetTokens = budget;
        _aiTokenRemainingTokens = remaining
            .clamp(0, math.max(0, budget))
            .toInt();
        _aiTokenLowThreshold = threshold;
        _showAiTokenLowBanner =
            _aiTokenBudgetTokens > 0 &&
            _aiTokenRemainingTokens <= _aiTokenLowThreshold;
        // Reset banner dismissal only if tokens increased or budget changed
        if ((_aiTokenRemainingTokens > prevRemaining) ||
            (_aiTokenBudgetTokens != prevBudget)) {
          _userDismissedTokenBanner = false;
        }
      });
    } catch (e) {
      debugPrint('Failed to refresh AI token status: $e');
    } finally {
      _isAiTokenStatusLoading = false;
    }
  }

  Future<void> _openAiTopUpDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PaywallDialog(
        onSuccess: () {
          if (!mounted) return;
          setState(() => _userDismissedTokenBanner = false);
          _refreshAiTokenStatus(forceRefresh: true);
        },
      ),
    );
    if (!mounted) return;
    await _refreshAiTokenStatus(forceRefresh: true);
  }

  void _showAiTokenTopUpSnackBar(String message) {
    if (!mounted) return;
    final now = DateTime.now();
    final lastShownAt = _lastAiTokenTopUpSnackBarAt;
    final isSameMessage = _lastAiTokenTopUpSnackBarMessage == message;
    if (lastShownAt != null &&
        isSameMessage &&
        now.difference(lastShownAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastAiTokenTopUpSnackBarAt = now;
    _lastAiTokenTopUpSnackBarMessage = message;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Recharge',
          onPressed: _openAiTopUpDialog,
        ),
      ),
    );
  }

  bool _shouldSuppressRapidDuplicateSend({
    required String userPrompt,
    required List<_ChatAttachment> activeAttachments,
  }) {
    final now = DateTime.now();
    final lastTriggeredAt = _lastSendTriggeredAt;
    _lastSendTriggeredAt = now;

    if (lastTriggeredAt != null &&
        now.difference(lastTriggeredAt) < const Duration(milliseconds: 600)) {
      return true;
    }

    final attachmentSignature = activeAttachments
        .map((a) => '${a.name}|${a.url}|${a.isPdf}')
        .join('||');
    final fingerprint = '${userPrompt.trim()}::$attachmentSignature';
    final lastFingerprint = _lastSendFingerprint;
    final lastFingerprintAt = _lastSendFingerprintAt;
    _lastSendFingerprint = fingerprint;
    _lastSendFingerprintAt = now;

    return lastFingerprint != null &&
        lastFingerprintAt != null &&
        lastFingerprint == fingerprint &&
        now.difference(lastFingerprintAt) < const Duration(seconds: 2);
  }

  void _showSourceUrlErrorSnackBar(String sourceTitle) {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastSourceLinkSnackBarAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastSourceLinkSnackBarAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invalid source URL for $sourceTitle')),
    );
  }

  bool _isTransientAiFailure(Object error) {
    final lowered = error.toString().toLowerCase();
    return lowered.contains('504') ||
        lowered.contains('timeout') ||
        lowered.contains('timed out') ||
        lowered.contains('gateway') ||
        lowered.contains('temporarily unavailable') ||
        lowered.contains('service unavailable') ||
        lowered.contains('connection reset') ||
        lowered.contains('connection closed');
  }

  String _cleanUserVisibleErrorMessage(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final lowered = raw.toLowerCase();
    if (_looksLikeHighTrafficError(raw)) {
      return 'StudyShare is seeing high traffic right now. Please try again in a moment.';
    }
    if (lowered.contains('connection reset') ||
        lowered.contains('reset by peer') ||
        lowered.contains('socketexception') ||
        lowered.contains('connection abort')) {
      return 'The AI server connection was interrupted. Please try again.';
    }
    if (lowered.contains('timed out') || lowered.contains('timeout')) {
      return 'The AI request took too long. Please try again in a moment.';
    }
    final hasHtmlPayload =
        lowered.contains('<!doctype html') ||
        lowered.contains('<html') ||
        lowered.contains('</html>');
    if (hasHtmlPayload) {
      // Capture both 4xx and 5xx HTTP status codes
      final codeMatch = RegExp(r'\b([45]\d{2})\b').firstMatch(raw);
      final code = codeMatch?.group(1);
      if (code != null) {
        if (code.startsWith('5')) {
          return 'Backend temporarily unavailable (HTTP $code). Please retry in a moment.';
        } else if (code.startsWith('4')) {
          return 'Request error (HTTP $code). Please check your request or credentials.';
        }
      }
      return 'Backend temporarily unavailable. Please retry in a moment.';
    }
    return raw;
  }

  void _handlePotentialTokenLimitError(String message) {
    if (!_looksLikeTokenLimitError(message)) return;
    if (mounted) {
      setState(() {
        _showAiTokenLowBanner = true;
      });
    }
    _showAiTokenTopUpSnackBar(_buildAiTokenShortageMessage());
    _refreshAiTokenStatus(forceRefresh: true);
  }

  String _buildAiTokenShortageMessage() {
    final remaining = visibleAiTokensFromRaw(_aiTokenRemainingTokens);
    final shortBy = math.max(
      1,
      visibleAiTokenShortfallFromRaw(_aiTokenRemainingTokens),
    );

    if (remaining <= 0) {
      return 'You do not have enough AI tokens to continue. Recharge at least $shortBy more token${shortBy == 1 ? '' : 's'} to keep using AI chat.';
    }

    return 'You only have $remaining AI token${remaining == 1 ? '' : 's'} left. Recharge at least $shortBy more token${shortBy == 1 ? '' : 's'} to finish this request.';
  }

  void _applyAiTokenShortageState(AIChatMessage message) {
    message.content = _buildAiTokenShortageMessage();
    message.primarySource = null;
    message.sources = const <RagSource>[];
    message.cached = false;
    message.noLocal = false;
    message.retrievalScore = null;
    message.llmConfidenceScore = null;
    message.combinedConfidence = null;
    message.ocrFailureAffectsRetrieval = false;
    message.ocrErrors = const <OcrErrorInfo>[];
    message.quizActionPaper = null;
    message.answerOrigin = null;
    message.liveSteps = const <AiLiveActivityStep>[];
    message.liveTitle = null;
    message.showLiveExport = false;
  }

  String? _normalizeAcademicFilterValue(
    String raw, {
    bool semesterOnly = false,
  }) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    final lowered = cleaned.toLowerCase();
    const generic = <String>{
      'general',
      'all',
      'any',
      'none',
      'na',
      'n/a',
      '-',
      '--',
    };
    if (generic.contains(lowered)) return null;
    if (!semesterOnly) return cleaned;
    final match = RegExp(r'\b([1-8])\b').firstMatch(cleaned);
    return match?.group(1);
  }

  List<Map<String, dynamic>> _serializeStickyAttachments() {
    return _stickyAttachments
        .map(
          (attachment) => <String, dynamic>{
            'name': attachment.name,
            'url': attachment.url,
            'is_pdf': attachment.isPdf,
            'file_id': attachment.fileId,
            'resource_id': attachment.resourceId,
            'notice_id': attachment.noticeId,
            'subject': attachment.subject,
            'semester': attachment.semester,
            'branch': attachment.branch,
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _toAttachmentPayload(
    List<_ChatAttachment> attachments,
  ) {
    return attachments
        .map(
          (item) => <String, dynamic>{
            'name': item.name,
            'url': item.url,
            'type': item.isPdf ? 'pdf' : 'image',
            if ((item.fileId ?? '').trim().isNotEmpty) 'file_id': item.fileId,
            if ((item.resourceId ?? '').trim().isNotEmpty)
              'resource_id': item.resourceId,
            if ((item.noticeId ?? '').trim().isNotEmpty)
              'notice_id': item.noticeId,
            if ((item.subject ?? '').trim().isNotEmpty) 'subject': item.subject,
            if ((item.semester ?? '').trim().isNotEmpty)
              'semester': item.semester,
            if ((item.branch ?? '').trim().isNotEmpty) 'branch': item.branch,
          },
        )
        .toList(growable: false);
  }

  List<_ChatAttachment> _deserializeStickyAttachments(
    List<Map<String, dynamic>> raw,
  ) {
    return raw
        .map(
          (item) => _ChatAttachment(
            name: item['name']?.toString().trim().isNotEmpty == true
                ? item['name']!.toString().trim()
                : 'Attachment',
            url: item['url']?.toString().trim() ?? '',
            isPdf: item['is_pdf'] == true,
            fileId: item['file_id']?.toString().trim().isNotEmpty == true
                ? item['file_id']!.toString().trim()
                : null,
            resourceId:
                item['resource_id']?.toString().trim().isNotEmpty == true
                ? item['resource_id']!.toString().trim()
                : null,
            noticeId: item['notice_id']?.toString().trim().isNotEmpty == true
                ? item['notice_id']!.toString().trim()
                : null,
            subject: item['subject']?.toString().trim().isNotEmpty == true
                ? item['subject']!.toString().trim()
                : null,
            semester: item['semester']?.toString().trim().isNotEmpty == true
                ? item['semester']!.toString().trim()
                : null,
            branch: item['branch']?.toString().trim().isNotEmpty == true
                ? item['branch']!.toString().trim()
                : null,
          ),
        )
        .where((attachment) => attachment.url.isNotEmpty)
        .toList();
  }

  void _rememberAttachmentsForContext(List<_ChatAttachment> usedAttachments) {
    if (usedAttachments.isEmpty) return;
    final merged = <_ChatAttachment>[..._stickyAttachments];

    for (final attachment in usedAttachments) {
      final existingIndex = merged.indexWhere(
        (item) => item.url == attachment.url,
      );
      if (existingIndex != -1) {
        merged[existingIndex] = attachment;
      } else {
        merged.add(attachment);
      }
    }

    const maxSticky = 5;
    if (merged.length > maxSticky) {
      merged.removeRange(0, merged.length - maxSticky);
    }

    _stickyAttachments
      ..clear()
      ..addAll(merged);
  }

  void _clearStickyContext() {
    _stickyAttachments.clear();
  }

  Future<List<Map<String, dynamic>>> _loadSubjectAttachments({
    required String semester,
    required String branch,
    required String inferredSubject,
  }) async {
    try {
      final subject = inferredSubject.trim();
      final normalizedSemester = _normalizeAcademicFilterValue(
        semester,
        semesterOnly: true,
      );
      final normalizedBranch = _normalizeAcademicFilterValue(branch);
      if (subject.isEmpty) {
        return const [];
      }
      List<Resource> scoped = <Resource>[];
      scoped = await _supabase.getResources(
        collegeId: widget.collegeId,
        semester: normalizedSemester,
        branch: normalizedBranch,
        subject: subject,
        limit: 8,
      );

      if (scoped.isEmpty && subject.isNotEmpty && normalizedSemester != null) {
        scoped = await _supabase.getResources(
          collegeId: widget.collegeId,
          semester: normalizedSemester,
          subject: subject,
          limit: 8,
        );
      }

      if (scoped.isEmpty && subject.isNotEmpty) {
        scoped = await _supabase.getResources(
          collegeId: widget.collegeId,
          subject: subject,
          limit: 8,
        );
      }

      if (scoped.isEmpty && subject.isNotEmpty) {
        scoped = await _supabase.getResources(
          collegeId: widget.collegeId,
          semester: normalizedSemester,
          branch: normalizedBranch,
          searchQuery: subject,
          limit: 8,
        );
      }

      if (scoped.isEmpty && subject.isNotEmpty) {
        scoped = await _supabase.getResources(
          collegeId: widget.collegeId,
          searchQuery: subject,
          limit: 8,
        );
      }

      final ranked = _pickQuestionPaperResources(
        scoped,
        query: subject,
        preferredSemester: normalizedSemester,
        preferredBranch: normalizedBranch,
        limit: 8,
      );

      return ranked
          .where((resource) => resource.fileUrl.trim().isNotEmpty)
          .map(
            (resource) => <String, dynamic>{
              'name': resource.title,
              'url': resource.fileUrl,
              'type': _attachmentTypeFromUrl(resource.fileUrl),
              'resource_id': resource.id,
              'subject': resource.subject,
              'semester': resource.semester,
              'branch': resource.branch,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('Subject resource lookup failed: $e');
      return const [];
    }
  }

  String _buildQuestionPaperStrictRetryMessage(
    _QuestionPaperRetryReason? retryReason,
  ) {
    switch (retryReason) {
      case _QuestionPaperRetryReason.placeholderContent:
        return 'Your last response contained low-quality or placeholder content.';
      case _QuestionPaperRetryReason.groundingFailure:
        return 'Your last response did not use the attached notes well enough.';
      case _QuestionPaperRetryReason.invalidJson:
      case null:
        return 'Your last response was not valid JSON.';
    }
  }

  String _buildQuestionPaperPrompt({
    required String userPrompt,
    required String semester,
    required String branch,
    required String inferredSubject,
    bool preferNoticeSources = false,
    bool strictAntiPlaceholder = false,
    _QuestionPaperRetryReason? strictRetryReason,
  }) {
    final scopeHints = <String>[
      if (inferredSubject.trim().isNotEmpty) 'topic=${inferredSubject.trim()}',
      if (semester.trim().isNotEmpty) 'semester=$semester',
      if (branch.trim().isNotEmpty) 'branch=$branch',
    ];
    final strictRetryMessage = strictAntiPlaceholder
        ? _buildQuestionPaperStrictRetryMessage(strictRetryReason)
        : '';

    return [
      userPrompt.trim(),
      if (scopeHints.isNotEmpty) 'Scope hints: ${scopeHints.join(', ')}.',
      if (preferNoticeSources)
        'Grounding rule: if the retrieved source is a notice or announcement, create factual MCQs only from that notice content. Use its exact dates, timings, platform instructions, completion rules, stated purpose, and named details. Do not turn a notice into generic theory questions.',
      if (strictAntiPlaceholder)
        'Retry guidance: return a clean, exam-like MCQ paper grounded only in the selected local source material. '
            'Use complete question stems, 4 complete options, and valid JSON only. '
            '$strictRetryMessage',
    ].join('\n\n');
  }

  String _normalizeTemplateToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  bool _isTemplateToken(String value) {
    final token = _normalizeTemplateToken(value);
    if (token.isEmpty) return true;
    const templateTokens = <String>{
      'question text',
      'subject name',
      'a option',
      'b option',
      'c option',
      'd option',
      'option a',
      'option b',
      'option c',
      'option d',
      'question statement',
      'specific paper title',
      'exact subject name',
    };
    return templateTokens.contains(token);
  }

  String _labelForOcrCode(String code) {
    switch (code.toLowerCase()) {
      case 'ocr_empty':
        return 'empty result';
      case 'ocr_unavailable':
        return 'unavailable';
      case 'ocr_failed':
      default:
        return 'failed';
    }
  }

  bool _isPlaceholderQuestion({
    required String question,
    required List<String> options,
  }) {
    if (_isTemplateToken(question)) return true;
    if (options.isEmpty) return true;
    var templateOptionCount = 0;
    for (final option in options) {
      if (_isTemplateToken(option)) {
        templateOptionCount++;
      }
    }
    return templateOptionCount >= 2;
  }

  bool _looksLikeGenericQuestionStem(String question) {
    final normalized = question.trim().toLowerCase();
    final match = RegExp(
      r'(?:what is true about|which statement best describes|what is the most accurate description of|select the most accurate statement about|which description correctly matches)\s+(.+?)\??$',
    ).firstMatch(normalized);
    if (match == null) return false;
    final concept = (match.group(1) ?? '')
        .replaceAll(RegExp(r'[^a-z\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const genericConcepts = <String>{
      'method',
      'methods',
      'process',
      'processes',
      'system',
      'systems',
      'technique',
      'techniques',
      'approach',
      'approaches',
      'concept',
      'term',
      'property',
      'properties',
    };
    return genericConcepts.contains(concept);
  }

  bool _isLowQualityQuestionPaper(AiQuestionPaper paper) {
    if (paper.questions.length < 3) return true;
    if (_isTemplateToken(paper.subject) || _isTemplateToken(paper.title)) {
      return true;
    }

    var placeholderCount = 0;
    var sentenceCompletionCount = 0;
    var noisyOptionCount = 0;
    var pronounOptionCount = 0;
    var genericStemCount = 0;
    var genericOptionCount = 0;
    final normalizedQuestions = <String>{};
    for (final q in paper.questions) {
      if (_isPlaceholderQuestion(question: q.question, options: q.options)) {
        placeholderCount++;
      }
      if (_looksLikeGenericQuestionStem(q.question)) {
        genericStemCount++;
      }
      if (q.question.toLowerCase().startsWith(
        'which term best completes this statement from your notes?',
      )) {
        sentenceCompletionCount++;
      }
      for (final option in q.options) {
        final normalizedOption = option.trim().toLowerCase();
        if (RegExp(
          r'^(nextct|kittu|syllabus|complete|page|date)$',
        ).hasMatch(normalizedOption)) {
          noisyOptionCount++;
        }
        if (normalizedOption.contains('[figure')) {
          noisyOptionCount++;
        }
        if (RegExp(
          r'^(they|it|this|these|those|there|here)$',
        ).hasMatch(normalizedOption)) {
          pronounOptionCount++;
        }
        if (RegExp(
          r'^(method|methods|process|processes|system|systems|technique|techniques|approach|approaches)$',
        ).hasMatch(normalizedOption)) {
          genericOptionCount++;
        }
      }
      normalizedQuestions.add(_normalizeTemplateToken(q.question));
    }

    final questionCount = paper.questions.length;
    if (placeholderCount >= math.max(2, (questionCount * 0.4).ceil())) {
      return true;
    }
    if (sentenceCompletionCount >= math.max(2, (questionCount * 0.75).ceil())) {
      return true;
    }
    if (genericStemCount > (questionCount / 2).floor()) return true;
    if (noisyOptionCount >= math.max(3, questionCount)) return true;
    if (pronounOptionCount >= math.max(3, questionCount)) return true;
    if (genericOptionCount >= math.max(3, questionCount + 1)) return true;
    final duplicateRatio =
        1 - (normalizedQuestions.length / questionCount.clamp(1, 9999));
    if (duplicateRatio > 0.55) return true;
    return false;
  }

  AiQuestionPaper? _parseQuestionPaper({
    required String rawResponse,
    required String semester,
    required String branch,
    required String fallbackSubject,
    required int contextResourceCount,
  }) {
    final parsed = parseAiQuestionPaper(
      rawResponse: rawResponse,
      semester: semester,
      branch: branch,
      fallbackSubject: fallbackSubject,
      contextResourceCount: contextResourceCount,
    );
    if (parsed == null) return null;

    final filteredQuestions = parsed.questions
        .where(
          (q) =>
              !_isPlaceholderQuestion(question: q.question, options: q.options),
        )
        .toList(growable: false);
    if (filteredQuestions.isEmpty) return null;

    return parsed.copyWith(
      subject: parsed.subject.trim().isEmpty ? 'General' : parsed.subject,
      questions: filteredQuestions,
    );
  }

  String _buildQuestionPaperSummary(AiQuestionPaper paper) {
    return 'Question paper generated for ${paper.subject} '
        '(Sem ${paper.semester}, ${paper.branch}).\n'
        'Questions: ${paper.questions.length} | Context sources analyzed: ${paper.pyqCount}\n\n'
        'Tap "Start Quiz" to attempt the full-screen quiz.';
  }

  bool _looksLikeQuizJsonPayload(String rawResponse) {
    final normalized = rawResponse.toLowerCase();
    return (normalized.contains('"questions"') ||
            normalized.contains('"mcq"') ||
            normalized.contains('"quiz"')) &&
        (normalized.contains('"options"') ||
            normalized.contains('"choices"') ||
            normalized.contains('"answer"'));
  }

  Future<AiQuestionPaper?> _maybePromoteQuizFromAssistantResponse({
    required String rawResponse,
    required String userPrompt,
    required bool hasAttachmentContext,
    required int contextResourceCount,
  }) async {
    if (rawResponse.trim().isEmpty) return null;

    final promptLooksQuiz = _isQuestionPaperIntent(
      prompt: userPrompt,
      hasAttachments: hasAttachmentContext,
    );
    final responseLooksQuiz = _looksLikeQuizJsonPayload(rawResponse);
    if (!promptLooksQuiz && !responseLooksQuiz) return null;

    final config = await _resolveQuestionPaperConfig();
    if (config == null) return null;

    final subjectHint = _extractTopicFromPrompt(userPrompt);
    final parsed = _parseQuestionPaper(
      rawResponse: rawResponse,
      semester: config.semester,
      branch: config.branch,
      fallbackSubject: subjectHint,
      contextResourceCount: contextResourceCount,
    );
    if (parsed == null) return null;
    if (_isLowQualityQuestionPaper(parsed)) return null;
    return parsed;
  }

  Future<void> _handleQuestionPaperGeneration({
    required String userPrompt,
    required String userVisible,
    required List<Map<String, dynamic>> attachmentPayload,
    required _QuestionPaperRequestConfig config,
    required String resolvedSubject,
    required bool pinnedScopeOnly,
    required bool preferTopicOnlyScope,
  }) async {
    final tracker = _startLongResponseTracker('Question paper generation');
    final history = _buildStructuredHistory();
    final aiMessage = AIChatMessage(
      isUser: false,
      content: '',
      liveTitle: 'Generating your question paper',
      liveSteps: _buildQuestionPaperLiveSteps(
        notesDescription:
            'Collecting the most relevant local sources for this paper.',
      ),
    );

    setState(() {
      _messages.add(AIChatMessage(isUser: true, content: userVisible));
      _messages.add(aiMessage);
      aiMessage.liveSteps = _updateLiveStepList(
        aiMessage.liveSteps,
        'qp_context',
        status: AiLiveActivityStatus.active,
      );
      _isLoading = true;
      _controller.clear();
      _attachments.clear();
    });
    await _persistCurrentSession();
    await _scrollToBottom();

    try {
      final searchAllForPrompt = _shouldSearchAllPdfsForPrompt(userPrompt);
      final noticeRequestContext = _buildNoticeRequestContext(
        prompt: userPrompt,
        forQuestionPaper: true,
      );
      final contextFilters = await _buildContextFiltersForRequest(
        ignoreSubject: searchAllForPrompt,
        prompt: userPrompt,
      );
      final sourceSwitchForTurn = _promptRequestsAllPdfs(userPrompt);
      final languageHint = _shouldForceEnglish(userPrompt) ? 'en' : 'auto';
      final dialectIntensity = languageHint == 'en'
          ? null
          : (_detectDialectIntensity(userPrompt) == 'strong' ? 'strong' : null);
      final excludeFileIds = (_lastPrimarySourceFileId ?? '').trim().isNotEmpty
          ? <String>[_lastPrimarySourceFileId!.trim()]
          : null;
      final inferredSubject = resolvedSubject.trim();
      final effectiveQuestionPaperFilters = <String, dynamic>{
        ...?contextFilters,
      };
      if (preferTopicOnlyScope) {
        effectiveQuestionPaperFilters.remove('semester');
        effectiveQuestionPaperFilters.remove('branch');
      }
      if (!preferTopicOnlyScope && config.semester.trim().isNotEmpty) {
        effectiveQuestionPaperFilters['semester'] = config.semester.trim();
      }
      if (!preferTopicOnlyScope &&
          config.branch.trim().isNotEmpty &&
          config.branch.trim().toLowerCase() != 'general') {
        effectiveQuestionPaperFilters['branch'] = config.branch.trim();
      }

      final contextAttachments = pinnedScopeOnly || inferredSubject.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _loadSubjectAttachments(
              semester: preferTopicOnlyScope ? '' : config.semester,
              branch: preferTopicOnlyScope ? '' : config.branch,
              inferredSubject: inferredSubject,
            );
      final groundingAttachments = <Map<String, dynamic>>[...attachmentPayload];
      final displayAttachments = <Map<String, dynamic>>[
        ...groundingAttachments,
        ...contextAttachments,
      ];
      final totalAttachmentCount = displayAttachments.length;
      final hasPdfAttachments = groundingAttachments.any(
        (item) => item['type']?.toString().toLowerCase() == 'pdf',
      );
      final hasImageAttachments = groundingAttachments.any(
        (item) => item['type']?.toString().toLowerCase() == 'image',
      );
      final noteSources = _activitySourcesFromAttachmentMaps(
        displayAttachments,
      );
      final notesDescription = noteSources.isNotEmpty
          ? 'Using ${noteSources.length} grounded source'
                '${noteSources.length == 1 ? '' : 's'} for grounding.'
          : noticeRequestContext.preferNoticeSources
          ? 'Searching StudyShare for the matching notice content or study material.'
          : 'Searching the available study material for this paper.';
      if (mounted) {
        setState(() {
          aiMessage.liveTitle = _buildQuestionPaperLiveTitle(
            inferredSubject: inferredSubject,
            config: config,
          );
          aiMessage.liveSteps = _updateLiveStepList(
            aiMessage.liveSteps,
            'qp_context',
            status: AiLiveActivityStatus.completed,
            description: inferredSubject.trim().isNotEmpty
                ? 'Resolved topic: $inferredSubject'
                : ((config.semester.trim().isNotEmpty ||
                          config.branch.trim().isNotEmpty)
                      ? 'Using ${[if (config.semester.trim().isNotEmpty) 'Sem ${config.semester.trim()}', if (config.branch.trim().isNotEmpty) config.branch.trim().toUpperCase()].join(' • ')} context.'
                      : 'Searching the available study material for the right topic.'),
          );
          aiMessage.liveSteps = _updateLiveStepList(
            aiMessage.liveSteps,
            'qp_notes',
            status: noteSources.isNotEmpty
                ? AiLiveActivityStatus.completed
                : AiLiveActivityStatus.warning,
            description: notesDescription,
            sources: noteSources,
          );
          aiMessage.liveSteps = _updateLiveStepList(
            aiMessage.liveSteps,
            'qp_generate',
            status: AiLiveActivityStatus.active,
          );
        });
      }
      var lastAnswer = '';
      AiQuestionPaper? paper;
      var forceOcr = false;
      var aiInvoked = false;
      var ocrRetryUsed = false;
      _QuestionPaperRetryReason? strictRetryReason;
      for (var attempt = 0; attempt < 2 && paper == null; attempt++) {
        final strictMode = attempt > 0;
        final attemptId = attempt == 0
            ? 'attempt_1'
            : (!ocrRetryUsed && forceOcr ? 'attempt_ocr' : 'attempt_strict');
        final attemptTitle = attempt == 0
            ? 'Attempt 1'
            : (!ocrRetryUsed && forceOcr ? 'OCR retry' : 'Strict retry');
        if (attemptId == 'attempt_ocr') {
          ocrRetryUsed = true;
        }
        if (mounted) {
          setState(() {
            aiMessage.liveSteps = _upsertLiveEventList(
              aiMessage.liveSteps,
              'qp_generate',
              AiLiveActivityEvent(
                id: attemptId,
                title: attemptTitle,
                status: AiLiveActivityStatus.active,
              ),
            );
          });
        }
        final prompt = _buildQuestionPaperPrompt(
          userPrompt: userPrompt,
          semester: config.semester,
          branch: config.branch,
          inferredSubject: inferredSubject,
          preferNoticeSources: noticeRequestContext.preferNoticeSources,
          strictAntiPlaceholder: strictMode,
          strictRetryReason: strictRetryReason,
        );
        final allowWeb =
            _allowWebMode &&
            groundingAttachments.isEmpty &&
            !noticeRequestContext.preferNoticeSources;
        final response = await _api.queryRag(
          question: prompt,
          collegeId: widget.collegeId,
          sessionId: _activeSessionId,
          topK: 15,
          minScore: 0.32,
          fileId: searchAllForPrompt || noticeRequestContext.preferNoticeSources
              ? null
              : widget.resourceContext?.fileId,
          videoUrl: noticeRequestContext.preferNoticeSources
              ? null
              : widget.resourceContext?.videoUrl,
          allowWeb: allowWeb,
          useOcr: hasImageAttachments || forceOcr,
          forceOcr: forceOcr,
          attachments: groundingAttachments,
          history: history,
          filters: effectiveQuestionPaperFilters,
          sourceSwitchForTurn: sourceSwitchForTurn,
          excludeFileIds: noticeRequestContext.preferNoticeSources
              ? null
              : excludeFileIds,
          noticeIds: noticeRequestContext.noticeIds,
          sourceHint: noticeRequestContext.preferNoticeSources
              ? 'notice'
              : null,
          dialectIntensity: dialectIntensity,
          languageHint: languageHint,
          generationMode: 'question_paper',
        );
        final primarySourceFileId = _extractPrimarySourceFileId(response);
        if (primarySourceFileId != null && primarySourceFileId.isNotEmpty) {
          _lastPrimarySourceFileId = primarySourceFileId;
        }
        aiInvoked = true;
        final answer = _extractRagAnswer(response);
        lastAnswer = answer;
        final groundingLooksInsufficient =
            _responseIndicatesInsufficientGrounding(response);
        AiQuestionPaper? preParsedGroundedCandidate;
        if (groundingLooksInsufficient) {
          preParsedGroundedCandidate = _parseQuestionPaper(
            rawResponse: answer,
            semester: config.semester,
            branch: config.branch,
            fallbackSubject: inferredSubject,
            contextResourceCount: totalAttachmentCount,
          );
        }
        if (groundingLooksInsufficient &&
            (preParsedGroundedCandidate == null ||
                _isLowQualityQuestionPaper(preParsedGroundedCandidate))) {
          const noNotesMessage =
              'No related local study material or notice content was found for this paper yet. Add a matching source and try again.';
          if (mounted) {
            setState(() {
              aiMessage.content = noNotesMessage;
              aiMessage.showLiveExport = false;
              aiMessage.answerOrigin = AiAnswerOrigin.insufficientNotes;
              aiMessage.liveSteps = _updateLiveStepList(
                aiMessage.liveSteps,
                'qp_generate',
                status: AiLiveActivityStatus.failed,
                description:
                    'Question paper generation stopped because the local grounding was not strong enough.',
              );
              aiMessage.liveSteps = _updateLiveStepList(
                aiMessage.liveSteps,
                'qp_validate',
                status: AiLiveActivityStatus.failed,
                description:
                    'A paper cannot be validated without grounded local sources.',
              );
              aiMessage.liveSteps = _updateLiveStepList(
                aiMessage.liveSteps,
                'qp_ready',
                status: AiLiveActivityStatus.failed,
                description:
                    'Upload matching study material to enable PDF export.',
              );
            });
          }
          await _persistCurrentSession();
          return;
        }
        aiMessage.answerOrigin = AiAnswerOriginX.fromWireValue(
          response['answer_origin']?.toString(),
        );
        final noLocal =
            _responseIndicatesNoLocal(response) ||
            _looksLikeNoContextAnswer(answer);
        final responseSourcesRaw = response['sources'] as List?;
        final responseSources = responseSourcesRaw == null
            ? const <RagSource>[]
            : responseSourcesRaw
                  .whereType<Map>()
                  .map(
                    (entry) =>
                        RagSource.fromJson(Map<String, dynamic>.from(entry)),
                  )
                  .toList(growable: false);
        final attemptSources = _activitySourcesFromRagSources(responseSources);
        debugPrint(
          'QuizGen attempt=${attempt + 1} noLocal=$noLocal '
          'attachments=${displayAttachments.length} '
          'answerLen=${answer.length}',
        );
        if (noLocal && hasPdfAttachments && !forceOcr) {
          strictRetryReason = _QuestionPaperRetryReason.groundingFailure;
          if (mounted) {
            setState(() {
              aiMessage.liveSteps = _upsertLiveEventList(
                aiMessage.liveSteps,
                'qp_generate',
                AiLiveActivityEvent(
                  id: attemptId,
                  title: attemptTitle,
                  status: AiLiveActivityStatus.warning,
                  detail:
                      'The first pass did not find enough grounded note context. Retrying with OCR enabled.',
                  sources: attemptSources,
                ),
              );
            });
          }
          forceOcr = true;
          continue;
        }
        final candidate =
            preParsedGroundedCandidate ??
            _parseQuestionPaper(
              rawResponse: answer,
              semester: config.semester,
              branch: config.branch,
              fallbackSubject: inferredSubject,
              contextResourceCount: totalAttachmentCount,
            );
        if (candidate == null) {
          debugPrint(
            'QuizGen parse failed attempt=${attempt + 1}. '
            'Preview=${answer.replaceAll('\n', ' ').substring(0, answer.length > 240 ? 240 : answer.length)}',
          );
          strictRetryReason = _QuestionPaperRetryReason.invalidJson;
          if (mounted) {
            setState(() {
              aiMessage.liveSteps = _upsertLiveEventList(
                aiMessage.liveSteps,
                'qp_generate',
                AiLiveActivityEvent(
                  id: attemptId,
                  title: attemptTitle,
                  status: AiLiveActivityStatus.failed,
                  detail:
                      'The response could not be parsed into a usable question paper format.',
                  sources: attemptSources,
                ),
              );
            });
          }
          continue;
        }
        if (_isLowQualityQuestionPaper(candidate)) {
          debugPrint(
            'Discarded low-quality question paper response '
            '(attempt=${attempt + 1}).',
          );
          strictRetryReason = _QuestionPaperRetryReason.placeholderContent;
          if (mounted) {
            setState(() {
              aiMessage.liveSteps = _upsertLiveEventList(
                aiMessage.liveSteps,
                'qp_generate',
                AiLiveActivityEvent(
                  id: attemptId,
                  title: attemptTitle,
                  status: AiLiveActivityStatus.warning,
                  detail:
                      'The draft was incomplete, so StudyShare is trying a stricter generation pass.',
                  sources: attemptSources,
                ),
              );
            });
          }
          continue;
        }
        if (mounted) {
          setState(() {
            aiMessage.liveSteps = _upsertLiveEventList(
              aiMessage.liveSteps,
              'qp_generate',
              AiLiveActivityEvent(
                id: attemptId,
                title: attemptTitle,
                status: AiLiveActivityStatus.completed,
                detail: 'A valid question paper draft was generated.',
                sources: attemptSources,
              ),
            );
            aiMessage.liveSteps = _updateLiveStepList(
              aiMessage.liveSteps,
              'qp_generate',
              status: AiLiveActivityStatus.completed,
            );
            aiMessage.liveSteps = _updateLiveStepList(
              aiMessage.liveSteps,
              'qp_validate',
              status: AiLiveActivityStatus.active,
            );
          });
        }
        paper = candidate;
      }
      if (aiInvoked) {
        _supabase.markAiTokenBalanceStale();
        _refreshAiTokenStatus(forceRefresh: true);
      }

      if (paper == null) {
        setState(() {
          final fallback =
              'Failed to generate a valid question paper. Try again with '
              'a shorter topic, clearer notes, or upload additional material.';
          if (_looksLikeQuizJsonPayload(lastAnswer)) {
            aiMessage.content = fallback;
          } else {
            aiMessage.content = lastAnswer.trim().isEmpty
                ? fallback
                : lastAnswer;
          }
          aiMessage.showLiveExport = false;
          aiMessage.liveSteps = _updateLiveStepList(
            aiMessage.liveSteps,
            'qp_generate',
            status: AiLiveActivityStatus.failed,
            description:
                'StudyShare could not generate a valid paper from the current notes.',
          );
          aiMessage.liveSteps = _updateLiveStepList(
            aiMessage.liveSteps,
            'qp_validate',
            status: AiLiveActivityStatus.failed,
            description: 'The generated response was not valid enough to use.',
          );
          aiMessage.liveSteps = _updateLiveStepList(
            aiMessage.liveSteps,
            'qp_ready',
            status: AiLiveActivityStatus.failed,
            description:
                'Download stays unavailable until a valid paper is ready.',
          );
        });
        await _persistCurrentSession();
        return;
      }
      final generatedPaper = paper;

      setState(() {
        aiMessage.content = _buildQuestionPaperSummary(generatedPaper);
        aiMessage.quizActionPaper = generatedPaper;
        aiMessage.showLiveExport = true;
        aiMessage.liveSteps = _updateLiveStepList(
          aiMessage.liveSteps,
          'qp_validate',
          status: AiLiveActivityStatus.completed,
          description:
              'Questions, options, and explanations were validated successfully.',
        );
        aiMessage.liveSteps = _updateLiveStepList(
          aiMessage.liveSteps,
          'qp_ready',
          status: AiLiveActivityStatus.completed,
          description: 'You can start the quiz or download the PDF now.',
        );
      });
      await _persistCurrentSession();
    } catch (e) {
      if (!mounted) return;
      final errorMessage = _presentAiErrorMessage(
        e.toString().replaceFirst('Exception: ', ''),
        fallback: 'StudyShare could not finish the question paper right now.',
      );
      setState(() {
        aiMessage.content = errorMessage;
        aiMessage.showLiveExport = false;
        aiMessage.liveSteps = _updateLiveStepList(
          aiMessage.liveSteps,
          'qp_generate',
          status: AiLiveActivityStatus.failed,
          description: 'The paper generation request failed before completion.',
        );
        aiMessage.liveSteps = _updateLiveStepList(
          aiMessage.liveSteps,
          'qp_validate',
          status: AiLiveActivityStatus.failed,
        );
        aiMessage.liveSteps = _updateLiveStepList(
          aiMessage.liveSteps,
          'qp_ready',
          status: AiLiveActivityStatus.failed,
        );
      });
      await _persistCurrentSession();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        await _scrollToBottom();
      }
      await _finishLongResponseTracker(
        tracker: tracker,
        notificationTitle: 'Question Paper Ready',
        notificationBody: 'Your generated quiz is ready to attempt.',
      );
    }
  }

  Future<void> _openWebSourceInAppOrExternal({
    required Uri uri,
    required String sourceTitle,
  }) async {
    if (!mounted) return;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebSourceViewerScreen(
            initialUrl: uri.toString(),
            title: sourceTitle,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Opening web source in app failed for "$sourceTitle": $e');
      await _openExternalSourceLink(uri: uri, sourceTitle: sourceTitle);
    }
  }

  Future<void> _handleSummaryExport({
    required String userPrompt,
    required String userVisible,
    required List<Map<String, dynamic>> attachmentPayload,
  }) async {
    final tracker = _startLongResponseTracker('Summary export');
    setState(() {
      _messages.add(AIChatMessage(isUser: true, content: userVisible));
      _isLoading = true;
      _controller.clear();
      _attachments.clear();
    });
    await _persistCurrentSession();
    await _scrollToBottom();

    try {
      final searchAllForPrompt = _shouldSearchAllPdfsForPrompt(userPrompt);
      final contextFilters = await _buildContextFiltersForRequest(
        ignoreSubject: searchAllForPrompt,
        prompt: userPrompt,
      );
      final sourceSwitchForTurn = _promptRequestsAllPdfs(userPrompt);
      final languageHint = _shouldForceEnglish(userPrompt) ? 'en' : 'auto';
      final dialectIntensity = languageHint == 'en'
          ? null
          : (_detectDialectIntensity(userPrompt) == 'strong' ? 'strong' : null);
      final excludeFileIds = (_lastPrimarySourceFileId ?? '').trim().isNotEmpty
          ? <String>[_lastPrimarySourceFileId!.trim()]
          : null;
      final hasOcrEligibleAttachments = attachmentPayload.any((item) {
        final type = item['type']?.toString().toLowerCase();
        return type == 'pdf' || type == 'image';
      });
      final prompt = _buildRagPrompt(
        userPrompt:
            '$userPrompt\n\nOutput instruction: generate a structured report-ready summary.',
        hasAttachments: attachmentPayload.isNotEmpty,
        searchAllPdfs: searchAllForPrompt,
      );
      Map<String, dynamic>? response;
      String answer = '';
      Object? lastError;

      for (var attempt = 0; attempt < 2; attempt++) {
        // First attempt uses local-only; second attempt enables web fallback.
        final allowWeb = attempt > 0 && _allowWebMode;
        try {
          final candidate = await _api.queryRag(
            question: prompt,
            collegeId: widget.collegeId,
            sessionId: null,
            topK: 6,
            fileId: searchAllForPrompt ? null : widget.resourceContext?.fileId,
            videoUrl: widget.resourceContext?.videoUrl,
            allowWeb: allowWeb,
            useOcr: hasOcrEligibleAttachments,
            forceOcr: hasOcrEligibleAttachments && attempt > 0,
            attachments: attachmentPayload,
            history: const <Map<String, String>>[],
            filters: contextFilters,
            sourceSwitchForTurn: sourceSwitchForTurn,
            excludeFileIds: excludeFileIds,
            dialectIntensity: dialectIntensity,
            languageHint: languageHint,
          );
          final primarySourceFileId = _extractPrimarySourceFileId(candidate);
          if (primarySourceFileId != null && primarySourceFileId.isNotEmpty) {
            _lastPrimarySourceFileId = primarySourceFileId;
          }
          final candidateAnswer = _sanitizeAssistantAnswerText(
            _extractRagAnswer(candidate).trim(),
          );
          final noLocal =
              _responseIndicatesNoLocal(candidate) ||
              _looksLikeNoContextAnswer(candidateAnswer);
          final shouldRetryWithWeb =
              _allowWebMode &&
              !allowWeb &&
              (candidateAnswer.isEmpty || noLocal);

          response = candidate;
          answer = candidateAnswer;
          if (shouldRetryWithWeb) {
            continue;
          }
          break;
        } catch (e) {
          lastError = e;
          final retryOnWeb =
              _allowWebMode && attempt == 0 && _isTransientAiFailure(e);
          if (retryOnWeb) {
            continue;
          }
          rethrow;
        }
      }

      if (response == null && lastError != null) {
        throw lastError;
      }
      if (response != null) {
        _supabase.markAiTokenBalanceStale();
        _refreshAiTokenStatus(forceRefresh: true);
      }
      if (answer.isEmpty) {
        setState(() {
          _messages.add(
            AIChatMessage(
              isUser: false,
              content: _allowWebMode
                  ? 'I could not generate a summary from your files. Try uploading a clearer PDF or asking for a shorter chapter-wise summary.'
                  : 'I could not generate a summary from the uploaded files.',
            ),
          );
        });
        await _persistCurrentSession();
        return;
      }

      final file = await _summaryPdfService.saveSummaryPdf(
        title: 'AI_Report_${DateTime.now().millisecondsSinceEpoch}',
        summary: answer,
        subtitle: 'AI Chat Summary',
        watermarkText: 'StudyShare',
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          AIChatMessage(
            isUser: false,
            content:
                'Report generated successfully. The PDF has been saved on your device.',
          ),
        );
      });
      await _persistCurrentSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved PDF: ${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          AIChatMessage(
            isUser: false,
            content:
                'Summary export failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        );
      });
      await _persistCurrentSession();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        await _scrollToBottom();
      }
      await _finishLongResponseTracker(
        tracker: tracker,
        notificationTitle: 'Summary Export Ready',
        notificationBody: 'Your summary report PDF has been generated.',
      );
    }
  }

  Future<void> _openQuizPaper(AiQuestionPaper paper) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiQuestionPaperQuizScreen(paper: paper),
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_isSendAttemptInProgress) return;
    _isSendAttemptInProgress = true;
    if (mounted) setState(() {});
    try {
      await (() async {
        final text = _controller.text.trim();
        final turnAttachments = List<_ChatAttachment>.from(_attachments);
        final hasAttachmentContext =
            turnAttachments.isNotEmpty || _stickyAttachments.isNotEmpty;
        if ((text.isEmpty && !hasAttachmentContext) ||
            _isLoading ||
            _isUploadingAttachment) {
          return;
        }

        if (!_auth.isSignedIn) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in to use AI chat.')),
          );
          return;
        }

        if (!_aiTokenStatusLoaded) {
          await _refreshAiTokenStatus();
        }
        if (_aiTokenStatusLoaded &&
            _aiTokenBudgetTokens > 0 &&
            _aiTokenRemainingTokens <= 0) {
          await _analytics.logEvent(
            'ai_chat_blocked',
            parameters: <String, Object?>{
              ..._baseAnalyticsParameters(),
              'reason': 'insufficient_tokens',
            },
          );
          setState(() => _showAiTokenLowBanner = true);
          _showAiTokenTopUpSnackBar(_buildAiTokenShortageMessage());
          return;
        }

        if (turnAttachments.isNotEmpty) {
          _rememberAttachmentsForContext(turnAttachments);
        }

        final effectiveAttachments = turnAttachments.isNotEmpty
            ? turnAttachments
            : List<_ChatAttachment>.from(_stickyAttachments);

        final hasAttachments = effectiveAttachments.isNotEmpty;
        final userPrompt = text.isEmpty
            ? 'Please analyze the attached files and help me study.'
            : text;
        if (_shouldSuppressRapidDuplicateSend(
          userPrompt: userPrompt,
          activeAttachments: effectiveAttachments,
        )) {
          return;
        }
        final noticeRequestContext = _buildNoticeRequestContext(
          prompt: userPrompt,
        );
        final searchAllForPrompt = _shouldSearchAllPdfsForPrompt(userPrompt);
        final isPdfOverviewPrompt = _isPdfOverviewPrompt(userPrompt);
        final localContextRequired =
            hasAttachments ||
            _isStudioChat ||
            _promptRequiresLocalContext(userPrompt) ||
            searchAllForPrompt;
        final sourceSwitchForTurn = _promptRequestsAllPdfs(userPrompt);
        final languageHint = _shouldForceEnglish(userPrompt) ? 'en' : 'auto';
        final dialectIntensity = languageHint == 'en'
            ? null
            : (_detectDialectIntensity(userPrompt) == 'strong'
                  ? 'strong'
                  : null);
        final excludeFileIds =
            (_lastPrimarySourceFileId ?? '').trim().isNotEmpty
            ? <String>[_lastPrimarySourceFileId!.trim()]
            : null;
        final attachmentPayload = _toAttachmentPayload(effectiveAttachments);
        final sendPrompt = _buildRagPrompt(
          userPrompt: userPrompt,
          hasAttachments: hasAttachments,
          preferLocalOnly:
              localContextRequired || noticeRequestContext.preferNoticeSources,
          searchAllPdfs: searchAllForPrompt,
          preferNoticeSources: noticeRequestContext.preferNoticeSources,
        );
        final history = _buildStructuredHistory(pendingUserPrompt: userPrompt);
        final contextFilters = await _buildContextFiltersForRequest(
          ignoreSubject: searchAllForPrompt,
          prompt: userPrompt,
        );
        final hasImageAttachments = attachmentPayload.any(
          (item) => item['type']?.toString().toLowerCase() == 'image',
        );
        final hasPdfAttachments = attachmentPayload.any(
          (item) => item['type']?.toString().toLowerCase() == 'pdf',
        );
        final hasOcrEligibleAttachments =
            hasImageAttachments || hasPdfAttachments;
        final isQuestionPaperRequest = _isQuestionPaperIntent(
          prompt: userPrompt,
          hasAttachments: hasAttachments,
        );
        final isQuestionPaperContinuation =
            !isQuestionPaperRequest &&
            _hasActiveQuestionPaperResponse() &&
            _isQuestionPaperContinuationIntent(userPrompt);
        final isQuestionPaperClarificationReply =
            !isQuestionPaperRequest &&
            !isQuestionPaperContinuation &&
            _pendingQuestionPaperRequest != null &&
            _looksLikeQuestionPaperClarificationReply(userPrompt);
        final shouldGenerateQuestionPaper =
            isQuestionPaperRequest ||
            isQuestionPaperContinuation ||
            isQuestionPaperClarificationReply;
        final mustUseGroundedLocalContext =
            localContextRequired ||
            hasOcrEligibleAttachments ||
            shouldGenerateQuestionPaper ||
            noticeRequestContext.preferNoticeSources;
        final effectiveAllowWeb = _allowWebMode && !mustUseGroundedLocalContext;
        final releasePinnedResourceForNotice =
            noticeRequestContext.preferNoticeSources;
        final effectiveFileId =
            effectiveAllowWeb || releasePinnedResourceForNotice
            ? null
            : (searchAllForPrompt ? null : widget.resourceContext?.fileId);
        final effectiveVideoUrl =
            effectiveAllowWeb || releasePinnedResourceForNotice
            ? null
            : widget.resourceContext?.videoUrl;
        final effectiveAttachmentPayload = effectiveAllowWeb
            ? const <Map<String, dynamic>>[]
            : attachmentPayload;
        final effectiveFilters = effectiveAllowWeb ? null : contextFilters;
        final effectiveSourceSwitchForTurn = effectiveAllowWeb
            ? false
            : sourceSwitchForTurn;
        final effectiveExcludeFileIds = effectiveAllowWeb
            ? null
            : (releasePinnedResourceForNotice ? null : excludeFileIds);
        final effectiveUseOcr = effectiveAllowWeb
            ? false
            : hasOcrEligibleAttachments;
        final effectiveForceOcr = false;
        final minScore = localContextRequired
            ? (isPdfOverviewPrompt ? 0.16 : 0.08)
            : null;
        final effectiveMinScore = effectiveAllowWeb ? null : minScore;
        final effectiveSourceHint = noticeRequestContext.preferNoticeSources
            ? 'notice'
            : null;
        final userVisible = turnAttachments.isEmpty
            ? userPrompt
            : '$userPrompt\n\n${turnAttachments.length} attachments added.';
        final isSummaryExportRequest = _isSummaryExportIntent(
          prompt: userPrompt,
          hasAttachments: hasAttachments,
        );
        final analyticsParameters = <String, Object?>{
          ..._baseAnalyticsParameters(),
          'has_attachments': hasAttachments,
          'attachment_count': effectiveAttachments.length,
          'allow_web': effectiveAllowWeb,
          'search_all_pdfs': searchAllForPrompt,
          'use_ocr': effectiveUseOcr,
          'force_ocr': effectiveForceOcr,
          'summary_export': isSummaryExportRequest,
          'question_paper': shouldGenerateQuestionPaper,
          'prefer_notice_sources': noticeRequestContext.preferNoticeSources,
        };

        await _analytics.logEvent(
          'ai_chat_send',
          parameters: analyticsParameters,
        );

        if (isSummaryExportRequest) {
          await _handleSummaryExport(
            userPrompt: userPrompt,
            userVisible: userVisible,
            attachmentPayload: attachmentPayload,
          );
          return;
        }

        if (shouldGenerateQuestionPaper) {
          final resolvedQuestionPaperRequest = await _resolveQuestionPaperRequest(
            userPrompt: isQuestionPaperContinuation
                ? 'Continue the previous question paper on the same topic. $userPrompt'
                : userPrompt,
            userVisible: userVisible,
            effectiveAttachments: effectiveAttachments,
            turnAttachments: turnAttachments,
            isFreshQuestionPaperRequest: isQuestionPaperRequest,
          );
          if (resolvedQuestionPaperRequest == null) return;
          await _handleQuestionPaperGeneration(
            userPrompt: resolvedQuestionPaperRequest.generationPrompt,
            userVisible: resolvedQuestionPaperRequest.userVisible,
            attachmentPayload: attachmentPayload,
            config: resolvedQuestionPaperRequest.config,
            resolvedSubject: resolvedQuestionPaperRequest.subject,
            pinnedScopeOnly: resolvedQuestionPaperRequest.pinnedScopeOnly,
            preferTopicOnlyScope:
                resolvedQuestionPaperRequest.preferTopicOnlyScope,
          );
          return;
        }

        _pendingQuestionPaperRequest = null;

        final tracker = _startLongResponseTracker('AI response generation');
        final aiMessage = AIChatMessage(isUser: false, content: '');
        final AIChatMessage aiMessageForError = aiMessage;
        var malformedChunkCount = 0;
        var aiInvoked = false;

        setState(() {
          _messages.add(AIChatMessage(isUser: true, content: userVisible));
          _messages.add(aiMessage);
          _isLoading = true;
          _controller.clear();
          _attachments.clear();
        });
        await _persistCurrentSession();
        await _scrollToBottom();

        try {
          _resetTypingRenderer();

          final stream = _api.queryRagStream(
            question: sendPrompt,
            collegeId: widget.collegeId,
            sessionId: _activeSessionId,
            minScore: effectiveMinScore,
            fileId: effectiveFileId,
            videoUrl: effectiveVideoUrl,
            allowWeb: effectiveAllowWeb,
            useOcr: effectiveUseOcr,
            forceOcr: effectiveForceOcr,
            attachments: effectiveAttachmentPayload,
            history: history,
            filters: effectiveFilters,
            sourceSwitchForTurn: effectiveSourceSwitchForTurn,
            excludeFileIds: effectiveExcludeFileIds,
            noticeIds: noticeRequestContext.noticeIds,
            sourceHint: effectiveSourceHint,
            dialectIntensity: dialectIntensity,
            languageHint: languageHint,
          );
          aiInvoked = true;

          await for (final chunkStr in stream) {
            if (!mounted) break;
            try {
              final chunk = jsonDecode(chunkStr);
              final type = chunk['type'];

              if (type == 'metadata') {
                final data = chunk['data'] as Map<String, dynamic>? ?? {};
                _guardUnexpectedWebResponse(
                  allowWeb: effectiveAllowWeb,
                  response: data,
                );
                final sourcesRaw = (data['sources'] as List?) ?? const [];
                final ocrErrorsRaw = (data['ocr_errors'] as List?) ?? const [];
                final sources = sourcesRaw
                    .whereType<Map>()
                    .map(
                      (s) => RagSource.fromJson(Map<String, dynamic>.from(s)),
                    )
                    .toList();
                final ocrErrors = ocrErrorsRaw
                    .whereType<Map>()
                    .map(
                      (entry) => OcrErrorInfo.fromJson(
                        Map<String, dynamic>.from(entry),
                      ),
                    )
                    .toList();
                final primarySource = _parsePrimarySource(
                  data['primary_source'],
                );
                final orderedSources = _mergePrimarySource(
                  primarySource,
                  sources,
                );
                final primarySourceFileId =
                    _extractPrimarySourceFileId(data) ?? primarySource?.fileId;
                final answerOrigin = AiAnswerOriginX.fromWireValue(
                  data['answer_origin']?.toString(),
                );
                final insufficientGrounding =
                    data['insufficient_grounding'] == true ||
                    answerOrigin == AiAnswerOrigin.insufficientNotes;
                final effectiveAnswerOrigin = insufficientGrounding
                    ? AiAnswerOrigin.insufficientNotes
                    : answerOrigin;
                final liveSteps = _buildLiveAnswerSteps(
                  answerOrigin: effectiveAnswerOrigin,
                  sources: orderedSources,
                  noLocal: data['no_local'] == true || insufficientGrounding,
                  answerCompleted: false,
                );

                setState(() {
                  aiMessage.primarySource = primarySource;
                  aiMessage.sources = orderedSources;
                  aiMessage.noLocal =
                      data['no_local'] == true || insufficientGrounding;
                  aiMessage.answerOrigin = effectiveAnswerOrigin;
                  aiMessage.liveTitle = 'Tracing your answer';
                  aiMessage.liveSteps = liveSteps;
                  aiMessage.retrievalScore = _toNullableDouble(
                    data['retrieval_score'],
                  );
                  aiMessage.llmConfidenceScore = _toNullableDouble(
                    data['llm_confidence_score'],
                  );
                  aiMessage.combinedConfidence = _toNullableDouble(
                    data['combined_confidence'],
                  );
                  aiMessage.ocrFailureAffectsRetrieval =
                      data['ocr_failure_affects_retrieval'] == true;
                  aiMessage.ocrErrors = ocrErrors;
                  if (primarySourceFileId != null &&
                      primarySourceFileId.trim().isNotEmpty) {
                    _lastPrimarySourceFileId = primarySourceFileId.trim();
                  }
                });
              } else if (type == 'chunk') {
                final textChunk = chunk['text']?.toString() ?? '';
                _enqueueTypedChunk(aiMessage, textChunk);
              } else if (type == 'error') {
                _enqueueTypedChunk(aiMessage, '\n\nError: ${chunk['message']}');
              } else if (type == 'done') {
                if (aiMessage.liveSteps.isNotEmpty) {
                  setState(() {
                    aiMessage.liveSteps = _markLiveAnswerStatus(
                      aiMessage.liveSteps,
                      AiLiveActivityStatus.completed,
                    );
                  });
                }
              } else {
                _guardUnexpectedWebResponse(
                  allowWeb: effectiveAllowWeb,
                  response: Map<String, dynamic>.from(chunk),
                );
                final textChunk =
                    chunk['text']?.toString() ??
                    chunk['answer']?.toString() ??
                    chunk['response']?.toString() ??
                    '';
                if (textChunk.trim().isNotEmpty) {
                  _enqueueTypedChunk(aiMessage, textChunk);
                }
                final sourcesRaw = (chunk['sources'] as List?) ?? const [];
                if (sourcesRaw.isNotEmpty) {
                  final sources = sourcesRaw
                      .whereType<Map>()
                      .map(
                        (s) => RagSource.fromJson(Map<String, dynamic>.from(s)),
                      )
                      .toList();
                  final primarySource = _parsePrimarySource(
                    chunk['primary_source'],
                  );
                  final orderedSources = _mergePrimarySource(
                    primarySource,
                    sources,
                  );
                  final primarySourceFileId =
                      _extractPrimarySourceFileId(
                        Map<String, dynamic>.from(chunk),
                      ) ??
                      primarySource?.fileId;
                  if (sources.isNotEmpty) {
                    final chunkAnswerOrigin = AiAnswerOriginX.fromWireValue(
                      chunk['answer_origin']?.toString(),
                    );
                    final insufficientGrounding =
                        chunk['insufficient_grounding'] == true ||
                        chunkAnswerOrigin == AiAnswerOrigin.insufficientNotes;
                    setState(() {
                      aiMessage.primarySource = primarySource;
                      aiMessage.sources = orderedSources;
                      aiMessage.noLocal =
                          chunk['no_local'] == true || insufficientGrounding;
                      aiMessage.answerOrigin ??= insufficientGrounding
                          ? AiAnswerOrigin.insufficientNotes
                          : chunkAnswerOrigin;
                      aiMessage.liveTitle = 'Tracing your answer';
                      aiMessage.liveSteps = _buildLiveAnswerSteps(
                        answerOrigin: aiMessage.answerOrigin,
                        sources: orderedSources,
                        noLocal:
                            chunk['no_local'] == true || insufficientGrounding,
                        answerCompleted: false,
                      );
                      aiMessage.retrievalScore = _toNullableDouble(
                        chunk['retrieval_score'],
                      );
                      aiMessage.llmConfidenceScore = _toNullableDouble(
                        chunk['llm_confidence_score'],
                      );
                      aiMessage.combinedConfidence = _toNullableDouble(
                        chunk['combined_confidence'],
                      );
                      aiMessage.ocrFailureAffectsRetrieval =
                          chunk['ocr_failure_affects_retrieval'] == true;
                      if (primarySourceFileId != null &&
                          primarySourceFileId.trim().isNotEmpty) {
                        _lastPrimarySourceFileId = primarySourceFileId.trim();
                      }
                    });
                  }
                }
              }
            } catch (e, st) {
              final fallbackText = chunkStr.trim();
              if (fallbackText.isNotEmpty) {
                _enqueueTypedChunk(aiMessage, fallbackText);
              } else {
                debugPrint('Chunk parse error: $e\nStack: $st');
                malformedChunkCount++;
              }
            }
          }

          if (malformedChunkCount > 0) {
            debugPrint(
              'Stream finished with $malformedChunkCount malformed chunks.',
            );
          }
          _streamTypingDone = true;
          _completeTypingDrainIfDrained();
          await _waitForTypingDrain();
          final hasAssistantText = aiMessage.content.trim().isNotEmpty;
          if (hasAssistantText) {
            final sanitized = _sanitizeAssistantAnswerText(aiMessage.content);
            final promotedQuiz = await _maybePromoteQuizFromAssistantResponse(
              rawResponse: sanitized,
              userPrompt: userPrompt,
              hasAttachmentContext: hasAttachments,
              contextResourceCount: attachmentPayload.length,
            );
            if (!mounted) return;
            setState(() {
              if (promotedQuiz != null) {
                aiMessage.quizActionPaper = promotedQuiz;
                aiMessage.content = _buildQuestionPaperSummary(promotedQuiz);
              } else {
                aiMessage.content = sanitized;
              }
            });
          } else if (mounted) {
            setState(() {
              aiMessage.content = effectiveAllowWeb
                  ? 'The AI connection was interrupted before a full answer arrived. Please try again.'
                  : 'I could not complete a local StudyShare answer this time. Please try again.';
            });
          }

          await _persistCurrentSession();
          if (aiInvoked) {
            _supabase.markAiTokenBalanceStale();
            _refreshAiTokenStatus(forceRefresh: true);
          }
          await _analytics.logEvent(
            'ai_chat_response',
            parameters: <String, Object?>{
              ...analyticsParameters,
              'has_sources': aiMessage.sources.isNotEmpty,
              'source_count': aiMessage.sources.length,
              'ocr_error_count': aiMessage.ocrErrors.length,
              'answer_origin': aiMessage.answerOrigin?.wireValue,
              'response_chars': aiMessage.content.trim().length,
              'malformed_chunks': malformedChunkCount,
            },
          );
        } catch (e) {
          final errorMessage = _cleanUserVisibleErrorMessage(e);
          final presentedErrorMessage = _presentAiErrorMessage(errorMessage);
          final isTokenLimitError = _looksLikeTokenLimitError(errorMessage);
          _handlePotentialTokenLimitError(errorMessage);
          _streamTypingDone = true;
          _completeTypingDrainIfDrained();
          await _waitForTypingDrain();
          if (mounted) {
            setState(() {
              if (aiMessageForError.liveSteps.isNotEmpty &&
                  !isTokenLimitError) {
                aiMessageForError.liveSteps = _markLiveAnswerStatus(
                  aiMessageForError.liveSteps,
                  AiLiveActivityStatus.failed,
                );
              }
              if (isTokenLimitError) {
                _applyAiTokenShortageState(aiMessageForError);
              } else {
                final separator = aiMessageForError.content.isEmpty
                    ? ''
                    : '\n\n';
                aiMessageForError.content += '$separator$presentedErrorMessage';
              }
            });
            await _persistCurrentSession();
          }
          await _analytics.logEvent(
            'ai_chat_error',
            parameters: <String, Object?>{
              ...analyticsParameters,
              'reason': _classifyAiChatError(errorMessage),
            },
          );
        } finally {
          _resetTypingRenderer();
          if (mounted) {
            setState(() => _isLoading = false);
            await _scrollToBottom();
          }
          await _finishLongResponseTracker(
            tracker: tracker,
            notificationTitle: 'AI Response Ready',
            notificationBody: 'Your AI answer is ready in StudyShare.',
          );
        }
      })();
    } finally {
      _isSendAttemptInProgress = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickAttachment() async {
    if (_isUploadingAttachment || _isLoading || _isSendAttemptInProgress) {
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      withData: true,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
    );

    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final filename = file.name.toLowerCase();
    final isPdf = filename.endsWith('.pdf');

    setState(() => _isUploadingAttachment = true);
    try {
      final uploadPlan = await _api.getResourceUploadUrl(filename: file.name);
      final uploadUrl = uploadPlan['uploadUrl']?.toString().trim();
      final publicUrl = uploadPlan['publicUrl']?.toString().trim();
      if (uploadUrl == null ||
          uploadUrl.isEmpty ||
          publicUrl == null ||
          publicUrl.isEmpty) {
        throw const FormatException('Failed to get attachment upload URL.');
      }
      await _api.uploadToPresignedUrl(
        file: file,
        uploadUrl: uploadUrl,
        contentType: _api.inferContentType(file.name),
        bytes: file.bytes,
      );
      if (!mounted) return;
      setState(() {
        _attachments.add(
          _ChatAttachment(name: file.name, url: publicUrl, isPdf: isPdf),
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${file.name} attached')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Attachment upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _attachments.length) return;
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _copyMessage(String text, String label) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  Future<void> _shareMessage(String text) async {
    if (text.trim().isEmpty) return;
    await SharePlus.instance.share(ShareParams(text: text.trim()));
  }

  String _extractPromptFromUserVisible(String raw) {
    final markerMatch = RegExp(
      r'\n\n\d+\s+attachments?\s+added\.$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (markerMatch != null) {
      return raw.substring(0, markerMatch.start).trim();
    }
    final legacyIndex = raw.indexOf('\n\nAttachments:');
    if (legacyIndex != -1) {
      return raw.substring(0, legacyIndex).trim();
    }
    return raw.trim();
  }

  String _buildGenerateMoreQuestionPaperPrompt({
    required String basePrompt,
    required AiQuestionPaper paper,
  }) {
    final originalPrompt = _sanitizePromptFragment(
      _extractPromptFromUserVisible(basePrompt),
      maxLength: 320,
    );
    final previousQuestions = paper.questions
        .take(5)
        .map((item) => '- ${item.question.trim()}')
        .join('\n');

    return [
      if (originalPrompt.isNotEmpty) 'Original request: $originalPrompt',
      'Generate 5 more multiple-choice quiz questions from the same notice or study material.',
      'Do not repeat any of the earlier questions.',
      'Ground every question only in the same retrieved source content.',
      if (previousQuestions.isNotEmpty)
        'Previously used questions:\n$previousQuestions',
    ].join('\n\n');
  }

  Future<void> _generateMoreQuestionPaperFromMessage(int messageIndex) async {
    if (_isLoading || messageIndex < 0 || messageIndex >= _messages.length) {
      return;
    }

    final message = _messages[messageIndex];
    final paper = message.quizActionPaper;
    if (paper == null) return;

    var basePrompt = '';
    for (var i = messageIndex - 1; i >= 0; i--) {
      final candidate = _messages[i];
      if (!candidate.isUser) continue;
      basePrompt = _extractPromptFromUserVisible(candidate.content);
      if (basePrompt.trim().isNotEmpty) break;
    }
    if (basePrompt.trim().isEmpty) {
      basePrompt = 'Generate a quiz from the same notice or study material.';
    }

    final effectiveAttachments = List<_ChatAttachment>.from(_stickyAttachments);
    final attachmentPayload = _toAttachmentPayload(effectiveAttachments);
    final resolvedSubject = paper.subject.trim().toLowerCase() == 'general'
        ? ''
        : _normalizeQuestionPaperSubjectHint(paper.subject);
    final pinnedScopeOnly =
        widget.resourceContext != null || effectiveAttachments.isNotEmpty;

    await _handleQuestionPaperGeneration(
      userPrompt: _buildGenerateMoreQuestionPaperPrompt(
        basePrompt: basePrompt,
        paper: paper,
      ),
      userVisible: 'Generate 5 more questions',
      attachmentPayload: attachmentPayload,
      config: _QuestionPaperRequestConfig(
        semester: pinnedScopeOnly ? paper.semester.trim() : '',
        branch: pinnedScopeOnly ? paper.branch.trim() : '',
      ),
      resolvedSubject: resolvedSubject,
      pinnedScopeOnly: pinnedScopeOnly,
      preferTopicOnlyScope: resolvedSubject.isNotEmpty && !pinnedScopeOnly,
    );
  }

  Future<void> _regenerateFromMessage(int messageIndex) async {
    if (_isLoading || messageIndex <= 0) return;
    for (var i = messageIndex - 1; i >= 0; i--) {
      final candidate = _messages[i];
      if (!candidate.isUser) continue;
      final prompt = _extractPromptFromUserVisible(candidate.content);
      if (prompt.isEmpty) continue;
      setState(() {
        final int startIndex = messageIndex.clamp(0, _messages.length);
        if (startIndex < _messages.length) {
          _messages.removeRange(startIndex, _messages.length);
        }
        _controller.text = prompt;
      });
      await _sendMessage();
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No prompt available to regenerate.')),
    );
  }

  Widget _buildAiTokenLowBanner(bool isDark) {
    final exhausted =
        _aiTokenStatusLoaded &&
        _aiTokenBudgetTokens > 0 &&
        _aiTokenRemainingTokens <= 0;
    final remainingCredits = visibleAiTokensFromRaw(
      math.max(0, _aiTokenRemainingTokens),
    );
    final totalCredits = visibleAiTokensFromRaw(
      math.max(0, _aiTokenBudgetTokens),
    );
    final shortBy = math.max(
      1,
      visibleAiTokenShortfallFromRaw(_aiTokenRemainingTokens),
    );
    final message = exhausted
        ? 'You have 0 of $totalCredits AI tokens left. Add at least $shortBy more token${shortBy == 1 ? '' : 's'} to continue.'
        : 'Low AI balance: $remainingCredits of $totalCredits AI tokens left.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: exhausted
            ? AppTheme.error.withValues(alpha: isDark ? 0.2 : 0.12)
            : AppTheme.warning.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: exhausted
              ? AppTheme.error.withValues(alpha: 0.6)
              : AppTheme.warning.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Icon(
            exhausted
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            size: 16,
            color: exhausted ? AppTheme.error : AppTheme.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _openAiTopUpDialog,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(
              'Recharge',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: () => setState(() {
              _showAiTokenLowBanner = false;
              _userDismissedTokenBanner = true;
            }),
            icon: Icon(
              Icons.close_rounded,
              size: 15,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    required bool isCompact,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 5 : 6,
          vertical: isCompact ? 3 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isCompact ? 13 : 14, color: color),
            SizedBox(width: isCompact ? 3 : 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: isCompact ? 10 : 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOcrErrorDetails(
    List<OcrErrorInfo> errors,
    bool isDark,
    bool isCompact,
  ) {
    if (errors.isEmpty) return const SizedBox.shrink();
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final muted = isDark ? Colors.white54 : Colors.black54;
    final visible = errors.take(3).toList();
    final remaining = errors.length - visible.length;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final err in visible) ...[
            Text(
              '- ${err.name} (${_labelForOcrCode(err.code)})',
              style: GoogleFonts.inter(
                fontSize: isCompact ? 10.5 : 11,
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (err.message.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 2, bottom: 4),
                child: Text(
                  err.message.trim(),
                  style: GoogleFonts.inter(
                    fontSize: isCompact ? 10 : 10.5,
                    color: muted,
                  ),
                ),
              )
            else
              const SizedBox(height: 4),
          ],
          if (remaining > 0)
            Text(
              '+ $remaining more file${remaining == 1 ? '' : 's'}',
              style: GoogleFonts.inter(
                fontSize: isCompact ? 10 : 10.5,
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    AIChatMessage msg,
    bool isDark,
    int index,
    double screenWidth,
    double bubbleMaxWidth,
  ) {
    final isCompact = screenWidth < 380;
    final isSmallPhone = screenWidth < 350;
    final bubbleInset = (screenWidth * (isSmallPhone ? 0.068 : 0.095))
        .clamp(18.0, 56.0)
        .toDouble();
    final bubblePadding = EdgeInsets.symmetric(
      horizontal: isSmallPhone ? 10 : (isCompact ? 12 : 14),
      vertical: isSmallPhone ? 9 : (isCompact ? 10 : 11),
    );
    final textColor = msg.isUser
        ? Colors.white
        : (isDark ? Colors.white : Colors.black);
    final isStreamingAssistantMessage =
        !msg.isUser && _isLoading && index == _messages.length - 1;
    final isStreamingPlaceholder =
        isStreamingAssistantMessage && msg.content.trim().isEmpty;
    final showLegacyShimmer =
        isStreamingPlaceholder &&
        !_shouldShowLiveActivityCard(msg, isStreamingAssistantMessage);
    final messageTextStyle = GoogleFonts.inter(
      fontSize: isCompact ? 13.5 : 14,
      height: 1.46,
      color: textColor,
      letterSpacing: 0.05,
    );
    final streamingHint = _allowWebMode
        ? 'Thinking through your sources and the web...'
        : 'Thinking through your notes...';
    final messageBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!msg.isUser)
          Row(
            children: [
              const AiLogo(size: 16, animate: true),
              const SizedBox(width: 6),
              Text(
                _chatTitle,
                style: GoogleFonts.inter(
                  fontSize: isCompact ? 10 : 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: AppTheme.primary,
                ),
              ),
              if (msg.noLocal) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'No PDF match',
                    style: GoogleFonts.inter(
                      fontSize: isCompact ? 9 : 9.5,
                      color: AppTheme.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (msg.combinedConfidence != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Conf ${(msg.combinedConfidence! * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.inter(
                      fontSize: isCompact ? 9 : 9.5,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (msg.cached) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Cached',
                    style: GoogleFonts.inter(
                      fontSize: isCompact ? 9 : 9.5,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        if (!msg.isUser) const SizedBox(height: 8),
        if (_shouldShowCollapsedLiveTrace(msg, isStreamingAssistantMessage))
          _buildCollapsedLiveTrace(msg, isDark, isCompact),
        if (showLegacyShimmer)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Shimmer.fromColors(
              baseColor: isDark ? Colors.white54 : Colors.black45,
              highlightColor: isDark ? Colors.white : Colors.black87,
              child: Text(
                streamingHint,
                style: messageTextStyle.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else if (msg.content.trim().isNotEmpty)
          MarkdownBody(
            data: msg.content,
            softLineBreak: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: messageTextStyle,
                  strong: messageTextStyle.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  h3: messageTextStyle.copyWith(fontWeight: FontWeight.w700),
                  blockquoteDecoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
          ),
        if (!msg.isUser && msg.ocrFailureAffectsRetrieval) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Results may be incomplete because OCR failed for one or more sources.',
                  style: GoogleFonts.inter(
                    fontSize: isCompact ? 11 : 11.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _buildOcrErrorDetails(msg.ocrErrors, isDark, isCompact),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildBubbleAction(
                      icon: Icons.refresh_rounded,
                      label: _isOcrActionLoading ? 'Retrying...' : 'Retry OCR',
                      onTap: _isOcrActionLoading
                          ? () {}
                          : () => _retryOcrForMessage(msg),
                      color: isDark ? Colors.white70 : Colors.black87,
                      isCompact: isCompact,
                    ),
                    _buildBubbleAction(
                      icon: Icons.cancel_schedule_send_rounded,
                      label: _isOcrActionLoading
                          ? 'Working...'
                          : 'Cancel Retry',
                      onTap: _isOcrActionLoading
                          ? () {}
                          : () => _cancelOcrRetryForMessage(msg),
                      color: isDark ? Colors.white70 : Colors.black87,
                      isCompact: isCompact,
                    ),
                    _buildBubbleAction(
                      icon: Icons.upload_file_rounded,
                      label: _isOcrActionLoading
                          ? 'Uploading...'
                          : 'Request Re-upload',
                      onTap: _isOcrActionLoading
                          ? () {}
                          : () => _requestReuploadForMessage(msg),
                      color: isDark ? Colors.white70 : Colors.black87,
                      isCompact: isCompact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (!msg.isUser && msg.sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Sources',
            style: GoogleFonts.inter(
              fontSize: isCompact ? 11.5 : 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          if (msg.primarySource != null) ...[
            const SizedBox(height: 4),
            Text(
              'Primary source: ${msg.primarySource!.title}',
              style: GoogleFonts.inter(
                fontSize: isCompact ? 10.5 : 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.amber[200] : Colors.indigo[700],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: msg.sources.asMap().entries.map((entry) {
              final s = entry.value;
              final isPrimary =
                  msg.primarySource != null &&
                  msg.primarySource!.fileId.trim().isNotEmpty &&
                  s.fileId.trim().isNotEmpty &&
                  s.fileId == msg.primarySource!.fileId;
              final isYoutubeSource =
                  s.sourceType == 'youtube' ||
                  (s.videoUrl?.toLowerCase().contains('youtu') ?? false) ||
                  (s.fileUrl?.toLowerCase().contains('youtu') ?? false);
              final isWebSource = s.sourceType == 'web';
              final isNoticeSource = s.isNoticeSource;
              final launchTarget = (s.videoUrl?.trim().isNotEmpty == true)
                  ? s.videoUrl!.trim()
                  : (s.fileUrl?.trim() ?? '');
              final normalizedLaunchTarget = _normalizeExternalUrl(
                launchTarget,
              );
              final label = isYoutubeSource
                  ? (s.timestamp != null && s.timestamp!.trim().isNotEmpty
                        ? '${s.title} (${s.timestamp})'
                        : s.title)
                  : (s.startPage != null && s.endPage != null
                        ? '${s.title} (p${s.startPage}-${s.endPage})'
                        : s.title);
              return InkWell(
                onTap: !isNoticeSource && normalizedLaunchTarget.isEmpty
                    ? null
                    : () async {
                        if (_isOpeningSourceLink) return;
                        _isOpeningSourceLink = true;
                        final uri = _buildExternalLaunchUri(
                          normalizedLaunchTarget,
                        );
                        try {
                          if (!mounted) return;
                          if (isNoticeSource) {
                            await _openNoticeSource(s);
                          } else if (isYoutubeSource) {
                            bool opened;
                            try {
                              opened = await openStudyShareLink(
                                context,
                                rawUrl: normalizedLaunchTarget,
                                title: s.title,
                                resourceId: s.fileId.trim().isEmpty
                                    ? null
                                    : s.fileId,
                                collegeId: widget.collegeId,
                                subject: widget.resourceContext?.subject,
                                semester: widget.resourceContext?.semester,
                                branch: widget.resourceContext?.branch,
                                fallbackBaseUrl: AppConfig.apiUrl,
                              );
                            } catch (e) {
                              debugPrint(
                                'openStudyShareLink failed for '
                                '"${s.title}": $e',
                              );
                              opened = false;
                            }
                            if (!opened && uri != null) {
                              await _openExternalSourceLink(
                                uri: uri,
                                sourceTitle: s.title,
                              );
                            } else if (!opened) {
                              _showSourceUrlErrorSnackBar(s.title);
                            }
                          } else if (isWebSource && uri != null) {
                            await _openWebSourceInAppOrExternal(
                              uri: uri,
                              sourceTitle: s.title,
                            );
                          } else if (uri != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PdfViewerScreen(
                                  pdfUrl: uri.toString(),
                                  title: s.title,
                                  resourceId: s.fileId,
                                  collegeId: widget.collegeId,
                                ),
                              ),
                            );
                          } else if (mounted) {
                            _showSourceUrlErrorSnackBar(s.title);
                          }
                        } finally {
                          _isOpeningSourceLink = false;
                        }
                      },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? (isPrimary
                              ? Colors.amber.withValues(alpha: 0.16)
                              : Colors.white10)
                        : (isPrimary
                              ? Colors.indigo.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isPrimary
                          ? (isDark
                                ? Colors.amber.withValues(alpha: 0.45)
                                : Colors.indigo.withValues(alpha: 0.35))
                          : (isDark ? Colors.white12 : Colors.black12),
                    ),
                  ),
                  child: Text(
                    isPrimary ? '[Primary] $label' : label,
                    style: GoogleFonts.inter(
                      fontSize: isCompact ? 10 : 10.5,
                      color: isPrimary
                          ? (isDark ? Colors.amber[100] : Colors.indigo[800])
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        if (!msg.isUser && msg.quizActionPaper != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () => _openQuizPaper(msg.quizActionPaper!),
                  icon: const Icon(Icons.quiz_rounded, size: 16),
                  label: const Text('Start Quiz'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (!_isLoading && index == _messages.length - 1)
                SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _generateMoreQuestionPaperFromMessage(index),
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16,
                    ),
                    label: const Text('Generate More'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      side: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (msg.content.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              _buildBubbleAction(
                icon: Icons.copy_all_rounded,
                label: 'Copy',
                onTap: () => _copyMessage(
                  msg.content,
                  msg.isUser ? 'Message' : 'Answer',
                ),
                color: msg.isUser
                    ? Colors.white.withValues(alpha: 0.9)
                    : (isDark ? Colors.white70 : Colors.black54),
                isCompact: isCompact,
              ),
              if (!msg.isUser)
                _buildBubbleAction(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  onTap: () => _shareMessage(msg.content),
                  color: isDark ? Colors.white70 : Colors.black54,
                  isCompact: isCompact,
                ),
              if (!msg.isUser && !_isLoading && index == _messages.length - 1)
                _buildBubbleAction(
                  icon: Icons.refresh_rounded,
                  label: 'Regenerate',
                  onTap: () => _regenerateFromMessage(index),
                  color: isDark ? Colors.white70 : Colors.black54,
                  isCompact: isCompact,
                ),
            ],
          ),
        ],
      ],
    );

    if (msg.isUser) {
      return UserMessageBubble(
        isDark: isDark,
        horizontalInset: bubbleInset,
        padding: bubblePadding,
        child: messageBody,
      );
    }
    return BotMessageBubble(
      isDark: isDark,
      horizontalInset: bubbleInset,
      padding: bubblePadding,
      child: messageBody,
    );
  }

  Widget _buildStandaloneLiveActivityCard(
    AIChatMessage msg,
    bool isStreamingAssistantMessage,
  ) {
    return StudyAiLiveActivityCard(
      title: msg.liveTitle?.trim().isNotEmpty == true
          ? msg.liveTitle!.trim()
          : _chatTitle,
      answerOrigin: msg.answerOrigin,
      steps: msg.liveSteps,
      isRunning: isStreamingAssistantMessage,
      showExport: msg.showLiveExport,
      onOpenPdf: (fileId, page) => _openLivePdfSource(msg, fileId, page),
      onOpenNotice: _openLiveNoticeSource,
      onOpenUrl: _openLiveWebSource,
      onOpenVideo: _openLiveVideoSource,
      onExport: msg.quizActionPaper == null
          ? null
          : () => _exportQuestionPaperFromMessage(msg),
      onPlayGame: _supportsLiveQuestionPaperGame(msg)
          ? () => _openQuestionPaperGameSheet(msg)
          : null,
    );
  }

  Widget _buildEntrySplash(bool isDark) {
    return AnimatedBuilder(
      animation: _entrySplashController,
      builder: (context, _) {
        final t = _entrySplashController.value;
        final eased = Curves.easeOutCubic.transform(t);
        final pulse = 0.982 + (math.sin(t * math.pi * 3) * 0.012);
        final ringScale = 0.72 + (eased * 1.55);
        final innerRingScale = 0.66 + (eased * 1.2);
        final ringOpacity = (1.0 - eased).clamp(0.0, 1.0) * 0.26;
        final logoLift = (1.0 - eased) * 8.0;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [Color(0xFF04070F), Color(0xFF0A1629)]
                  : const [Color(0xFFF4F8FF), Color(0xFFE8EFFD)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Opacity(
                  opacity: ringOpacity,
                  child: Transform.scale(
                    scale: ringScale,
                    child: Container(
                      width: 210,
                      height: 210,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.55),
                          width: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: ringOpacity * 0.7,
                  child: Transform.scale(
                    scale: innerRingScale,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.45),
                          width: 0.9,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Transform.scale(
                  scale: _entrySplashScale.value * pulse,
                  child: Opacity(
                    opacity: _entrySplashFade.value,
                    child: Transform.translate(
                      offset: Offset(0, logoLift),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 94,
                            height: 94,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 26,
                                  ),
                                ],
                              ),
                              child: const AiLogo(size: 72, animate: true),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _chatTitle,
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Preparing your workspace',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              letterSpacing: 0.15,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Opacity(
                            opacity: 0.9,
                            child: SizedBox(
                              width: 120,
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                borderRadius: BorderRadius.circular(999),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primary.withValues(alpha: 0.72),
                                ),
                                backgroundColor: isDark
                                    ? Colors.white10
                                    : Colors.black12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPromptComposer({
    required bool isDark,
    required bool hasComposerContent,
    required double attachButtonSize,
    required double sendButtonSize,
    required TextStyle textFieldStyle,
    required TextStyle hintStyle,
  }) {
    final iconColor = isDark ? Colors.white70 : const Color(0xFF1F2937);
    final mutedIconColor = isDark ? Colors.white54 : const Color(0xFF6B7280);
    final composerSurface = isDark ? const Color(0xFF0C1118) : Colors.white;
    final composerBorder = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFDCE4F2);
    final chipSurface = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF3F6FB);
    final composerBusy =
        _isLoading || _isUploadingAttachment || _isSendAttemptInProgress;
    final canSend = hasComposerContent && !composerBusy;
    final sendSurface = canSend
        ? AppTheme.primary
        : (isDark ? Colors.white12 : const Color(0xFFE5E7EB));
    final sendIconColor = canSend
        ? Colors.white
        : (isDark ? Colors.white38 : const Color(0xFF9CA3AF));
    final modeChipBackground = _allowWebMode
        ? AppTheme.primary.withValues(alpha: isDark ? 0.2 : 0.12)
        : chipSurface;
    final modeChipBorder = _allowWebMode
        ? AppTheme.primary.withValues(alpha: 0.28)
        : composerBorder;
    final modeChipIconColor = _allowWebMode ? AppTheme.primary : mutedIconColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: composerSurface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: composerBorder),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.26)
                  : const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: TextField(
                  key: _coachInputKey,
                  controller: _controller,
                  minLines: 1,
                  maxLines: 7,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  style: textFieldStyle.copyWith(
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Message StudyShare AI',
                    hintStyle: hintStyle.copyWith(color: mutedIconColor),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Tooltip(
                    message: 'Attach image or PDF',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: _coachAttachKey,
                        onTap: composerBusy ? null : _pickAttachment,
                        borderRadius: BorderRadius.circular(999),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: attachButtonSize,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: chipSurface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: composerBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isUploadingAttachment)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.add_rounded,
                                  size: 16,
                                  color: composerBusy
                                      ? mutedIconColor
                                      : iconColor,
                                ),
                              const SizedBox(width: 6),
                              Text(
                                'Attach',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: composerBusy
                                      ? mutedIconColor
                                      : iconColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _allowWebMode
                        ? 'Web research enabled'
                        : 'Answer from notes only',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: composerBusy
                            ? null
                            : () {
                                if (!mounted) return;
                                setState(() => _allowWebMode = !_allowWebMode);
                              },
                        borderRadius: BorderRadius.circular(999),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: attachButtonSize,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: modeChipBackground,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: modeChipBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _allowWebMode
                                    ? Icons.public_rounded
                                    : Icons.menu_book_rounded,
                                size: 14,
                                color: modeChipIconColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _allowWebMode ? 'Web' : 'Notes',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _allowWebMode
                                      ? AppTheme.primary
                                      : mutedIconColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    key: _coachSendKey,
                    width: math.max(sendButtonSize + 4, 42),
                    height: math.max(sendButtonSize + 4, 42),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: canSend ? _sendMessage : null,
                        borderRadius: BorderRadius.circular(999),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: sendSurface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: sendIconColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isCompact = screenWidth < 380;
    final isSmallPhone = screenWidth < 350;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBodyTopPadding = widget.embedded
        ? 0.0
        : mediaQuery.padding.top + kToolbarHeight + 6;
    final horizontalPagePadding = (screenWidth * 0.03)
        .clamp(8.0, 16.0)
        .toDouble();
    final bubbleMaxWidth =
        (screenWidth * (isSmallPhone ? 0.93 : (isCompact ? 0.9 : 0.84)))
            .clamp(240.0, 520.0)
            .toDouble();
    final attachmentMaxWidth =
        (screenWidth * (isSmallPhone ? 0.52 : (isCompact ? 0.48 : 0.38)))
            .clamp(116.0, 240.0)
            .toDouble();
    final inputOuterPadding = EdgeInsets.fromLTRB(
      horizontalPagePadding,
      isSmallPhone ? 7 : (isCompact ? 8 : 10),
      horizontalPagePadding,
      12,
    );
    final listPadding = EdgeInsets.fromLTRB(
      horizontalPagePadding,
      12,
      horizontalPagePadding,
      22,
    );
    final attachmentChipPadding = EdgeInsets.symmetric(
      horizontal: isSmallPhone ? 8 : 10,
      vertical: isSmallPhone ? 5 : 6,
    );
    final attachButtonSize = isSmallPhone ? 36.0 : 38.0;
    final sendButtonSize = isSmallPhone ? 36.0 : (isCompact ? 38.0 : 42.0);
    final hasComposerContent =
        _hasText || _attachments.isNotEmpty || _stickyAttachments.isNotEmpty;
    final textFieldStyle = GoogleFonts.inter(
      color: isDark ? Colors.white : Colors.black87,
      fontSize: isSmallPhone ? 14 : 15,
    );
    final hintStyle = GoogleFonts.inter(
      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
      fontSize: isSmallPhone ? 14 : 15,
    );
    final attachmentNameStyle = GoogleFonts.inter(
      fontSize: isSmallPhone ? 10 : (isCompact ? 10.5 : 11),
      color: isDark ? Colors.white70 : Colors.black87,
      fontWeight: FontWeight.w600,
    );

    if (_showEntrySplash && !widget.embedded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF04070F) : Colors.white,
        body: _buildEntrySplash(isDark),
      );
    }

    final chatBackground = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final effectiveCollegeName = widget.collegeName.trim().isEmpty
        ? 'My College'
        : widget.collegeName.trim();

    final chatScaffold = Scaffold(
      backgroundColor: chatBackground,
      extendBodyBehindAppBar: !widget.embedded,
      appBar: widget.embedded
          ? null
          : AppBar(
              backgroundColor: chatBackground.withValues(alpha: 0.78),
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(color: Colors.transparent),
                ),
              ),
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _chatTitle,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: isCompact ? 16 : 17,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    _isStudioChat
                        ? effectiveCollegeName
                        : 'Smart study assistant',
                    style: GoogleFonts.inter(
                      fontSize: isCompact ? 10 : 10.5,
                      letterSpacing: 0.1,
                      color: isDark
                          ? AppTheme.darkTextMuted
                          : AppTheme.lightTextMuted,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Show coach marks',
                  onPressed: _replayCoachMarks,
                  icon: const Icon(Icons.help_outline_rounded),
                ),
                IconButton(
                  tooltip: _notifyOnLongResponses
                      ? 'Disable long-response notifications'
                      : 'Enable long-response notifications',
                  onPressed: _toggleLongResponseNotifications,
                  icon: Icon(
                    _notifyOnLongResponses
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                  ),
                ),
                IconButton(
                  key: _coachHistoryKey,
                  tooltip: 'Chat history',
                  onPressed: _isHistoryLoading ? null : _openHistorySheet,
                  icon: const Icon(Icons.history_rounded),
                ),
                IconButton(
                  key: _coachNewChatKey,
                  tooltip: 'New chat',
                  onPressed: (_messages.isEmpty && _attachments.isEmpty)
                      ? null
                      : _startNewChat,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ],
            ),
      body: Padding(
        padding: EdgeInsets.only(top: appBarBodyTopPadding),
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 20 : 28,
                          vertical: isCompact ? 24 : 30,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SlideTransition(
                              position: _iconSlideAnimation,
                              child: ScaleTransition(
                                scale: _iconScaleAnimation,
                                child: SizedBox(
                                  width: isCompact ? 72 : 78,
                                  height: isCompact ? 72 : 78,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primary.withValues(
                                            alpha: isDark ? 0.18 : 0.12,
                                          ),
                                          blurRadius: 22,
                                        ),
                                      ],
                                    ),
                                    child: const AiLogo(
                                      size: 60,
                                      animate: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            SlideTransition(
                              position: _titleSlideAnimation,
                              child: FadeTransition(
                                opacity: _splashTitleAnimation,
                                child: Text(
                                  'How can I help you study today?',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: isCompact ? 22 : 25,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    height: 1.16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SlideTransition(
                              position: _subtitleSlideAnimation,
                              child: FadeTransition(
                                opacity: _splashSubtitleAnimation,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: isCompact ? 340 : 420,
                                  ),
                                  child: Text(
                                    'I can analyze your notes, summarize PDFs, or generate practice questions based on your specific college materials.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: isCompact ? 13.5 : 14.5,
                                      letterSpacing: 0.06,
                                      color: isDark
                                          ? AppTheme.darkTextSecondary
                                          : AppTheme.lightTextSecondary,
                                      height: 1.42,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 34),
                            Wrap(
                              spacing: isCompact ? 8 : 10,
                              runSpacing: isCompact ? 10 : 12,
                              alignment: WrapAlignment.center,
                              children: List.generate(_suggestions.length, (
                                index,
                              ) {
                                final animation = _suggestionAnimations[index];
                                return ScaleTransition(
                                  scale: animation,
                                  child: FadeTransition(
                                    opacity: _suggestionFadeAnimations[index],
                                    child: ActionChip(
                                      label: Text(
                                        _suggestions[index],
                                        style: GoogleFonts.inter(
                                          fontSize: isCompact ? 11 : 12,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black87,
                                        ),
                                      ),
                                      backgroundColor: isDark
                                          ? Colors.white10
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        side: BorderSide(
                                          color: isDark
                                              ? Colors.white12
                                              : Colors.black12,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      onPressed: () {
                                        _controller.text = _suggestions[index];
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                      },
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: listPadding,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final m = _messages[index];
                        final isStreamingAssistantMessage =
                            !m.isUser &&
                            _isLoading &&
                            index == _messages.length - 1;
                        final showStandaloneLiveCard =
                            !m.isUser &&
                            _shouldShowLiveActivityCard(
                              m,
                              isStreamingAssistantMessage,
                            );
                        final hideBubble =
                            showStandaloneLiveCard && m.content.trim().isEmpty;

                        return Align(
                          alignment: m.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: bubbleMaxWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showStandaloneLiveCard) ...[
                                  _buildStandaloneLiveActivityCard(
                                    m,
                                    isStreamingAssistantMessage,
                                  ),
                                  if (!hideBubble) const SizedBox(height: 10),
                                ],
                                if (!hideBubble)
                                  _buildMessageBubble(
                                    m,
                                    isDark,
                                    index,
                                    screenWidth,
                                    bubbleMaxWidth,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Input area
            SafeArea(
              top: false,
              child: Padding(
                padding: inputOuterPadding,
                child: Column(
                  children: [
                    if (_showAiTokenLowBanner && !_userDismissedTokenBanner)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildAiTokenLowBanner(isDark),
                      ),
                    const SizedBox(height: 4),
                    if (_attachments.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(_attachments.length, (
                              index,
                            ) {
                              final attachment = _attachments[index];
                              return Container(
                                padding: attachmentChipPadding,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white12
                                        : Colors.black12,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      attachment.isPdf
                                          ? Icons.picture_as_pdf_rounded
                                          : Icons.image_rounded,
                                      size: 14,
                                      color: AppTheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: attachmentMaxWidth,
                                      ),
                                      child: Text(
                                        attachment.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: attachmentNameStyle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => _removeAttachment(index),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 14,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    if (_attachments.isEmpty && _stickyAttachments.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 14,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Using ${_stickyAttachments.length} previous attachment${_stickyAttachments.length > 1 ? 's' : ''}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () async {
                                    if (!mounted) return;
                                    setState(() => _clearStickyContext());
                                    await _persistCurrentSession();
                                  },
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    _buildPromptComposer(
                      isDark: isDark,
                      hasComposerContent: hasComposerContent,
                      attachButtonSize: attachButtonSize,
                      sendButtonSize: sendButtonSize,
                      textFieldStyle: textFieldStyle,
                      hintStyle: hintStyle,
                    ),
                    if (widget.resourceContext != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 4,
                          right: 4,
                          bottom: 8,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              if (!mounted) return;
                              setState(() => _searchAllPdfs = !_searchAllPdfs);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: _searchAllPdfs
                                    ? AppTheme.primary.withValues(
                                        alpha: isDark ? 0.22 : 0.14,
                                      )
                                    : (isDark
                                          ? Colors.white10
                                          : Colors.black.withValues(
                                              alpha: 0.04,
                                            )),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _searchAllPdfs
                                      ? AppTheme.primary
                                      : (isDark
                                            ? Colors.white12
                                            : Colors.black12),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.layers_rounded,
                                    size: 14,
                                    color: _searchAllPdfs
                                        ? AppTheme.primary
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black54),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Search all PDFs',
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: _searchAllPdfs
                                          ? AppTheme.primary
                                          : (isDark
                                                ? Colors.white70
                                                : Colors.black54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded || !_showCoachMarks) {
      return chatScaffold;
    }

    return OnboardingOverlay(
      steps: _buildAiCoachSteps(),
      onComplete: _onCoachMarksComplete,
      completionPreferenceKey: _aiCoachMarksSeenKey,
      child: chatScaffold,
    );
  }
}
