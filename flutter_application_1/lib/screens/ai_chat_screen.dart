import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../config/theme.dart';
import '../models/ai_question_paper.dart';
import '../services/auth_service.dart';
import '../services/ai_chat_notification_service.dart';
import '../services/backend_api_service.dart';
import '../services/cloudinary_service.dart';
import '../services/ai_chat_local_service.dart';
import '../services/chat_session_repository.dart';
import '../services/summary_pdf_service.dart';
import '../services/supabase_service.dart';
import '../controllers/ai_chat_animation_controller.dart';
import '../widgets/ai_chat_message_bubble.dart';
import '../widgets/branded_loader.dart';
import '../widgets/onboarding_overlay.dart';
import 'ai_question_paper_quiz_screen.dart';
import 'viewer/pdf_viewer_screen.dart';

class RagSource {
  final String fileId;
  final String title;
  final int? startPage;
  final int? endPage;
  final double? score;
  final String? fileUrl;

  RagSource({
    required this.fileId,
    required this.title,
    this.startPage,
    this.endPage,
    this.score,
    this.fileUrl,
  });

  factory RagSource.fromJson(Map<String, dynamic> json) {
    final pages = json['pages'] as Map<String, dynamic>?;
    final start = pages?['start'];
    final end = pages?['end'];
    return RagSource(
      fileId: json['file_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Source',
      startPage: start is int ? start : int.tryParse(start?.toString() ?? ''),
      endPage: end is int ? end : int.tryParse(end?.toString() ?? ''),
      score: (json['score'] is num) ? (json['score'] as num).toDouble() : null,
      fileUrl: json['file_url']?.toString(),
    );
  }
}

class AIChatMessage {
  final bool isUser;
  String content;
  List<RagSource> sources;
  bool cached;
  bool noLocal;
  AiQuestionPaper? quizActionPaper;

  AIChatMessage({
    required this.isUser,
    required this.content,
    this.sources = const [],
    this.cached = false,
    this.noLocal = false,
    this.quizActionPaper,
  });
}

class _ChatAttachment {
  final String name;
  final String url;
  final bool isPdf;

  const _ChatAttachment({
    required this.name,
    required this.url,
    required this.isPdf,
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

class _LongResponseTracker {
  Timer? timer;
  bool didCrossThreshold = false;
}

/// Context for pinning a RAG chat to a specific resource/PDF.
class ResourceContext {
  final String fileId;
  final String title;
  final String? subject;
  final String? semester;
  final String? branch;

  const ResourceContext({
    required this.fileId,
    required this.title,
    this.subject,
    this.semester,
    this.branch,
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

  /// Optional: if set, all RAG queries are pinned to this resource.
  final ResourceContext? resourceContext;

  const AIChatScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
    this.resourceContext,
  });

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen>
    with TickerProviderStateMixin {
  static const String _aiCoachMarksSeenKey = 'ai_chat_coach_marks_v1_seen';
  static final String _internalDomainSuffix = '.${AppConfig.webDomain}';

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
  final List<AIChatMessage> _messages = [];
  final List<_ChatAttachment> _attachments = [];
  final List<_ChatAttachment> _stickyAttachments = [];
  bool _isUploadingAttachment = false;
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

  bool get _isStudioChat => widget.resourceContext != null;

  String get _chatTitle => _isStudioChat ? 'AI Studio' : 'AI Chat';

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
    _prepareCoachMarks();

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
            'Tap send to start AI generation. Responses stream live as they are produced.',
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

  String _buildRagPrompt({
    required String userPrompt,
    required bool hasAttachments,
  }) {
    final cleaned = userPrompt.trim();
    if (cleaned.isNotEmpty) return cleaned;
    if (hasAttachments) {
      return 'Please analyze the attached files and help me study.';
    }
    return userPrompt;
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
        r'(?:quiz|mcq|question paper|test)\s+(?:on|for|about|from)\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(r'(?:on|for|about)\s+(.+)$', caseSensitive: false),
    ];
    for (final pattern in matches) {
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;
      final captured = match.group(1)?.trim() ?? '';
      if (captured.isNotEmpty) {
        return captured
            .replaceAll(RegExp(r'[.?!]+$'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
    }
    return '';
  }

  Future<_QuestionPaperRequestConfig?> _resolveQuestionPaperConfig() async {
    final fromContextSemester = widget.resourceContext?.semester?.trim() ?? '';
    final fromContextBranch = widget.resourceContext?.branch?.trim() ?? '';
    if (fromContextSemester.isNotEmpty && fromContextBranch.isNotEmpty) {
      return _QuestionPaperRequestConfig(
        semester: fromContextSemester,
        branch: fromContextBranch,
      );
    }

    final email = _auth.userEmail?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      try {
        final info = await _supabase.getUserInfo(email);
        final semester = info?['semester']?.toString().trim() ?? '';
        final branch =
            (info?['branch'] ?? info?['department'])?.toString().trim() ?? '';
        if (semester.isNotEmpty && branch.isNotEmpty) {
          return _QuestionPaperRequestConfig(
            semester: semester,
            branch: branch,
          );
        }
      } catch (e) {
        debugPrint(
          'Question-paper profile lookup failed, falling back to manual config: $e',
        );
        return _showQuestionPaperConfigDialog();
      }
    }

    return _showQuestionPaperConfigDialog();
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
    return LocalAiChatMessage(
      isUser: message.isUser,
      content: message.content,
      sources: message.sources
          .map(
            (source) => {
              'file_id': source.fileId,
              'title': source.title,
              'pages': {'start': source.startPage, 'end': source.endPage},
              'score': source.score,
              'file_url': source.fileUrl,
            },
          )
          .toList(),
      cached: message.cached,
      noLocal: message.noLocal,
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
    return AIChatMessage(
      isUser: message.isUser,
      content: message.content,
      sources: message.sources
          .map((source) => RagSource.fromJson(source))
          .toList(),
      cached: message.cached,
      noLocal: message.noLocal,
      quizActionPaper: quizActionPaper,
    );
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
      }
    });

    // If opened with a resource context, always start fresh so history
    // from unrelated sessions is not shown.
    if (widget.resourceContext != null) {
      _activeSessionId = _newSessionId();
      _messages.clear();
      _clearStickyContext();
      _injectResourceGreeting();
    } else if (_messages.isEmpty && mounted) {
      _splashAnimationController.forward().then((_) {
        if (_messages.isEmpty && mounted) {
          _suggestionsController.forward();
        }
      });
    }

    await _scrollToBottom();
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
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.78,
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
      r'\b(quiz|mcq|question paper|questionpaper|mock test|exam paper|practice test)\b',
    ).hasMatch(normalized);
    if (!hasQuizKeyword) return false;

    final explicitQuizIntent =
        RegExp(
          r'\b(make|create|generate|build|prepare|give|start)\s+(?:me\s+)?(?:a\s+)?(?:quick\s+)?(quiz|mcq|question paper|mock test|practice test)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(ask|test)\s+me\s+(?:\d+\s+)?(?:questions?|mcqs?|quiz)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(?:questions?|mcqs?)\s+(?:on|for|about|from)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(quiz|mcq|question paper|mock test|practice test)\s+(?:on|for|about|from)\b',
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

  Map<String, dynamic>? _decodeJsonMapFromText(String raw) {
    if (raw.trim().isEmpty) return null;
    final fenceMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(raw);
    final cleaned = (fenceMatch?.group(1) ?? raw).trim();

    dynamic tryDecode(String source) {
      try {
        return jsonDecode(source);
      } catch (_) {
        return null;
      }
    }

    final full = tryDecode(cleaned);
    if (full is Map<String, dynamic>) return full;
    if (full is Map) return Map<String, dynamic>.from(full);

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    final sliced = cleaned.substring(start, end + 1);
    final parsed = tryDecode(sliced);
    if (parsed is Map<String, dynamic>) return parsed;
    if (parsed is Map) return Map<String, dynamic>.from(parsed);
    return null;
  }

  int _resolveAnswerIndex({
    required dynamic answer,
    required List<String> options,
  }) {
    if (options.isEmpty) return 0;
    final answerText = answer?.toString().trim() ?? '';
    if (answerText.isEmpty) return 0;

    final letterMatch = RegExp(r'^[A-Za-z]$').firstMatch(answerText);
    if (letterMatch != null) {
      final idx = answerText.toUpperCase().codeUnitAt(0) - 65;
      if (idx >= 0 && idx < options.length) return idx;
    }

    final numeric = int.tryParse(answerText);
    if (numeric != null && numeric > 0 && numeric <= options.length) {
      return numeric - 1;
    }

    final normalizedAnswer = answerText.toLowerCase();
    for (var i = 0; i < options.length; i++) {
      if (options[i].trim().toLowerCase() == normalizedAnswer) {
        return i;
      }
    }
    return 0;
  }

  List<AiQuestionPaperQuestion> _parsePlainTextMcqs(String raw) {
    final lines = raw.split('\n');
    final questions = <AiQuestionPaperQuestion>[];

    String currentQuestion = '';
    final currentOptions = <String>[];
    int currentAnswer = 0;

    void flush() {
      if (currentQuestion.trim().isEmpty || currentOptions.length < 2) return;
      questions.add(
        AiQuestionPaperQuestion(
          question: currentQuestion.trim(),
          options: List<String>.from(currentOptions),
          correctIndex: currentAnswer.clamp(0, currentOptions.length - 1),
        ),
      );
      currentQuestion = '';
      currentOptions.clear();
      currentAnswer = 0;
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final qMatch = RegExp(r'^\d+[\).]\s*(.+)$').firstMatch(line);
      if (qMatch != null) {
        flush();
        currentQuestion = qMatch.group(1)?.trim() ?? '';
        continue;
      }

      final optionMatch = RegExp(r'^[A-Da-d][\).:\-]\s*(.+)$').firstMatch(line);
      if (optionMatch != null) {
        currentOptions.add(optionMatch.group(1)?.trim() ?? '');
        continue;
      }

      final answerMatch = RegExp(
        r'^(?:answer|correct)\s*[:\-]\s*([A-Da-d])$',
        caseSensitive: false,
      ).firstMatch(line);
      if (answerMatch != null) {
        final char = answerMatch.group(1)?.toUpperCase() ?? 'A';
        currentAnswer = char.codeUnitAt(0) - 65;
        continue;
      }

      if (currentQuestion.isNotEmpty && currentOptions.isEmpty) {
        currentQuestion = '$currentQuestion $line';
      }
    }
    flush();
    return questions;
  }

  Future<String> _inferSubjectFromAttachments({
    required List<Map<String, dynamic>> attachments,
  }) async {
    if (attachments.isEmpty) return widget.resourceContext?.subject ?? '';
    final contextFilters = _buildContextFilters();
    try {
      final response = await _api.queryRag(
        question:
            'Identify the exact academic subject from attached notes. '
            'Return strict JSON only: {"subject":"<subject name>"}',
        collegeId: widget.collegeId,
        fileId: widget.resourceContext?.fileId,
        allowWeb: false,
        useOcr: true,
        forceOcr: true,
        ocrProvider: 'google_vision',
        attachments: attachments,
        filters: contextFilters,
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

  List<Map<String, dynamic>> _serializeStickyAttachments() {
    return _stickyAttachments
        .map(
          (attachment) => <String, dynamic>{
            'name': attachment.name,
            'url': attachment.url,
            'is_pdf': attachment.isPdf,
          },
        )
        .toList();
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
          ),
        )
        .where((attachment) => attachment.url.isNotEmpty)
        .toList();
  }

  void _rememberAttachmentsForContext(List<_ChatAttachment> usedAttachments) {
    if (usedAttachments.isEmpty) return;
    final merged = <_ChatAttachment>[..._stickyAttachments];

    for (final attachment in usedAttachments) {
      final existingIndex = merged.indexWhere((item) => item.url == attachment.url);
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
      List<dynamic> scoped = <dynamic>[];
      if (subject.isNotEmpty) {
        scoped = await _supabase.getResources(
          collegeId: widget.collegeId,
          semester: semester,
          branch: branch,
          subject: subject,
          limit: 8,
        );
      }

      if (scoped.isEmpty && subject.isNotEmpty) {
        scoped = await _supabase.getResources(
          collegeId: widget.collegeId,
          semester: semester,
          branch: branch,
          searchQuery: subject,
          limit: 8,
        );
      }

      if (scoped.isEmpty) {
        scoped = await _supabase.getResources(
          collegeId: widget.collegeId,
          semester: semester,
          branch: branch,
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

      return scoped
          .where((resource) => resource.fileUrl.trim().isNotEmpty)
          .map(
            (resource) => <String, dynamic>{
              'name': resource.title,
              'url': resource.fileUrl,
              'type': _attachmentTypeFromUrl(resource.fileUrl),
            },
          )
          .toList();
    } catch (e) {
      debugPrint('Subject resource lookup failed: $e');
      return const [];
    }
  }

  String _buildQuestionPaperPrompt({
    required String userPrompt,
    required String semester,
    required String branch,
    required String inferredSubject,
    required int contextResourcesCount,
  }) {
    final subjectLine = inferredSubject.trim().isEmpty
        ? 'Infer from attached notes and PYQs'
        : inferredSubject.trim();
    return '''
Generate a university-style question paper quiz.
User request: "$userPrompt"
Semester: $semester
Branch: $branch
Subject: $subjectLine
Attached study documents available: $contextResourcesCount

Requirements:
1) Analyze available notes/resources to match exam pattern and difficulty.
2) Generate exactly 20 MCQs.
3) 4 options per question.
4) Include one correct answer.
5) Include concise explanation.
6) For each question include source mapping in "source" using title/section/pages.

Return STRICT JSON only (no markdown):
{
  "title": "Question Paper",
  "subject": "Subject Name",
  "instructions": ["instruction 1", "instruction 2"],
  "questions": [
    {
      "question": "Question text",
      "options": ["A option", "B option", "C option", "D option"],
      "answer": "A",
      "explanation": "Short reason",
      "source": {
        "title": "Document title",
        "section": "Chapter or topic",
        "pages": "12-14",
        "note": "Any supporting reference"
      }
    }
  ]
}
''';
  }

  AiQuestionPaper? _parseQuestionPaper({
    required String rawResponse,
    required String semester,
    required String branch,
    required String fallbackSubject,
    required int contextResourceCount,
  }) {
    final decoded = _decodeJsonMapFromText(rawResponse);
    final questions = <AiQuestionPaperQuestion>[];
    var subject = fallbackSubject.trim();
    var title = 'Generated Question Paper';
    var instructions = <String>[];

    if (decoded != null) {
      final parsedSubject = decoded['subject']?.toString().trim() ?? '';
      if (parsedSubject.isNotEmpty) subject = parsedSubject;
      final parsedTitle = decoded['title']?.toString().trim() ?? '';
      if (parsedTitle.isNotEmpty) title = parsedTitle;
      instructions = ((decoded['instructions'] as List?) ?? const [])
          .map((line) => line.toString().trim())
          .where((line) => line.isNotEmpty)
          .toList();

      final rawQuestions = ((decoded['questions'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      for (final raw in rawQuestions) {
        final questionText = raw['question']?.toString().trim() ?? '';
        final options = ((raw['options'] as List?) ?? const [])
            .map((opt) => opt.toString().trim())
            .where((opt) => opt.isNotEmpty)
            .toList();
        if (questionText.isEmpty || options.length < 2) continue;

        final sourceRaw = raw['source'];
        final source = sourceRaw is Map
            ? AiQuestionPaperSource(
                title: sourceRaw['title']?.toString() ?? '',
                section: sourceRaw['section']?.toString() ?? '',
                pages: sourceRaw['pages']?.toString() ?? '',
                note: sourceRaw['note']?.toString() ?? '',
              )
            : AiQuestionPaperSource(note: sourceRaw?.toString() ?? '');

        questions.add(
          AiQuestionPaperQuestion(
            question: questionText,
            options: options,
            correctIndex: _resolveAnswerIndex(
              answer: raw['answer'],
              options: options,
            ),
            explanation: raw['explanation']?.toString() ?? '',
            source: source,
          ),
        );
      }
    }

    if (questions.isEmpty) {
      questions.addAll(_parsePlainTextMcqs(rawResponse));
    }
    if (questions.isEmpty) return null;
    if (subject.isEmpty) subject = 'General';

    return AiQuestionPaper(
      title: title,
      subject: subject,
      semester: semester,
      branch: branch,
      instructions: instructions,
      questions: questions,
      generatedAt: DateTime.now(),
      pyqCount: contextResourceCount,
    );
  }

  String _buildQuestionPaperSummary(AiQuestionPaper paper) {
    return 'Question paper generated for ${paper.subject} '
        '(Sem ${paper.semester}, ${paper.branch}).\n'
        'Questions: ${paper.questions.length} | Context docs analyzed: ${paper.pyqCount}\n\n'
        'Tap "Start Quiz" to attempt the full-screen quiz.';
  }

  Future<void> _handleQuestionPaperGeneration({
    required String userPrompt,
    required String userVisible,
    required List<Map<String, dynamic>> attachmentPayload,
    required _QuestionPaperRequestConfig config,
  }) async {
    final tracker = _startLongResponseTracker('Question paper generation');
    final history = _buildStructuredHistory(pendingUserPrompt: userPrompt);

    setState(() {
      _messages.add(AIChatMessage(isUser: true, content: userVisible));
      _isLoading = true;
      _controller.clear();
      _attachments.clear();
    });
    await _persistCurrentSession();
    await _scrollToBottom();

    try {
      final contextFilters = _buildContextFilters();
      final inferredFromPrompt = _extractTopicFromPrompt(userPrompt);
      final inferredFromAttachments = await _inferSubjectFromAttachments(
        attachments: attachmentPayload,
      );
      final inferredSubject = inferredFromPrompt.isNotEmpty
          ? inferredFromPrompt
          : inferredFromAttachments;

      final contextAttachments = await _loadSubjectAttachments(
        semester: config.semester,
        branch: config.branch,
        inferredSubject: inferredSubject,
      );
      final mergedAttachments = <Map<String, dynamic>>[
        ...attachmentPayload,
        ...contextAttachments,
      ];
      final prompt = _buildQuestionPaperPrompt(
        userPrompt: userPrompt,
        semester: config.semester,
        branch: config.branch,
        inferredSubject: inferredSubject,
        contextResourcesCount: contextAttachments.length,
      );

      final response = await _api.queryRag(
        question: prompt,
        collegeId: widget.collegeId,
        fileId: widget.resourceContext?.fileId,
        allowWeb: false,
        useOcr: true,
        forceOcr: true,
        ocrProvider: 'google_vision',
        attachments: mergedAttachments,
        history: history,
        filters: contextFilters,
      );
      final answer = _extractRagAnswer(response);
      final paper = _parseQuestionPaper(
        rawResponse: answer,
        semester: config.semester,
        branch: config.branch,
        fallbackSubject: inferredSubject,
        contextResourceCount: contextAttachments.length,
      );

      if (paper == null) {
        setState(() {
          _messages.add(
            AIChatMessage(
              isUser: false,
              content: answer.trim().isEmpty
                  ? 'Failed to generate question paper from attachments.'
                  : answer,
            ),
          );
        });
        await _persistCurrentSession();
        return;
      }

      setState(() {
        _messages.add(
          AIChatMessage(
            isUser: false,
            content: _buildQuestionPaperSummary(paper),
            quizActionPaper: paper,
          ),
        );
      });
      await _persistCurrentSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          AIChatMessage(
            isUser: false,
            content:
                'Question paper generation failed: '
                '${e.toString().replaceFirst('Exception: ', '')}',
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
        notificationTitle: 'Question Paper Ready',
        notificationBody: 'Your generated quiz is ready to attempt.',
      );
    }
  }

  Future<void> _handleSummaryExport({
    required String userPrompt,
    required String userVisible,
    required List<Map<String, dynamic>> attachmentPayload,
  }) async {
    final tracker = _startLongResponseTracker('Summary export');
    final history = _buildStructuredHistory(pendingUserPrompt: userPrompt);
    setState(() {
      _messages.add(AIChatMessage(isUser: true, content: userVisible));
      _isLoading = true;
      _controller.clear();
      _attachments.clear();
    });
    await _persistCurrentSession();
    await _scrollToBottom();

    try {
      final contextFilters = _buildContextFilters();
      final prompt = _buildRagPrompt(
        userPrompt:
            '$userPrompt\n\nOutput instruction: generate a structured report-ready summary.',
        hasAttachments: attachmentPayload.isNotEmpty,
      );
      final response = await _api.queryRag(
        question: prompt,
        collegeId: widget.collegeId,
        fileId: widget.resourceContext?.fileId,
        allowWeb: false,
        useOcr: true,
        forceOcr: true,
        ocrProvider: 'google_vision',
        attachments: attachmentPayload,
        history: history,
        filters: contextFilters,
      );
      final answer = _sanitizeAssistantAnswerText(
        _extractRagAnswer(response).trim(),
      );
      if (answer.isEmpty) {
        setState(() {
          _messages.add(
            AIChatMessage(
              isUser: false,
              content:
                  'I could not generate a summary from the uploaded files.',
            ),
          );
        });
        await _persistCurrentSession();
        return;
      }

      final file = await _summaryPdfService.saveSummaryPdf(
        title: 'AI_Report_${DateTime.now().millisecondsSinceEpoch}',
        summary: answer,
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
    final attachmentPayload = effectiveAttachments
        .map(
          (item) => <String, dynamic>{
            'name': item.name,
            'url': item.url,
            'type': item.isPdf ? 'pdf' : 'image',
          },
        )
        .toList();
    final sendPrompt = _buildRagPrompt(
      userPrompt: userPrompt,
      hasAttachments: hasAttachments,
    );
    final history = _buildStructuredHistory(pendingUserPrompt: userPrompt);
    final contextFilters = _buildContextFilters();
    final shouldForceVisionOcr = attachmentPayload.isNotEmpty;
    final userVisible = turnAttachments.isEmpty
        ? userPrompt
        : '$userPrompt\n\n${turnAttachments.length} attachments added.';
    final isQuestionPaperRequest = _isQuestionPaperIntent(
      prompt: userPrompt,
      hasAttachments: hasAttachments,
    );
    final isSummaryExportRequest = _isSummaryExportIntent(
      prompt: userPrompt,
      hasAttachments: hasAttachments,
    );

    if (isSummaryExportRequest) {
      await _handleSummaryExport(
        userPrompt: userPrompt,
        userVisible: userVisible,
        attachmentPayload: attachmentPayload,
      );
      return;
    }

    if (isQuestionPaperRequest) {
      final config = await _resolveQuestionPaperConfig();
      if (config == null) return;
      await _handleQuestionPaperGeneration(
        userPrompt: userPrompt,
        userVisible: userVisible,
        attachmentPayload: attachmentPayload,
        config: config,
      );
      return;
    }

    final tracker = _startLongResponseTracker('AI response generation');

    setState(() {
      _messages.add(AIChatMessage(isUser: true, content: userVisible));
      _isLoading = true;
      _controller.clear();
      _attachments.clear();
    });
    await _persistCurrentSession();
    await _scrollToBottom();

    AIChatMessage? aiMessageForError;
    var malformedChunkCount = 0;

    try {
      _resetTypingRenderer();
      final aiMessage = AIChatMessage(isUser: false, content: '');
      aiMessageForError = aiMessage;

      setState(() {
        _messages.add(aiMessage);
      });
      await _scrollToBottom();

      final stream = _api.queryRagStream(
        question: sendPrompt,
        collegeId: widget.collegeId,
        fileId: widget.resourceContext?.fileId,
        allowWeb: true,
        useOcr: shouldForceVisionOcr,
        forceOcr: shouldForceVisionOcr,
        ocrProvider: shouldForceVisionOcr ? 'google_vision' : null,
        attachments: attachmentPayload,
        history: history,
        filters: contextFilters,
      );

      var receivedContent = false;
      await for (final chunkStr in stream) {
        if (!mounted) break;
        try {
          final chunk = jsonDecode(chunkStr);
          final type = chunk['type'];

          if (type == 'metadata') {
            final data = chunk['data'] as Map<String, dynamic>? ?? {};
            final sourcesRaw = (data['sources'] as List?) ?? const [];
            final sources = sourcesRaw
                .whereType<Map>()
                .map((s) => RagSource.fromJson(Map<String, dynamic>.from(s)))
                .toList();

            setState(() {
              aiMessage.sources = sources;
              aiMessage.noLocal = data['no_local'] == true;
            });
          } else if (type == 'chunk') {
            final textChunk = chunk['text']?.toString() ?? '';
            if (textChunk.trim().isNotEmpty) {
              receivedContent = true;
            }
            _enqueueTypedChunk(aiMessage, textChunk);
          } else if (type == 'error') {
            _enqueueTypedChunk(aiMessage, '\n\nError: ${chunk['message']}');
          } else if (type == 'done') {
            // Done
          }
        } catch (e, st) {
          debugPrint('Chunk parse error: $e\nStack: $st');
          malformedChunkCount++;
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
      if (receivedContent) {
        setState(() {
          aiMessage.content = _sanitizeAssistantAnswerText(aiMessage.content);
        });
      }

      await _persistCurrentSession();
    } catch (e) {
      _streamTypingDone = true;
      _completeTypingDrainIfDrained();
      await _waitForTypingDrain();
      if (mounted) {
        setState(() {
          if (aiMessageForError != null) {
            aiMessageForError.content +=
                '\n\n${e.toString().replaceFirst('Exception: ', '')}';
          } else {
            _messages.add(
              AIChatMessage(
                isUser: false,
                content: e.toString().replaceFirst('Exception: ', ''),
              ),
            );
          }
        });
        await _persistCurrentSession();
      }
    } finally {
      _resetTypingRenderer();
      if (mounted) {
        setState(() => _isLoading = false);
        await _scrollToBottom();
      }
      await _finishLongResponseTracker(
        tracker: tracker,
        notificationTitle: 'AI Response Ready',
        notificationBody: 'Your AI answer is ready in StudySpace.',
      );
    }
  }

  Future<void> _pickAttachment() async {
    if (_isUploadingAttachment || _isLoading) return;

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
      final url = await CloudinaryService.uploadFile(file);
      if (!mounted) return;
      setState(() {
        _attachments.add(
          _ChatAttachment(name: file.name, url: url, isPdf: isPdf),
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

  Widget _buildMessageBubble(
    AIChatMessage msg,
    bool isDark,
    int index,
    double screenWidth,
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

    final messageBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!msg.isUser)
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.asset(
                  'assets/images/ai_logo.png',
                  width: 15,
                  height: 15,
                ),
              ),
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
        Text(
          msg.content,
          style: GoogleFonts.inter(
            fontSize: isCompact ? 13.5 : 14,
            height: 1.46,
            color: textColor,
            letterSpacing: 0.05,
          ),
        ),
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
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: msg.sources.map((s) {
              final label = s.startPage != null && s.endPage != null
                  ? '${s.title} (p${s.startPage}-${s.endPage})'
                  : s.title;
              return InkWell(
                onTap: s.fileUrl == null
                    ? null
                    : () async {
                        final uri = Uri.tryParse(s.fileUrl!);
                        if (uri != null) {
                          final host = uri.host.toLowerCase();
                          final isInternal =
                              host == AppConfig.webDomain ||
                              host.endsWith(_internalDomainSuffix);
                          if (isInternal) {
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PdfViewerScreen(
                                  pdfUrl: s.fileUrl!,
                                  title: s.title,
                                  resourceId: s.fileId,
                                  collegeId: widget.collegeId,
                                ),
                              ),
                            );
                          } else if (await canLaunchUrl(uri)) {
                            if (!mounted) return;
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Could not open ${s.title}'),
                              ),
                            );
                          }
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
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: isCompact ? 10 : 10.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        if (!msg.isUser && msg.quizActionPaper != null) ...[
          const SizedBox(height: 10),
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
                          Container(
                            width: 118,
                            height: 118,
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.36),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.24,
                                  ),
                                  blurRadius: 38,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.asset(
                                'assets/images/ai_logo.png',
                                fit: BoxFit.cover,
                              ),
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

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isCompact = screenWidth < 380;
    final isSmallPhone = screenWidth < 350;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBodyTopPadding = mediaQuery.padding.top + kToolbarHeight + 6;
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
    final composerMinHeight = (isSmallPhone ? 40.0 : (isCompact ? 42.0 : 46.0))
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
    final attachButtonSize = isSmallPhone ? 34.0 : (isCompact ? 36.0 : 38.0);
    final sendButtonSize = isSmallPhone ? 36.0 : (isCompact ? 38.0 : 42.0);
    final inputBorderRadius = isSmallPhone ? 20.0 : (isCompact ? 22.0 : 24.0);
    final inputContainerPadding = EdgeInsets.fromLTRB(
      isSmallPhone ? 6 : (isCompact ? 8 : 10),
      isSmallPhone ? 3 : (isCompact ? 4 : 6),
      isSmallPhone ? 5 : (isCompact ? 6 : 8),
      isSmallPhone ? 3 : (isCompact ? 4 : 6),
    );
    final sendIconSize = isSmallPhone ? 16.0 : 17.0;
    final textFieldStyle = GoogleFonts.inter(
      color: isDark ? Colors.white : Colors.black87,
      fontSize: isSmallPhone ? 14 : 15,
    );
    final hintStyle = GoogleFonts.inter(
      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
      fontSize: isSmallPhone ? 14 : 15,
    );
    final inputContentPadding = EdgeInsets.symmetric(
      horizontal: 2,
      vertical: isSmallPhone ? 8 : 10,
    );
    final inputMaxHeight = isSmallPhone ? 126.0 : 152.0;
    final typingWidth = (screenWidth * 0.31).clamp(102.0, 146.0).toDouble();
    final typingPadding = EdgeInsets.all(isSmallPhone ? 10 : 12);
    final typingMargin = EdgeInsets.symmetric(vertical: isSmallPhone ? 4 : 6);
    final typingBorderRadius = BorderRadius.only(
      topLeft: Radius.circular(isSmallPhone ? 18 : 20),
      topRight: Radius.circular(isSmallPhone ? 18 : 20),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(isSmallPhone ? 18 : 20),
    );
    final typingShadow = BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 5,
      offset: const Offset(0, 2),
    );
    final attachmentNameStyle = GoogleFonts.inter(
      fontSize: isSmallPhone ? 10 : (isCompact ? 10.5 : 11),
      color: isDark ? Colors.white70 : Colors.black87,
      fontWeight: FontWeight.w600,
    );

    if (_showEntrySplash) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF04070F) : Colors.white,
        body: _buildEntrySplash(isDark),
      );
    }

    final chatScaffold = Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFF2F2F7),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor:
            (isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7))
                .withValues(alpha: 0.78),
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
              _isStudioChat ? widget.collegeName : 'Smart study assistant',
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
                                child: Container(
                                  width: isCompact ? 82 : 92,
                                  height: isCompact ? 82 : 92,
                                  padding: EdgeInsets.all(isCompact ? 12 : 14),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(
                                      isCompact ? 22 : 24,
                                    ),
                                    border: Border.all(
                                      color: AppTheme.primary.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primary.withValues(
                                          alpha: isDark ? 0.18 : 0.12,
                                        ),
                                        blurRadius: 26,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      isCompact ? 10 : 12,
                                    ),
                                    child: Image.asset(
                                      'assets/images/ai_logo.png',
                                      fit: BoxFit.cover,
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
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: typingWidth,
                              margin: typingMargin,
                              padding: typingPadding,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFFE9E9EB),
                                borderRadius: typingBorderRadius,
                                boxShadow: [typingShadow],
                              ),
                              child: const BrandedLoader(
                                compact: true,
                                showQuotes: false,
                                message: 'Thinking...',
                              ),
                            ),
                          );
                        }

                        final m = _messages[index];
                        return Align(
                          alignment: m.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: bubbleMaxWidth,
                            ),
                            child: _buildMessageBubble(
                              m,
                              isDark,
                              index,
                              screenWidth,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Input area
            SafeArea(
              top: false,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: inputOuterPadding,
                    decoration: BoxDecoration(
                      color:
                          (isDark
                                  ? const Color(0xFF1C1C1E)
                                  : const Color(0xFFF2F2F7))
                              .withValues(alpha: 0.85),
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
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
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
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
                                        color: isDark ? Colors.white70 : Colors.black87,
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
                                        color: isDark ? Colors.white54 : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Container(
                          constraints: BoxConstraints(
                            minHeight: composerMinHeight,
                            maxHeight: inputMaxHeight,
                          ),
                          padding: inputContainerPadding,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(
                              inputBorderRadius,
                            ),
                            border: Border.all(
                              color: isDark
                                  ? Colors.transparent
                                  : const Color(0xFFD1D1D6),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                key: _coachAttachKey,
                                tooltip: 'Attach image or PDF',
                                onPressed:
                                    (_isLoading || _isUploadingAttachment)
                                    ? null
                                    : _pickAttachment,
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints.tightFor(
                                  width: attachButtonSize,
                                  height: attachButtonSize,
                                ),
                                icon: _isUploadingAttachment
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        Icons.add_rounded,
                                        color: isDark
                                            ? Colors.white70
                                            : AppTheme.primary,
                                      ),
                              ),
                              Expanded(
                                child: TextField(
                                  key: _coachInputKey,
                                  controller: _controller,
                                  minLines: 1,
                                  maxLines: 6,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendMessage(),
                                  style: textFieldStyle,
                                  decoration: InputDecoration(
                                    hintText: 'Message AI...',
                                    hintStyle: hintStyle,
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: inputContentPadding,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                key: _coachSendKey,
                                width: sendButtonSize,
                                height: sendButtonSize,
                                decoration: BoxDecoration(
                                  color: (_isLoading || _isUploadingAttachment)
                                      ? Colors.grey
                                      : AppTheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed:
                                      (_isLoading || _isUploadingAttachment)
                                      ? null
                                      : _sendMessage,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    Icons.arrow_upward_rounded,
                                    size: sendIconSize,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
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
    );

    if (!_showCoachMarks) {
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
