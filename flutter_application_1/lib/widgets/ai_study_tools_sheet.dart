import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../config/theme.dart';
import '../models/ai_question_paper.dart';
import '../screens/ai_chat_screen.dart';
import '../screens/ai_question_paper_quiz_screen.dart';
import '../services/analytics_service.dart';
import '../services/ai_chat_notification_service.dart';
import '../services/ai_output_local_service.dart';
import '../services/backend_api_service.dart';
import '../services/subscription_service.dart';
import '../services/summary_pdf_service.dart';
import '../services/supabase_service.dart';
import 'ai_formatted_text.dart';
import 'ai_loading_game_card.dart';
import 'ai_logo.dart';
import 'paywall_dialog.dart';

class QuizQuestion {
  final String question;
  final List<String> options;
  final String correct;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.correct,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = (json['options'] as List?) ?? const [];
    return QuizQuestion(
      question: json['question']?.toString() ?? '',
      options: rawOptions.map((o) => o.toString()).toList(),
      correct: json['correct']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'question': question, 'options': options, 'correct': correct};
  }
}

class Flashcard {
  final String front;
  final String back;

  Flashcard({required this.front, required this.back});

  factory Flashcard.fromJson(Map<String, dynamic> json) {
    return Flashcard(
      front: json['front']?.toString() ?? '',
      back: json['back']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'front': front, 'back': back};
  }
}

class AiStudyToolsSheet extends StatefulWidget {
  final String resourceId;
  final String resourceTitle;
  final String? collegeId;
  final String? collegeName;
  final String? subject;
  final String? semester;
  final String? branch;
  final String resourceType;
  final String? videoUrl;
  final int initialTabIndex;
  final String? autoGenerateType;
  final AiOutputLocalService localStore;
  final SummaryPdfService summaryPdfService;

  AiStudyToolsSheet({
    super.key,
    required this.resourceId,
    required this.resourceTitle,
    this.collegeId,
    this.collegeName,
    this.subject,
    this.semester,
    this.branch,
    this.resourceType = 'notes',
    this.videoUrl,
    this.initialTabIndex = 0,
    this.autoGenerateType,
    AiOutputLocalService? localStore,
    SummaryPdfService? summaryPdfService,
  }) : localStore = localStore ?? AiOutputLocalService(),
       summaryPdfService = summaryPdfService ?? SummaryPdfService();

  @override
  State<AiStudyToolsSheet> createState() => _AiStudyToolsSheetState();
}

class _AiStudyToolsSheetState extends State<AiStudyToolsSheet>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AnalyticsService _analytics = AnalyticsService.instance;
  final BackendApiService _api = BackendApiService();
  final SupabaseService _supabaseService = SupabaseService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  static const Color _studioBlue = Color(0xFF2563EB);
  static const Color _studioBlueDark = Color(0xFF1D4ED8);
  static const Duration _aiJobPollInterval = Duration(seconds: 3);
  static const List<String> _backgroundGenerationTypes = <String>[
    'summary',
    'quiz',
    'flashcards',
  ];

  late TabController _tabController;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDownloadingSummary = false;
  bool _isDownloadingFlashcards = false;
  final GlobalKey _pdfButtonKey = GlobalKey();
  String? _loadingType;
  String? _error;

  String? _summary;
  List<QuizQuestion>? _quiz;
  List<Flashcard>? _flashcards;

  bool _useOcr = true;
  bool _forceOcr = false;
  bool _showAnswers = false;
  final Map<int, String> _selectedAnswers = {};
  final Set<int> _flippedCardIndexes = <int>{};
  late final PageController _flashcardPageController;
  int _activeFlashcardIndex = 0;

  final Map<String, bool> _cachedMap = {};
  final Map<String, bool> _savedLocallyMap = {};

  bool _isFullscreen = false;
  Timer? _aiJobPollTimer;
  bool _isPollingPendingJob = false;
  String? _pendingJobType;
  String? _pendingJobId;
  String? _pendingJobStage;
  String? _pendingJobStatusReason;
  int? _pendingJobProgress;
  int? _pendingJobElapsedMs;
  int? _pendingJobEstimatedTotalMs;
  int? _pendingJobEstimatedRemainingMs;
  bool _pendingJobRestored = false;

  // Multi-PDF question paper selection
  final Set<String> _extraPdfIds = {};
  bool _isMultiQuizLoading = false;
  String? _multiQuizError;

  bool get _supportsOcr => widget.resourceType != 'video';

  Map<String, Object?> _baseAnalyticsParameters() {
    return <String, Object?>{
      'resource_type': widget.resourceType,
      'supports_ocr': _supportsOcr,
      'has_video': widget.videoUrl?.trim().isNotEmpty == true,
    };
  }

  String _tabNameForIndex(int index) {
    switch (index) {
      case 0:
        return 'summary';
      case 1:
        return 'quiz';
      case 2:
        return 'flashcards';
      case 3:
        return 'chat';
      default:
        return 'unknown';
    }
  }

  Future<void> _trackAiStudioOpened() async {
    await _analytics.trackScreenView(screenName: 'ai_studio');
    await _analytics.logEvent(
      'ai_studio_open',
      parameters: <String, Object?>{
        ..._baseAnalyticsParameters(),
        'initial_tab': _tabNameForIndex(_tabController.index),
        'auto_type': widget.autoGenerateType?.trim().toLowerCase(),
      },
    );
  }

  String _classifyGenerationError(String message) {
    final lowered = message.toLowerCase();
    if (_looksLikeTokenLimitError(message)) return 'token_limit';
    if (_looksLikeHighTrafficError(message)) return 'traffic';
    if (lowered.contains('socket') ||
        lowered.contains('host lookup') ||
        lowered.contains('network')) {
      return 'network';
    }
    if (lowered.contains('timeout')) return 'timeout';
    if (lowered.contains('valid quiz') ||
        lowered.contains('valid flashcards')) {
      return 'format';
    }
    return 'unknown';
  }

  bool _looksLikeHighTrafficError(String message) {
    final lowered = message.toLowerCase();
    return lowered.contains('rate limit') ||
        lowered.contains('too many requests') ||
        lowered.contains('http 429') ||
        lowered.contains('high traffic');
  }

  String _presentGenerationError(String message) {
    if (_looksLikeTokenLimitError(message)) {
      return 'Your AI tokens are too low for this request. Recharge AI tokens to continue generating content.';
    }
    if (_looksLikeHighTrafficError(message)) {
      return 'StudyShare is seeing high traffic right now. Please try again in a moment.';
    }
    return message;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flashcardPageController = PageController(viewportFraction: 0.9);
    final safeInitialIndex = widget.initialTabIndex.clamp(0, 3).toInt();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: safeInitialIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      unawaited(
        _analytics.logEvent(
          'ai_studio_tab_view',
          parameters: <String, Object?>{
            ..._baseAnalyticsParameters(),
            'tab': _tabNameForIndex(_tabController.index),
          },
        ),
      );
      if (mounted) setState(() {});
    });
    unawaited(AiChatNotificationService.instance.initialize());
    unawaited(_trackAiStudioOpened());
    _loadSavedOutputs().then((_) async {
      if (!mounted) return;
      await _restorePendingGeneration();
      if (!mounted) return;
      _handleInitialAutoGeneration();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPendingJobPolling();
    _subscriptionService.dispose();
    _flashcardPageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_pendingJobType == null || _pendingJobId == null) return;
    unawaited(_pollPendingJob(force: true));
    _ensurePendingJobPolling();
  }

  void _resetFlashcardDeckToStart() {
    _activeFlashcardIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_flashcardPageController.hasClients) return;
      _flashcardPageController.jumpToPage(0);
    });
  }

  void _handleInitialAutoGeneration() {
    final rawType = widget.autoGenerateType?.trim().toLowerCase();
    if (rawType == null || rawType.isEmpty) return;
    if (rawType == 'chat') return;
    if (rawType != 'summary' && rawType != 'quiz' && rawType != 'flashcards') {
      return;
    }
    if (_hasOutput(rawType)) return;
    _generate(rawType, regenerate: false);
  }

  Future<void> _animateToFlashcardIndex(int targetIndex) async {
    final cards = _flashcards;
    if (cards == null || cards.isEmpty) return;
    final maxIndex = cards.length - 1;
    final bounded = targetIndex.clamp(0, maxIndex).toInt();
    if (!_flashcardPageController.hasClients) {
      setState(() => _activeFlashcardIndex = bounded);
      return;
    }
    await _flashcardPageController.animateToPage(
      bounded,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadSavedOutputs() async {
    try {
      final results = await Future.wait([
        widget.localStore.loadOutput(
          resourceId: widget.resourceId,
          type: 'summary',
        ),
        widget.localStore.loadOutput(
          resourceId: widget.resourceId,
          type: 'quiz',
        ),
        widget.localStore.loadOutput(
          resourceId: widget.resourceId,
          type: 'flashcards',
        ),
      ]);

      if (!mounted) return;

      final loadedSummary = results[0] is String ? results[0] as String : null;
      final loadedQuiz = _parseSavedQuiz(results[1]);
      final loadedFlashcards = _parseSavedFlashcards(results[2]);

      setState(() {
        _summary = loadedSummary;
        _quiz = loadedQuiz;
        _flashcards = loadedFlashcards;
        _activeFlashcardIndex = 0;
        if (loadedSummary != null && loadedSummary.trim().isNotEmpty) {
          _savedLocallyMap['summary'] = true;
        }
        if (loadedQuiz != null && loadedQuiz.isNotEmpty) {
          _savedLocallyMap['quiz'] = true;
        }
        if (loadedFlashcards != null && loadedFlashcards.isNotEmpty) {
          _savedLocallyMap['flashcards'] = true;
        }
      });
      if (loadedFlashcards != null && loadedFlashcards.isNotEmpty) {
        _resetFlashcardDeckToStart();
      }
    } catch (e) {
      // Silently ignore load errors - user can regenerate content
      debugPrint('Failed to load saved outputs: $e');
    }
  }

  String _buildAiClientRequestId(String type) {
    return 'studio:${widget.resourceId}:$type:${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> _normalizeAiStudioResponse(Map<String, dynamic> raw) {
    final outerData = raw['data'];
    if (outerData is Map) {
      final nested = outerData.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      return <String, dynamic>{
        'data': nested.containsKey('data') ? nested['data'] : nested,
        'cached': nested['cached'] == true || raw['cached'] == true,
        'source': nested['source'] ?? raw['source'],
        'studio_kind': nested['studio_kind'] ?? raw['studio_kind'],
      };
    }
    return <String, dynamic>{
      'data': outerData,
      'cached': raw['cached'] == true,
      'source': raw['source'],
      'studio_kind': raw['studio_kind'],
    };
  }

  Future<Map<String, dynamic>> _requestBackgroundGeneration({
    required String type,
    required bool regenerate,
    required bool useOcr,
    required bool forceOcr,
    required String clientRequestId,
  }) {
    switch (type) {
      case 'summary':
        return _api.getAiSummary(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          force: regenerate,
          includeSource: false,
          videoUrl: widget.videoUrl,
          asyncRequested: true,
          clientRequestId: clientRequestId,
        );
      case 'quiz':
        return _api.getAiQuiz(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          force: regenerate,
          includeSource: false,
          videoUrl: widget.videoUrl,
          asyncRequested: true,
          clientRequestId: clientRequestId,
        );
      default:
        return _api.getAiFlashcards(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          force: regenerate,
          includeSource: false,
          videoUrl: widget.videoUrl,
          asyncRequested: true,
          clientRequestId: clientRequestId,
        );
    }
  }

  Future<void> _persistGeneratedOutput(String type, dynamic data) async {
    if (data == null) return;
    await widget.localStore.saveOutput(
      resourceId: widget.resourceId,
      type: type,
      data: data,
    );
  }

  Future<int> _applyGeneratedResponse(
    String type,
    Map<String, dynamic> rawResponse, {
    required bool regenerate,
    required bool useOcr,
    required bool forceOcr,
    bool persistLocally = false,
    bool notifyOnReady = false,
  }) async {
    final response = _normalizeAiStudioResponse(rawResponse);
    final cached = response['cached'] == true;
    late final int outputSize;
    dynamic persistPayload;

    if (type == 'summary') {
      final data = response['data'];
      final summaryText = data is String
          ? data.trim()
          : data?.toString().trim();
      if (summaryText == null || summaryText.isEmpty) {
        throw Exception('Could not create a valid summary. Please try again.');
      }
      outputSize = summaryText.length;
      persistPayload = summaryText;
      if (!mounted) return outputSize;
      setState(() {
        _summary = summaryText;
        _cachedMap['summary'] = cached;
        _savedLocallyMap['summary'] = persistLocally;
        _isLoading = false;
        _loadingType = null;
        _error = null;
      });
    } else if (type == 'quiz') {
      final parsed = _parseQuizPayload(response);
      if (parsed.isEmpty) {
        throw Exception(
          'Could not create a valid quiz from the AI response. Please try again.',
        );
      }
      outputSize = parsed.length;
      persistPayload = parsed.map((q) => q.toJson()).toList();
      if (!mounted) return outputSize;
      setState(() {
        _quiz = parsed;
        _selectedAnswers.clear();
        _showAnswers = false;
        _cachedMap['quiz'] = cached;
        _savedLocallyMap['quiz'] = persistLocally;
        _isLoading = false;
        _loadingType = null;
        _error = null;
      });
    } else {
      final parsed = _parseFlashcardPayload(response);
      if (parsed.isEmpty) {
        throw Exception(
          'Could not create valid flashcards from the AI response. Please try again.',
        );
      }
      outputSize = parsed.length;
      persistPayload = parsed.map((card) => card.toJson()).toList();
      if (!mounted) return outputSize;
      setState(() {
        _flashcards = parsed;
        _flippedCardIndexes.clear();
        _activeFlashcardIndex = 0;
        _cachedMap['flashcards'] = cached;
        _savedLocallyMap['flashcards'] = persistLocally;
        _isLoading = false;
        _loadingType = null;
        _error = null;
      });
      _resetFlashcardDeckToStart();
    }

    if (persistLocally) {
      try {
        await _persistGeneratedOutput(type, persistPayload);
      } catch (e) {
        debugPrint('Failed to persist AI Studio output for $type: $e');
      }
    }

    await _analytics.logEvent(
      'ai_studio_generate_success',
      parameters: <String, Object?>{
        ..._baseAnalyticsParameters(),
        'content_type': type,
        'regenerate': regenerate,
        'use_ocr': useOcr,
        'force_ocr': forceOcr,
        'cached': cached,
        'output_size': outputSize,
        'delivery': persistLocally ? 'background' : 'sync',
      },
    );
    _supabaseService.markAiTokenBalanceStale();

    if (notifyOnReady) {
      await AiChatNotificationService.instance.notifyAnswerReady(
        title: '${_labelForType(type)} ready',
        body: '${widget.resourceTitle} is ready in AI Studio.',
      );
    }

    return outputSize;
  }

  void _stopPendingJobPolling() {
    _aiJobPollTimer?.cancel();
    _aiJobPollTimer = null;
  }

  void _ensurePendingJobPolling() {
    if (_pendingJobType == null || _pendingJobId == null) return;
    _aiJobPollTimer ??= Timer.periodic(_aiJobPollInterval, (_) {
      unawaited(_pollPendingJob());
    });
  }

  Future<void> _clearPendingJob({
    required String type,
    bool clearLoadingState = true,
  }) async {
    _stopPendingJobPolling();
    await widget.localStore.clearPendingJob(
      resourceId: widget.resourceId,
      type: type,
    );
    if (!mounted) return;
    setState(() {
      if (_pendingJobType == type) {
        _pendingJobType = null;
        _pendingJobId = null;
        _pendingJobStage = null;
        _pendingJobStatusReason = null;
        _pendingJobProgress = null;
        _pendingJobElapsedMs = null;
        _pendingJobEstimatedTotalMs = null;
        _pendingJobEstimatedRemainingMs = null;
        _pendingJobRestored = false;
      }
      if (clearLoadingState) {
        _isLoading = false;
        _loadingType = null;
      }
    });
  }

  Future<void> _trackPendingJob({
    required String type,
    required String jobId,
    String? runId,
    String? clientRequestId,
    required bool restored,
  }) async {
    await widget.localStore.savePendingJob(
      resourceId: widget.resourceId,
      type: type,
      jobId: jobId,
      runId: runId,
      clientRequestId: clientRequestId,
    );
    if (!mounted) return;
    setState(() {
      _pendingJobType = type;
      _pendingJobId = jobId;
      _pendingJobStage = 'queued';
      _pendingJobStatusReason = 'queued_for_background_generation';
      _pendingJobProgress = 0;
      _pendingJobElapsedMs = null;
      _pendingJobEstimatedTotalMs = null;
      _pendingJobEstimatedRemainingMs = null;
      _pendingJobRestored = restored;
      _isLoading = true;
      _loadingType = type;
      _error = null;
    });
  }

  int? _readJobDurationMs(
    Map<String, dynamic> response,
    String snakeKey,
    String camelKey,
  ) {
    final raw = response[snakeKey] ?? response[camelKey];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  String? _etaLabel() {
    final remainingMs = _pendingJobEstimatedRemainingMs;
    if (remainingMs != null && remainingMs > 0) {
      final seconds = math.max(1, (remainingMs / 1000).ceil());
      return 'About ${seconds}s remaining';
    }

    final totalMs = _pendingJobEstimatedTotalMs;
    if (totalMs != null && totalMs > 0) {
      final totalSeconds = math.max(1, (totalMs / 1000).round());
      final lower = math.max(1, totalSeconds - 3);
      final upper = totalSeconds + 3;
      return 'Usually $lower-${upper}s';
    }

    return null;
  }

  Future<bool> _pollPendingJob({bool force = false}) async {
    final type = _pendingJobType;
    final jobId = _pendingJobId;
    if (type == null || jobId == null) return true;
    if (_isPollingPendingJob && !force) return false;

    _isPollingPendingJob = true;
    try {
      final response = await _api.getAiJobStatus(jobId);
      final status = response['status']?.toString().trim().toLowerCase() ?? '';
      final stage = response['stage']?.toString().trim();
      final statusReason = response['status_reason']?.toString().trim();
      final progressRaw = response['progress'];
      final progress = progressRaw is num ? progressRaw.toInt() : null;
      final elapsedMs = _readJobDurationMs(response, 'elapsed_ms', 'elapsedMs');
      final estimatedTotalMs = _readJobDurationMs(
        response,
        'estimated_total_ms',
        'estimatedTotalMs',
      );
      final estimatedRemainingMs = _readJobDurationMs(
        response,
        'estimated_remaining_ms',
        'estimatedRemainingMs',
      );
      if (mounted) {
        setState(() {
          _pendingJobStage = stage?.isNotEmpty == true
              ? stage
              : _pendingJobStage;
          _pendingJobStatusReason = statusReason?.isNotEmpty == true
              ? statusReason
              : _pendingJobStatusReason;
          _pendingJobProgress = progress ?? _pendingJobProgress;
          _pendingJobElapsedMs = elapsedMs ?? _pendingJobElapsedMs;
          _pendingJobEstimatedTotalMs =
              estimatedTotalMs ?? _pendingJobEstimatedTotalMs;
          _pendingJobEstimatedRemainingMs =
              estimatedRemainingMs ?? _pendingJobEstimatedRemainingMs;
        });
      }
      if (status == 'completed') {
        final restored = _pendingJobRestored;
        await _applyGeneratedResponse(
          type,
          response,
          regenerate: false,
          useOcr: _supportsOcr && (_useOcr || _forceOcr),
          forceOcr: _supportsOcr && _forceOcr,
          persistLocally: true,
          notifyOnReady: restored,
        );
        await _clearPendingJob(type: type);
        return true;
      }
      if (status == 'failed' || status == 'blocked' || status == 'cancelled') {
        final message = response['error']?.toString().trim().isNotEmpty == true
            ? response['error'].toString().trim()
            : 'AI generation failed. Please try again.';
        await _clearPendingJob(type: type);
        if (mounted) {
          setState(() {
            _error = _presentGenerationError(message);
          });
        }
        return true;
      }
      if (mounted) {
        setState(() {
          _isLoading = true;
          _loadingType = type;
          _pendingJobProgress = progress ?? _pendingJobProgress;
          _pendingJobElapsedMs = elapsedMs ?? _pendingJobElapsedMs;
          _pendingJobEstimatedTotalMs =
              estimatedTotalMs ?? _pendingJobEstimatedTotalMs;
          _pendingJobEstimatedRemainingMs =
              estimatedRemainingMs ?? _pendingJobEstimatedRemainingMs;
        });
      }
      return false;
    } catch (e) {
      debugPrint('Failed to poll AI Studio job $_pendingJobId: $e');
      return false;
    } finally {
      _isPollingPendingJob = false;
    }
  }

  Future<void> _restorePendingGeneration() async {
    for (final type in _backgroundGenerationTypes) {
      final pending = await widget.localStore.loadPendingJob(
        resourceId: widget.resourceId,
        type: type,
      );
      final jobId = pending?['job_id']?.toString().trim() ?? '';
      if (jobId.isEmpty) continue;
      await _trackPendingJob(
        type: type,
        jobId: jobId,
        runId: pending?['run_id']?.toString(),
        clientRequestId: pending?['client_request_id']?.toString(),
        restored: true,
      );
      final finished = await _pollPendingJob(force: true);
      if (!finished) {
        _ensurePendingJobPolling();
      }
      break;
    }
  }

  List<QuizQuestion>? _parseSavedQuiz(dynamic raw) {
    final parsed = _parseQuizPayload(raw);
    return parsed.isEmpty ? null : parsed;
  }

  List<Flashcard>? _parseSavedFlashcards(dynamic raw) {
    final parsed = _parseFlashcardPayload(raw);
    return parsed.isEmpty ? null : parsed;
  }

  List<QuizQuestion> _parseQuizPayload(dynamic raw) {
    final items = _extractStructuredList(
      raw,
      preferredKeys: const [
        'data',
        'quiz',
        'quizzes',
        'questions',
        'mcqs',
        'items',
        'result',
        'results',
      ],
    );
    if (items == null) return const [];

    return items.map(_parseQuizQuestionItem).whereType<QuizQuestion>().toList();
  }

  List<Flashcard> _parseFlashcardPayload(dynamic raw) {
    final items = _extractStructuredList(
      raw,
      preferredKeys: const [
        'data',
        'flashcards',
        'cards',
        'items',
        'result',
        'results',
      ],
    );
    if (items != null) {
      final parsed = items
          .map(_parseFlashcardItem)
          .whereType<Flashcard>()
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }

    return _parseFlashcardTextFallback(raw);
  }

  List<dynamic>? _extractStructuredList(
    dynamic raw, {
    required List<String> preferredKeys,
  }) {
    final decoded = _decodeStructuredValue(raw);
    if (decoded is List) return decoded;
    if (decoded is! Map) return null;

    final map = _stringKeyedMap(decoded);
    for (final key in preferredKeys) {
      final nested = _extractStructuredList(
        map[key],
        preferredKeys: preferredKeys,
      );
      if (nested != null) return nested;
    }

    if (map.length == 1) {
      return _extractStructuredList(
        map.values.first,
        preferredKeys: preferredKeys,
      );
    }

    return null;
  }

  dynamic _decodeStructuredValue(dynamic raw) {
    dynamic current = raw;
    for (var i = 0; i < 3; i++) {
      if (current is! String) return current;
      final trimmed = _stripCodeFence(current).trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          current = jsonDecode(trimmed);
          continue;
        } catch (_) {
          return trimmed;
        }
      }

      final firstObject = trimmed.indexOf('{');
      final lastObject = trimmed.lastIndexOf('}');
      if (firstObject != -1 && lastObject > firstObject) {
        final objectSlice = trimmed.substring(firstObject, lastObject + 1);
        try {
          current = jsonDecode(objectSlice);
          continue;
        } catch (_) {}
      }

      final firstArray = trimmed.indexOf('[');
      final lastArray = trimmed.lastIndexOf(']');
      if (firstArray != -1 && lastArray > firstArray) {
        final arraySlice = trimmed.substring(firstArray, lastArray + 1);
        try {
          current = jsonDecode(arraySlice);
          continue;
        } catch (_) {}
      }

      return trimmed;
    }
    return current;
  }

  List<Flashcard> _parseFlashcardTextFallback(dynamic raw) {
    final decoded = _decodeStructuredValue(raw);
    if (decoded is! String) return const [];
    final text = decoded.trim();
    if (text.isEmpty) return const [];

    final blocks = text
        .split(RegExp(r'\n\s*\n+'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();
    final parsed = <Flashcard>[];

    for (final block in blocks) {
      final lines = block
          .split(RegExp(r'\n+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      String? front;
      String? back;

      for (final line in lines) {
        if (front == null) {
          final frontMatch = RegExp(
            r'^(?:q(?:uestion)?|front|term|prompt)\s*[:\-]\s*(.+)$',
            caseSensitive: false,
          ).firstMatch(line);
          if (frontMatch != null) {
            front = frontMatch.group(1)?.trim();
            continue;
          }
        }
        if (back == null) {
          final backMatch = RegExp(
            r'^(?:a(?:nswer)?|back|definition|explanation|response)\s*[:\-]\s*(.+)$',
            caseSensitive: false,
          ).firstMatch(line);
          if (backMatch != null) {
            back = backMatch.group(1)?.trim();
            continue;
          }
        }
      }

      if ((front == null || back == null) && lines.length >= 2) {
        front ??= lines.first;
        back ??= lines.sublist(1).join(' ').trim();
      }

      if (front == null || back == null) continue;

      final normalizedFront = _normalizeOptionText(front);
      final normalizedBack = _normalizeOptionText(back);
      if (normalizedFront == null || normalizedBack == null) continue;

      parsed.add(Flashcard(front: normalizedFront, back: normalizedBack));
    }

    final seen = <String>{};
    final deduped = <Flashcard>[];
    for (final card in parsed) {
      final key = card.front.toLowerCase();
      if (seen.add(key)) {
        deduped.add(card);
      }
      if (deduped.length >= 25) break;
    }
    return deduped;
  }

  String _stripCodeFence(String raw) {
    final trimmed = raw.trim();
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return match?.group(1) ?? trimmed;
  }

  Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> raw) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  QuizQuestion? _parseQuizQuestionItem(dynamic raw) {
    final decoded = _decodeStructuredValue(raw);
    if (decoded is! Map) return null;

    final item = _stringKeyedMap(decoded);
    final question = _firstNonEmptyString([
      item['question'],
      item['prompt'],
      item['text'],
      item['query'],
      item['title'],
    ]);
    if (question == null) return null;

    final options = _extractOptionList(
      item['options'] ??
          item['choices'] ??
          item['answers'] ??
          item['mcq_options'],
    );
    if (options.length < 2) return null;

    final correct = _normalizeQuizCorrectValue(
      _firstNonEmptyString([
            item['correct'],
            item['answer'],
            item['correct_answer'],
            item['correctOption'],
            item['correct_option'],
            item['solution'],
          ]) ??
          '',
      options,
    );
    if (correct == null) return null;

    return QuizQuestion(question: question, options: options, correct: correct);
  }

  Flashcard? _parseFlashcardItem(dynamic raw) {
    final decoded = _decodeStructuredValue(raw);
    if (decoded is! Map) return null;

    final item = _stringKeyedMap(decoded);
    final front = _firstNonEmptyString([
      item['front'],
      item['question'],
      item['term'],
      item['title'],
      item['prompt'],
      item['heading'],
    ]);
    final back = _firstNonEmptyString([
      item['back'],
      item['answer'],
      item['definition'],
      item['explanation'],
      item['content'],
      item['description'],
      item['note'],
    ]);
    if (front == null || back == null) return null;

    return Flashcard(front: front, back: back);
  }

  List<String> _extractOptionList(dynamic raw) {
    final decoded = _decodeStructuredValue(raw);
    final options = <String>[];

    if (decoded is List) {
      for (final item in decoded) {
        final option = _extractOptionText(item);
        if (option != null) options.add(option);
      }
    } else if (decoded is Map) {
      final item = _stringKeyedMap(decoded);
      for (final value in item.values) {
        final option = _extractOptionText(value);
        if (option != null) options.add(option);
      }
    } else if (decoded is String) {
      for (final line in decoded.split(RegExp(r'[\r\n]+'))) {
        final option = _normalizeOptionText(line);
        if (option != null) options.add(option);
      }
    }

    return options.toSet().toList();
  }

  String? _extractOptionText(dynamic raw) {
    final decoded = _decodeStructuredValue(raw);
    if (decoded is Map) {
      return _firstNonEmptyString([
        decoded['text'],
        decoded['option'],
        decoded['label'],
        decoded['value'],
        decoded['answer'],
        decoded['content'],
      ]);
    }
    if (decoded == null) return null;
    return _normalizeOptionText(decoded.toString());
  }

  String? _normalizeOptionText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final cleaned = trimmed
        .replaceFirst(RegExp(r'^[A-Za-z][\)\.\:\-]\s*'), '')
        .replaceFirst(RegExp(r'^\d+[\)\.\:\-]\s*'), '')
        .replaceFirst(RegExp(r'^[-*]\s*'), '')
        .trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  String? _firstNonEmptyString(List<dynamic> candidates) {
    for (final candidate in candidates) {
      if (candidate == null) continue;
      final value = candidate.toString().trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  String? _normalizeQuizCorrectValue(String raw, List<String> options) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      debugPrint(
        '_normalizeQuizCorrectValue: AI provided empty correct answer.',
      );
      return null;
    }

    final upper = trimmed.toUpperCase();
    final letterPatterns = [
      RegExp(r'^[A-Z]$'),
      RegExp(r'^(?:OPTION|CHOICE)\s+([A-Z])$'),
      RegExp(r'^([A-Z])[\)\.\:\-]'),
    ];

    for (final pattern in letterPatterns) {
      final match = pattern.firstMatch(upper);
      final label = match?.groupCount == 1 ? match?.group(1) : match?.group(0);
      if (label == null || label.isEmpty) continue;
      final index = label.codeUnitAt(0) - 65;
      if (index >= 0 && index < options.length) {
        return String.fromCharCode(65 + index);
      }
    }

    final numericMatch = RegExp(r'\b(\d+)\b').firstMatch(trimmed);
    final numeric = int.tryParse(numericMatch?.group(1) ?? '');
    if (numeric != null && numeric >= 1 && numeric <= options.length) {
      return String.fromCharCode(64 + numeric);
    }

    final normalizedAnswer = _normalizeOptionText(trimmed)?.toLowerCase();
    if (normalizedAnswer != null) {
      for (var i = 0; i < options.length; i++) {
        if (options[i].trim().toLowerCase() == normalizedAnswer) {
          return String.fromCharCode(65 + i);
        }
      }
    }

    debugPrint(
      '_normalizeQuizCorrectValue: no match found for "$raw", '
      'returning trimmed value "$trimmed" as-is.',
    );
    return trimmed;
  }

  String get _activeType {
    switch (_tabController.index) {
      case 1:
        return 'quiz';
      case 2:
        return 'flashcards';
      case 3:
        return 'chat';
      default:
        return 'summary';
    }
  }

  bool _isNonEmptyOutput(Object? value) {
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return false;
  }

  bool _hasOutput(String type) {
    switch (type) {
      case 'summary':
        return _isNonEmptyOutput(_summary);
      case 'quiz':
        return _isNonEmptyOutput(_quiz);
      case 'flashcards':
        return _isNonEmptyOutput(_flashcards);
      default:
        return false;
    }
  }

  dynamic _serializeTypeData(String type) {
    switch (type) {
      case 'summary':
        return _summary;
      case 'quiz':
        return _quiz?.map((q) => q.toJson()).toList();
      case 'flashcards':
        return _flashcards?.map((c) => c.toJson()).toList();
      default:
        return null;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'quiz':
        return 'Quiz';
      case 'flashcards':
        return 'Cards';
      case 'chat':
        return 'Chat';
      default:
        return 'Summary';
    }
  }

  String _loadingMessageForType(String type) {
    final fallback = switch (type) {
      'summary' => 'Generating summary...',
      'quiz' => 'Building quiz...',
      'flashcards' => 'Creating flashcards...',
      _ => 'Generating content...',
    };

    final stage = (_pendingJobStage ?? '').trim().toLowerCase();
    final stageMessage = switch (stage) {
      'queued' => 'Queued in background...',
      'extraction' => 'Extracting study material...',
      'inventory' => 'Mapping document topics...',
      'generation' => fallback,
      'validation' => 'Validating generated content...',
      'completed' => 'Finalizing output...',
      _ => fallback,
    };

    final progress = _pendingJobProgress;
    final etaLabel = _etaLabel();
    if (progress == null || progress <= 0 || progress >= 100) {
      return etaLabel == null ? stageMessage : '$stageMessage • $etaLabel';
    }
    final progressLabel = '$stageMessage ($progress%)';
    return etaLabel == null ? progressLabel : '$progressLabel • $etaLabel';
  }

  int get _readyOutputCount {
    var count = 0;
    if (_isNonEmptyOutput(_summary)) count++;
    if (_isNonEmptyOutput(_quiz)) count++;
    if (_isNonEmptyOutput(_flashcards)) count++;
    return count;
  }

  Widget _buildHeaderChip({
    required bool isDark,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? Colors.white70 : const Color(0xFF1E293B),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generate(String type, {required bool regenerate}) async {
    if (_isLoading) return;
    final useOcr = _supportsOcr && (_useOcr || _forceOcr);
    final forceOcr = _supportsOcr && _forceOcr;
    setState(() {
      _isLoading = true;
      _loadingType = type;
      _error = null;
    });

    try {
      await _analytics.logEvent(
        'ai_studio_generate',
        parameters: <String, Object?>{
          ..._baseAnalyticsParameters(),
          'content_type': type,
          'regenerate': regenerate,
          'use_ocr': useOcr,
          'force_ocr': forceOcr,
        },
      );

      final clientRequestId = _buildAiClientRequestId(type);
      final response = await _requestBackgroundGeneration(
        type: type,
        regenerate: regenerate,
        useOcr: useOcr,
        forceOcr: forceOcr,
        clientRequestId: clientRequestId,
      );
      final jobId = response['job_id']?.toString().trim() ?? '';
      final status = response['status']?.toString().trim().toLowerCase() ?? '';

      if (jobId.isNotEmpty &&
          (status == 'queued' || status == 'processing' || status.isEmpty)) {
        await _trackPendingJob(
          type: type,
          jobId: jobId,
          runId: response['run_id']?.toString(),
          clientRequestId: clientRequestId,
          restored: false,
        );
        if (mounted) {
          final progressRaw = response['progress'];
          final elapsedMs = _readJobDurationMs(
            response,
            'elapsed_ms',
            'elapsedMs',
          );
          final estimatedTotalMs = _readJobDurationMs(
            response,
            'estimated_total_ms',
            'estimatedTotalMs',
          );
          final estimatedRemainingMs = _readJobDurationMs(
            response,
            'estimated_remaining_ms',
            'estimatedRemainingMs',
          );
          setState(() {
            _pendingJobStage =
                response['stage']?.toString().trim().isNotEmpty == true
                ? response['stage'].toString().trim()
                : _pendingJobStage;
            _pendingJobStatusReason =
                response['status_reason']?.toString().trim().isNotEmpty == true
                ? response['status_reason'].toString().trim()
                : _pendingJobStatusReason;
            _pendingJobProgress = progressRaw is num
                ? progressRaw.toInt()
                : _pendingJobProgress;
            _pendingJobElapsedMs = elapsedMs ?? _pendingJobElapsedMs;
            _pendingJobEstimatedTotalMs =
                estimatedTotalMs ?? _pendingJobEstimatedTotalMs;
            _pendingJobEstimatedRemainingMs =
                estimatedRemainingMs ?? _pendingJobEstimatedRemainingMs;
          });
        }

        final finished = await _pollPendingJob(force: true);
        if (!finished) {
          _ensurePendingJobPolling();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${_labelForType(type)} is generating in the background. '
                  'You can leave this screen and come back later.',
                ),
              ),
            );
          }
          await _analytics.logEvent(
            'ai_studio_generate_queued',
            parameters: <String, Object?>{
              ..._baseAnalyticsParameters(),
              'content_type': type,
              'regenerate': regenerate,
              'use_ocr': useOcr,
              'force_ocr': forceOcr,
            },
          );
        }
        return;
      }

      await _applyGeneratedResponse(
        type,
        response,
        regenerate: regenerate,
        useOcr: useOcr,
        forceOcr: forceOcr,
        persistLocally: false,
      );
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      await _analytics.logEvent(
        'ai_studio_generate_error',
        parameters: <String, Object?>{
          ..._baseAnalyticsParameters(),
          'content_type': type,
          'regenerate': regenerate,
          'use_ocr': useOcr,
          'force_ocr': forceOcr,
          'reason': _classifyGenerationError(message),
        },
      );
      setState(() {
        _error = _presentGenerationError(message);
        _isLoading = false;
        _loadingType = null;
      });
    }
  }

  /// Generate a question paper from the current resource plus any user-selected
  /// extra PDFs. Uses the /api/ai/multi-quiz endpoint.
  Future<void> _generateMultiQuiz() async {
    if (_isMultiQuizLoading) return;
    final allIds = [
      widget.resourceId,
      ..._extraPdfIds,
    ].map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList();
    if (allIds.isEmpty) return;

    setState(() {
      _isMultiQuizLoading = true;
      _multiQuizError = null;
    });

    final useOcr = _supportsOcr && (_useOcr || _forceOcr);
    final forceOcr = _supportsOcr && _forceOcr;

    try {
      await _analytics.logEvent(
        'ai_studio_generate_start',
        parameters: <String, Object?>{
          ..._baseAnalyticsParameters(),
          'content_type': 'multi_quiz',
          'regenerate': false,
          'use_ocr': useOcr,
          'force_ocr': forceOcr,
          'pdfs_count': allIds.length,
        },
      );

      final response = await _api.getAiMultiQuiz(
        fileIds: allIds,
        useOcr: useOcr,
        forceOcr: forceOcr,
      );
      final parsed = _parseQuizPayload(response);
      if (parsed.isEmpty) {
        throw Exception(
          'Could not create valid questions from the selected PDFs. '
          'Please try different resources.',
        );
      }

      await _analytics.logEvent(
        'ai_studio_generate_success',
        parameters: <String, Object?>{
          ..._baseAnalyticsParameters(),
          'content_type': 'multi_quiz',
          'regenerate': false,
          'use_ocr': useOcr,
          'force_ocr': forceOcr,
          'cached': response['cached'] == true,
          'output_size': parsed.length,
          'pdfs_count': allIds.length,
        },
      );

      _supabaseService.markAiTokenBalanceStale();

      if (mounted) {
        setState(() {
          _quiz = parsed;
          _selectedAnswers.clear();
          _showAnswers = false;
          _cachedMap['quiz'] = false;
          _savedLocallyMap['quiz'] = false;
          _tabController.animateTo(1);
        });
      }
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');

      await _analytics.logEvent(
        'ai_studio_generate_error',
        parameters: <String, Object?>{
          ..._baseAnalyticsParameters(),
          'content_type': 'multi_quiz',
          'regenerate': false,
          'use_ocr': useOcr,
          'force_ocr': forceOcr,
          'reason': _classifyGenerationError(message),
          'pdfs_count': allIds.length,
        },
      );

      if (mounted) {
        setState(() {
          _multiQuizError = _presentGenerationError(message);
        });
      }
    } finally {
      if (mounted) setState(() => _isMultiQuizLoading = false);
    }
  }

  Future<void> _showMultiPdfPicker(bool isDark) async {
    final collegeId = widget.collegeId;
    if (collegeId == null || collegeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('College scope required for multi-PDF quiz.'),
        ),
      );
      return;
    }
    // Fetch up to 30 recently approved PDFs from this college.
    List<Map<String, dynamic>> candidates = [];
    try {
      final payload = await _api.listResources(
        collegeId: collegeId,
        type: 'notes',
        limit: 30,
      );
      final raw = payload['resources'] ?? payload['data'] ?? <dynamic>[];
      if (raw is List) {
        candidates = raw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((m) {
              final id = m['id']?.toString().trim() ?? '';
              return id.isNotEmpty && id != widget.resourceId;
            })
            .toList();
      }
    } catch (e) {
      debugPrint('[MultiPDF] Failed to fetch candidates: $e');
    }

    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other PDFs found in your college.')),
      );
      return;
    }

    // Show a bottom sheet with a checkbox list.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final selected = Set<String>.from(_extraPdfIds);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (_, scrollCtrl) => Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Add PDFs to Question Paper',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        Text(
                          '${selected.length}/4 selected',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: candidates.length,
                      itemBuilder: (_, i) {
                        final item = candidates[i];
                        final id = item['id']?.toString() ?? '';
                        final title = item['title']?.toString() ?? 'Untitled';
                        final isSelected = selected.contains(id);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (val) {
                            if (val == true && selected.length >= 4) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Maximum 4 extra PDFs allowed.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setModalState(() {
                              if (val == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                          title: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppTheme.primary,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _extraPdfIds
                              ..clear()
                              ..addAll(selected);
                          });
                          Navigator.of(ctx).pop();
                          _generateMultiQuiz();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Generate Question Paper (${selected.length + 1} PDF${selected.isEmpty ? '' : 's'})',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
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
      },
    );
  }

  bool _looksLikeTokenLimitError(String message, {String? errorCode}) {
    // Prefer a structured error code from the backend when available.
    if (errorCode != null) {
      final code = errorCode.toUpperCase();
      if (code == 'TOKEN_LIMIT_EXCEEDED' ||
          code == 'INSUFFICIENT_TOKENS' ||
          code == 'QUOTA_EXCEEDED') {
        return true;
      }
    }
    // Fallback: heuristic string matching.
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

  Future<void> _openAiTokenPaywall() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PaywallDialog(
        onSuccess: () {
          if (!mounted) return;
          setState(() {
            _error = null;
            _multiQuizError = null;
          });
        },
      ),
    );
  }

  Widget _buildGenerationErrorBanner(
    String message, {
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(12, 4, 12, 0),
  }) {
    final isTokenError = _looksLikeTokenLimitError(message);
    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_rounded, color: AppTheme.error, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.error),
              ),
            ),
            if (isTokenError) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: _openAiTokenPaywall,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.45),
                ),
                child: Text(
                  'Recharge AI Tokens',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<bool> _ensurePremiumForPdfExport() async {
    final isPremium = await _subscriptionService.isPremium();
    if (isPremium) return true;
    if (!mounted) return false;

    await showDialog<void>(
      context: context,
      builder: (_) => PaywallDialog(
        onSuccess: () {
          if (!mounted) return;
          setState(() => _error = null);
        },
      ),
    );
    return false;
  }

  Future<void> _saveActiveOutput() async {
    final type = _activeType;
    final payload = _serializeTypeData(type);
    if (!_hasOutput(type) || payload == null) return;

    setState(() => _isSaving = true);
    try {
      await widget.localStore.saveOutput(
        resourceId: widget.resourceId,
        type: type,
        data: payload,
      );
      if (!mounted) return;

      setState(() {
        _savedLocallyMap[type] = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved on this device')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save output: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _downloadSummaryPdf() async {
    final summary = _summary;
    if (summary == null || summary.trim().isEmpty) return;
    if (!await _ensurePremiumForPdfExport()) return;

    setState(() => _isDownloadingSummary = true);
    try {
      final file = await widget.summaryPdfService.saveSummaryPdf(
        title: widget.resourceTitle,
        summary: summary,
        subtitle: 'AI Study Summary',
        watermarkText: 'StudyShare',
      );
      if (!mounted) return;
      final box =
          _pdfButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final sharePositionOrigin = (box != null && box.hasSize)
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Generative AI Summary for ${widget.resourceTitle}',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to export PDF: $e')));
    } finally {
      if (mounted) setState(() => _isDownloadingSummary = false);
    }
  }

  Future<void> _downloadFlashcardsPdf() async {
    final cards = _flashcards;
    if (cards == null || cards.isEmpty) return;
    if (!await _ensurePremiumForPdfExport()) return;

    setState(() => _isDownloadingFlashcards = true);
    try {
      final file = await widget.summaryPdfService.saveFlashcardsPdf(
        title: widget.resourceTitle,
        flashcards: cards
            .map(
              (card) =>
                  FlashcardPdfEntry(term: card.front, definition: card.back),
            )
            .toList(growable: false),
        subtitle: 'AI Flashcards',
        watermarkText: 'StudyShare Cards',
      );
      if (!mounted) return;
      final box =
          _pdfButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final sharePositionOrigin = (box != null && box.hasSize)
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'StudyShare flashcards PDF',
          subject: 'StudyShare Flashcards',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to export PDF: $e')));
    } finally {
      if (mounted) setState(() => _isDownloadingFlashcards = false);
    }
  }

  int _resolveQuizAnswerIndex(QuizQuestion question) {
    final options = question.options;
    if (options.isEmpty) return 0;

    final raw = question.correct.trim();
    if (raw.isEmpty) return 0;

    final letterMatch = RegExp(r'^[A-Za-z]$').firstMatch(raw);
    if (letterMatch != null) {
      final index = raw.toUpperCase().codeUnitAt(0) - 65;
      if (index >= 0 && index < options.length) return index;
    }

    final numeric = int.tryParse(raw);
    if (numeric != null && numeric >= 1 && numeric <= options.length) {
      return numeric - 1;
    }

    final normalized = raw.toLowerCase();
    for (var i = 0; i < options.length; i++) {
      if (options[i].trim().toLowerCase() == normalized) {
        return i;
      }
    }

    return 0;
  }

  AiQuestionPaper? _buildQuestionPaperFromStudioQuiz() {
    final quiz = _quiz;
    if (quiz == null || quiz.isEmpty) return null;

    final questions = <AiQuestionPaperQuestion>[];
    for (final item in quiz) {
      final text = item.question.trim();
      final options = item.options
          .map((option) => option.trim())
          .where((option) => option.isNotEmpty)
          .toList();
      if (text.isEmpty || options.length < 2) {
        continue;
      }

      questions.add(
        AiQuestionPaperQuestion(
          question: text,
          options: options,
          correctIndex: _resolveQuizAnswerIndex(
            item,
          ).clamp(0, options.length - 1),
          explanation: '',
          source: AiQuestionPaperSource(
            title: widget.resourceTitle,
            section: 'AI Studio Quiz',
            pages: '',
            note: 'Generated from selected resource',
          ),
        ),
      );
    }

    if (questions.isEmpty) return null;

    final subject = (widget.subject ?? '').trim();
    final semester = (widget.semester ?? '').trim();
    final branch = (widget.branch ?? '').trim();
    final resolvedSubject = subject.isEmpty ? 'General' : subject;

    return AiQuestionPaper(
      title: '$resolvedSubject Quiz',
      subject: resolvedSubject,
      semester: semester,
      branch: branch,
      instructions: const [
        'Answer all questions.',
        'Choose the best option for each question.',
        'Each question carries equal marks.',
      ],
      questions: questions,
      generatedAt: DateTime.now(),
      pyqCount: 1, // Default: studio quiz payload does not provide PYQ count.
    );
  }

  Future<void> _startStudioQuiz() async {
    final paper = _buildQuestionPaperFromStudioQuiz();
    if (paper == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid quiz questions available yet.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiQuestionPaperQuizScreen(paper: paper),
      ),
    );
  }

  Widget _buildStartQuizCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E1E37) : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF29456C) : const Color(0xFFC6DBFF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attempt Full Quiz',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Start quiz mode with submit and score screen.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _startStudioQuiz,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Start Quiz'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _studioBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsPanel(bool isDark) {
    if (!_supportsOcr) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () => _showExtractionSettingsSheet(isDark),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.tune_rounded,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _useOcr ? 'OCR on' : 'OCR off',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            Icon(
              Icons.settings_rounded,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExtractionSettingsSheet(bool isDark) async {
    if (!_supportsOcr) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF121A2B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Extraction Settings',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _useOcr,
                      onChanged: (val) {
                        setState(() {
                          _useOcr = val;
                          if (!val) _forceOcr = false;
                        });
                        setSheetState(() {});
                      },
                      activeThumbColor: _studioBlue,
                      activeTrackColor: _studioBlue.withValues(alpha: 0.35),
                      title: Text(
                        'Use OCR',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      subtitle: Text(
                        'Enable OCR fallback for scanned/low-text pages.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: _studioBlue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'OCR is automatic',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'AI Studio chooses the OCR path automatically when this toggle is enabled.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStudioHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF0D1728).withValues(alpha: 0.92)
              : const Color(0xFFF4F8FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFD8E5FF),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: AiLogo(size: 18, animate: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AI Studio',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    widget.resourceTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
            _buildHeaderChip(
              isDark: isDark,
              icon: Icons.checklist_rounded,
              label: '$_readyOutputCount/3',
            ),
            IconButton(
              onPressed: () => setState(() => _isFullscreen = !_isFullscreen),
              icon: Icon(
                _isFullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                size: 19,
              ),
              color: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
              visualDensity: VisualDensity.compact,
              tooltip: _isFullscreen ? 'Exit full screen' : 'Full screen',
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 19),
              color: isDark ? Colors.white70 : const Color(0xFF1E293B),
              visualDensity: VisualDensity.compact,
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactActionBar({
    required bool isDark,
    required bool hasOutput,
    required bool isSavedLocally,
    required String activeLabel,
  }) {
    final showPdfAction =
        hasOutput && (_activeType == 'summary' || _activeType == 'flashcards');
    final isDownloadingPdf = _activeType == 'flashcards'
        ? _isDownloadingFlashcards
        : _isDownloadingSummary;
    final downloadPdf = _activeType == 'flashcards'
        ? _downloadFlashcardsPdf
        : _downloadSummaryPdf;
    final chips = <Widget>[];
    if (_activeType != 'chat') {
      if (_cachedMap[_activeType] == true) {
        chips.add(_buildStatusChip('Server cache'));
      }
      if (isSavedLocally) {
        chips.add(_buildStatusChip('Saved on device'));
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chips.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 4, children: chips),
            if (chips.isNotEmpty) const SizedBox(height: 6),
            if (_activeType != 'chat')
              Row(
                children: [
                  if (hasOutput && !isSavedLocally)
                    _buildActionIconButton(
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      tooltip: 'Save',
                      onPressed: _isSaving ? null : _saveActiveOutput,
                    ),
                  if (hasOutput && !isSavedLocally) const SizedBox(width: 6),
                  if (hasOutput && _activeType == 'quiz') ...[
                    _buildActionIconButton(
                      icon: Icon(
                        _showAnswers
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      tooltip: _showAnswers ? 'Hide answers' : 'Show answers',
                      onPressed: () {
                        setState(() => _showAnswers = !_showAnswers);
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (showPdfAction) ...[
                    _buildActionIconButton(
                      buttonKey: _pdfButtonKey,
                      icon: isDownloadingPdf
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      tooltip: 'Download PDF',
                      onPressed: isDownloadingPdf ? null : downloadPdf,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _generate(_activeType, regenerate: hasOutput),
                      icon: Icon(
                        hasOutput
                            ? Icons.refresh_rounded
                            : Icons.auto_awesome_rounded,
                        size: 18,
                      ),
                      label: Text(
                        hasOutput
                            ? 'Regenerate $activeLabel'
                            : 'Generate $activeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _studioBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIconButton({
    Key? buttonKey,
    required Widget icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        key: buttonKey,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(38, 38),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: icon,
      ),
    );
  }

  Widget _buildStatusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  String _summaryPlain(String input) {
    // Strip markdown emphasis markers (_..._) while preserving underscores
    // inside identifiers (e.g., snake_case).
    return input
        .replaceAll('**', '')
        .replaceAll(RegExp(r'(?<=\s|^)_([^_]+)_(?=\s|$)'), r'$1')
        .trim();
  }

  Widget _buildLoadingArcade({required String loadingMessage}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final minHeight = constraints.maxHeight.isFinite
            ? math.max(0.0, constraints.maxHeight - 36).toDouble()
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: SizedBox(
                width: math.min(maxWidth - 32, 540).toDouble(),
                child: AiLoadingGameCard(
                  compact: true,
                  loadingMessage: loadingMessage,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryTab(bool isDark) {
    if (_isLoading && _loadingType == 'summary') {
      return _buildLoadingArcade(
        loadingMessage: _loadingMessageForType('summary'),
      );
    }

    if (_summary == null || _summary!.trim().isEmpty) {
      return _buildEmptyState(
        isDark: isDark,
        icon: Icons.summarize_rounded,
        title: 'No summary yet',
        subtitle: 'Generate or load a saved summary for this PDF.',
      );
    }

    final blocks = _parseSummary(_summary!);
    final headingIndexes = <int>[
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].kind == _SummaryBlockKind.heading) i,
    ];
    final firstHeadingIndex = headingIndexes.isEmpty
        ? -1
        : headingIndexes.first;

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          itemCount: blocks.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final block = blocks[index];
            switch (block.kind) {
              case _SummaryBlockKind.heading:
                final isMainHeading = index == firstHeadingIndex;
                final headingText = _summaryPlain(block.text);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headingText,
                      style: GoogleFonts.inter(
                        fontSize: isMainHeading ? 22 : 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: isMainHeading ? -0.4 : -0.2,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: isMainHeading ? 3 : 2,
                      width: isMainHeading ? 110 : 90,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                );
              case _SummaryBlockKind.bullet:
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8, right: 10),
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: AiFormattedText(
                        text: block.text,
                        baseStyle: GoogleFonts.inter(
                          fontSize: 14.5,
                          height: 1.55,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF334155),
                        ),
                        bulletColor: AppTheme.primary,
                        headingColor: isDark
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                );
              case _SummaryBlockKind.paragraph:
                return AiFormattedText(
                  text: block.text,
                  baseStyle: GoogleFonts.inter(
                    fontSize: 14.5,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                  bulletColor: AppTheme.primary,
                  headingColor: isDark ? Colors.white : const Color(0xFF0F172A),
                );
            }
          },
        ),
        Positioned(
          right: 18,
          bottom: 14,
          child: IgnorePointer(
            child: Opacity(
              opacity: isDark ? 0.07 : 0.09,
              child: Text(
                'studyshare',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuizTab(bool isDark) {
    if (_isLoading && _loadingType == 'quiz') {
      return _buildLoadingArcade(
        loadingMessage: _loadingMessageForType('quiz'),
      );
    }

    if (_quiz == null || _quiz!.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          children: [
            _buildEmptyState(
              isDark: isDark,
              icon: Icons.quiz_outlined,
              title: 'No quiz yet',
              subtitle: 'Generate MCQs for revision practice.',
            ),
            const SizedBox(height: 12),
            // Multi-PDF question paper CTA
            if (_isMultiQuizLoading)
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.sizeOf(context).width;
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: math.min(maxWidth - 32, 540).toDouble(),
                        child: AiLoadingGameCard(
                          compact: true,
                          loadingMessage:
                              'Building multi-PDF question paper...',
                          headline:
                              'Beat the high score before the paper lands',
                          subheadline:
                              'Fast arcade rounds keep the wait from feeling idle.',
                        ),
                      ),
                    ),
                  );
                },
              )
            else
              InkWell(
                onTap: () => _showMultiPdfPicker(isDark),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0A1628)
                        : const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF1E3A5F)
                          : const Color(0xFFBDD7FF),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.file_copy_outlined,
                          color: AppTheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Multi-PDF Question Paper',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Combine up to 5 PDFs for a comprehensive exam prep paper.',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: isDark
                                    ? Colors.white60
                                    : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark
                            ? Colors.white38
                            : const Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ),
            if (_multiQuizError != null)
              _buildGenerationErrorBanner(
                _multiQuizError!,
                padding: const EdgeInsets.only(top: 10),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: _quiz!.length + 1,
      itemBuilder: (context, idx) {
        if (idx == 0) {
          return _buildStartQuizCard(isDark);
        }

        final q = _quiz![idx - 1];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111A2A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF24324A) : const Color(0xFFD7E5FF),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: _studioBlue.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Q$idx',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      q.question,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...q.options.asMap().entries.map((entry) {
                final label = String.fromCharCode(65 + entry.key);
                final opt = entry.value;
                final selected = _selectedAnswers[idx] == label;
                final correct = _resolveQuizAnswerIndex(q) == entry.key;
                final reveal = _showAnswers || selected;
                final isCorrect = reveal && correct;
                final isWrong = selected && !correct && reveal;

                final borderColor = isCorrect
                    ? AppTheme.success
                    : isWrong
                    ? AppTheme.error
                    : (isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0));
                final fillColor = isCorrect
                    ? AppTheme.success.withValues(alpha: 0.16)
                    : isWrong
                    ? AppTheme.error.withValues(alpha: 0.16)
                    : (isDark
                          ? const Color(0xFF1A263B)
                          : const Color(0xFFF3F8FF));

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedAnswers[idx] = label;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? Colors.black26 : Colors.white,
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isCorrect
                                    ? AppTheme.success
                                    : isWrong
                                    ? AppTheme.error
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              opt,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: isCorrect
                                    ? AppTheme.success
                                    : isWrong
                                    ? AppTheme.error
                                    : (isDark
                                          ? Colors.white70
                                          : const Color(0xFF334155)),
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isCorrect)
                            const Icon(
                              Icons.check_circle,
                              size: 18,
                              color: AppTheme.success,
                            ),
                          if (isWrong)
                            const Icon(
                              Icons.cancel,
                              size: 18,
                              color: AppTheme.error,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFlashcardsTab(bool isDark) {
    if (_isLoading && _loadingType == 'flashcards') {
      return _buildLoadingArcade(
        loadingMessage: _loadingMessageForType('flashcards'),
      );
    }

    if (_flashcards == null || _flashcards!.isEmpty) {
      return _buildEmptyState(
        isDark: isDark,
        icon: Icons.style_outlined,
        title: 'No flashcards yet',
        subtitle: 'Generate cards for quick active recall.',
      );
    }

    final cards = _flashcards!;
    final currentIndex = _activeFlashcardIndex
        .clamp(0, cards.length - 1)
        .toInt();

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _flashcardPageController,
            physics: const BouncingScrollPhysics(),
            itemCount: cards.length,
            onPageChanged: (idx) {
              if (!mounted) return;
              setState(() => _activeFlashcardIndex = idx);
            },
            itemBuilder: (context, idx) {
              final card = cards[idx];
              final flipped = _flippedCardIndexes.contains(idx);

              return AnimatedBuilder(
                animation: _flashcardPageController,
                builder: (context, child) {
                  final page = _flashcardPageController.hasClients
                      ? (_flashcardPageController.page ??
                            _flashcardPageController.initialPage.toDouble())
                      : _flashcardPageController.initialPage.toDouble();
                  final delta = (idx - page).clamp(-1.2, 1.2).toDouble();
                  final scale = (1 - (delta.abs() * 0.08)).clamp(0.86, 1.0);
                  final rotateY = delta * 0.25;
                  final translateY = delta.abs() * 16;

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..translateByDouble(0.0, translateY, 0.0, 1.0)
                      ..rotateY(rotateY)
                      ..scaleByDouble(scale, scale, 1.0, 1.0),
                    child: child,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (flipped) {
                          _flippedCardIndexes.remove(idx);
                        } else {
                          _flippedCardIndexes.add(idx);
                        }
                      });
                    },
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: flipped ? 1.0 : 0.0),
                      duration: const Duration(milliseconds: 440),
                      curve: Curves.easeInOutCubic,
                      builder: (context, value, _) {
                        final progress = value.clamp(0.0, 1.0);
                        final isBackFace = progress >= 0.5;
                        final rotation = progress * math.pi;

                        final frontStart = const Color(0xFF60A5FA);
                        final frontEnd = _studioBlueDark;
                        final backStart = const Color(0xFFF97316);
                        final backEnd = const Color(0xFF7C3AED);
                        final faceBlend =
                            (progress < 0.5
                                    ? progress * 2
                                    : (progress - 0.5) * 2)
                                .clamp(0.0, 1.0);
                        final fromStart = isBackFace ? frontStart : backStart;
                        final toStart = isBackFace ? backStart : frontStart;
                        final fromEnd = isBackFace ? frontEnd : backEnd;
                        final toEnd = isBackFace ? backEnd : frontEnd;
                        final fromGlow = isBackFace ? _studioBlueDark : backEnd;
                        final toGlow = isBackFace ? backEnd : _studioBlueDark;

                        final gradientStart =
                            Color.lerp(fromStart, toStart, faceBlend) ??
                            toStart;
                        final gradientEnd =
                            Color.lerp(fromEnd, toEnd, faceBlend) ?? toEnd;
                        final glowColor =
                            Color.lerp(fromGlow, toGlow, faceBlend) ?? toGlow;

                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012)
                            ..rotateY(rotation),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: LinearGradient(
                                colors: [gradientStart, gradientEnd],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: glowColor.withValues(alpha: 0.30),
                                  blurRadius: 26,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 14),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..rotateY(isBackFace ? math.pi : 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              (isBackFace
                                                      ? const Color(0xFF2E1065)
                                                      : Colors.white)
                                                  .withValues(alpha: 0.22),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Text(
                                          'Card ${idx + 1}',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Transform.rotate(
                                        angle: progress * math.pi,
                                        child: Icon(
                                          Icons.flip_rounded,
                                          size: 20,
                                          color: Colors.white.withValues(
                                            alpha: 0.92,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    isBackFace ? 'Answer' : 'Question',
                                    key: ValueKey<String>(
                                      'flashcard_face_${idx}_$isBackFace',
                                    ),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(
                                        alpha: 0.92,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Center(
                                      child: SingleChildScrollView(
                                        child: AiFormattedText(
                                          key: ValueKey<String>(
                                            'flashcard_text_${idx}_'
                                            '${isBackFace ? 'back' : 'front'}',
                                          ),
                                          text: isBackFace
                                              ? card.back
                                              : card.front,
                                          baseStyle: GoogleFonts.inter(
                                            fontSize: 17,
                                            height: 1.45,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                          bulletColor: Colors.white,
                                          headingColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap to flip | Swipe for next card',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: currentIndex <= 0
                    ? null
                    : () => _animateToFlashcardIndex(currentIndex - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const Spacer(),
              Text(
                '${currentIndex + 1} / ${cards.length}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                ),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: currentIndex >= cards.length - 1
                    ? null
                    : () => _animateToFlashcardIndex(currentIndex + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatTab(bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: _studioBlue.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _studioBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: _studioBlue,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Study Chat',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask questions, clarify doubts, and interact with an AI tutor trained specifically on this document.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final trimmedResourceId = widget.resourceId.trim();
                  final trimmedVideoUrl = widget.videoUrl?.trim() ?? '';
                  if (trimmedResourceId.isEmpty && trimmedVideoUrl.isEmpty) {
                    return;
                  }
                  final ctx = ResourceContext(
                    fileId: trimmedResourceId.isEmpty
                        ? null
                        : trimmedResourceId,
                    title: widget.resourceTitle,
                    subject: widget.subject,
                    semester: widget.semester,
                    branch: widget.branch,
                    videoUrl: trimmedVideoUrl.isEmpty ? null : trimmedVideoUrl,
                  );
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(
                    MaterialPageRoute(
                      builder: (_) => AIChatScreen(
                        collegeId: widget.collegeId ?? '',
                        collegeName: widget.collegeName ?? '',
                        resourceContext: ctx,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.rocket_launch_rounded),
                label: const Text('Start Chatting'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _studioBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111A2A) : const Color(0xFFF3F8FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF24324A) : const Color(0xFFD7E5FF),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppTheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_SummaryBlock> _parseSummary(String rawSummary) {
    final lines = rawSummary.replaceAll('\r', '').split('\n');
    final blocks = <_SummaryBlock>[];

    for (final rawLine in lines) {
      final trimmedRaw = rawLine.trim();
      if (trimmedRaw.isEmpty) continue;

      final isBullet = RegExp(r'^([-*•]|\d+[.)])\s+').hasMatch(trimmedRaw);

      var line = trimmedRaw
          .replaceFirst(RegExp(r'^#+\s*'), '')
          .replaceFirst(RegExp(r'^([-*•]|\d+[.)])\s*'), '');
      final plain = line.replaceAll(RegExp(r'[:\-\s]+$'), '').trim();
      final plainForDetection = plain.replaceAll('**', '');
      final words = plain
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      final looksLikeHeading =
          trimmedRaw.startsWith('#') ||
          (!isBullet && trimmedRaw.endsWith(':')) ||
          (!isBullet &&
              words <= 7 &&
              RegExp(r'^[A-Z]').hasMatch(plainForDetection));

      if (looksLikeHeading) {
        blocks.add(_SummaryBlock(kind: _SummaryBlockKind.heading, text: plain));
      } else if (isBullet) {
        blocks.add(_SummaryBlock(kind: _SummaryBlockKind.bullet, text: line));
      } else {
        blocks.add(
          _SummaryBlock(kind: _SummaryBlockKind.paragraph, text: line),
        );
      }
    }

    if (blocks.isEmpty) {
      final fallback = rawSummary
          .replaceAll(RegExp(r'^[*-]\s*', multiLine: true), '')
          .replaceAll('**', '')
          .trim();
      if (fallback.isNotEmpty) {
        blocks.add(
          _SummaryBlock(kind: _SummaryBlockKind.paragraph, text: fallback),
        );
      }
    }

    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasOutput = _hasOutput(_activeType);
    final isSavedLocally = _savedLocallyMap[_activeType] == true;
    final activeLabel = _labelForType(_activeType);

    final sheetContent = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      height: _isFullscreen
          ? MediaQuery.of(context).size.height
          : MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF0A1120).withValues(alpha: 0.85),
                  const Color(0xFF040810).withValues(alpha: 0.95),
                ]
              : [
                  const Color(0xFFFFFFFF).withValues(alpha: 0.9),
                  const Color(0xFFF0F5FF).withValues(alpha: 0.95),
                ],
        ),
        borderRadius: _isFullscreen
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        children: [
          if (_isFullscreen)
            SizedBox(height: MediaQuery.of(context).padding.top),
          const SizedBox(height: 8),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white24
                  : _studioBlue.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildStudioHeader(isDark),
          if (_error != null) _buildGenerationErrorBanner(_error!),
          _buildControlsPanel(isDark),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF111A2A)
                    : const Color(0xFFF2F7FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF24324A)
                      : const Color(0xFFD5E4FF),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelPadding: EdgeInsets.zero,
                labelColor: isDark ? Colors.white : _studioBlueDark,
                unselectedLabelColor: isDark
                    ? Colors.white70
                    : const Color(0xFF5B6D8D),
                indicator: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color(0xFFE6F0FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.18)
                        : _studioBlue.withValues(alpha: 0.28),
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(3),
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
                unselectedLabelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.summarize_rounded, size: 15),
                    iconMargin: EdgeInsets.only(bottom: 2),
                    text: 'Summary',
                  ),
                  Tab(
                    icon: Icon(Icons.quiz_rounded, size: 15),
                    iconMargin: EdgeInsets.only(bottom: 2),
                    text: 'Quiz',
                  ),
                  Tab(
                    icon: Icon(Icons.style_rounded, size: 15),
                    iconMargin: EdgeInsets.only(bottom: 2),
                    text: 'Cards',
                  ),
                  Tab(
                    icon: Icon(Icons.chat_bubble_rounded, size: 15),
                    iconMargin: EdgeInsets.only(bottom: 2),
                    text: 'Chat',
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(isDark),
                _buildQuizTab(isDark),
                _buildFlashcardsTab(isDark),
                _buildChatTab(isDark),
              ],
            ),
          ),
          _buildCompactActionBar(
            isDark: isDark,
            hasOutput: hasOutput,
            isSavedLocally: isSavedLocally,
            activeLabel: activeLabel,
          ),
        ],
      ),
    );

    return sheetContent;
  }
}

enum _SummaryBlockKind { heading, bullet, paragraph }

class _SummaryBlock {
  final _SummaryBlockKind kind;
  final String text;

  _SummaryBlock({required this.kind, required this.text});
}
