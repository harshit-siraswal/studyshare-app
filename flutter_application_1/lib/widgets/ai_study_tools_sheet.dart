import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../config/theme.dart';
import '../models/ai_question_paper.dart';
import '../screens/ai_chat_screen.dart';
import '../screens/ai_question_paper_quiz_screen.dart';
import '../services/ai_output_local_service.dart';
import '../services/backend_api_service.dart';
import '../services/summary_pdf_service.dart';
import '../services/supabase_service.dart';
import 'branded_loader.dart';

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
    with SingleTickerProviderStateMixin {
  final BackendApiService _api = BackendApiService();
  final SupabaseService _supabaseService = SupabaseService();
  static const Color _studioBlue = Color(0xFF2563EB);
  static const Color _studioBlueDark = Color(0xFF1D4ED8);

  late TabController _tabController;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDownloadingSummary = false;
  final GlobalKey _pdfButtonKey = GlobalKey();
  String? _loadingType;
  String? _error;

  String? _summary;
  List<QuizQuestion>? _quiz;
  List<Flashcard>? _flashcards;

  bool _useOcr = true;
  bool _forceOcr = false;
  String _ocrProvider = 'google_vision';
  bool _showAnswers = false;
  final Map<int, String> _selectedAnswers = {};
  final Set<int> _flippedCardIndexes = <int>{};
  late final PageController _flashcardPageController;
  int _activeFlashcardIndex = 0;

  final Map<String, bool> _cachedMap = {};
  final Map<String, bool> _savedLocallyMap = {};

  bool _isFullscreen = false;

  bool get _supportsOcr => widget.resourceType != 'video';

  String _ocrProviderLabelFor(String provider) {
    switch (provider) {
      case 'google_vision':
        return 'Google Vision';
      case 'sarvam':
        return 'Sarvam';
      default:
        return 'Google Vision';
    }
  }

  @override
  void initState() {
    super.initState();
    _flashcardPageController = PageController(viewportFraction: 0.9);
    final safeInitialIndex = widget.initialTabIndex.clamp(0, 3).toInt();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: safeInitialIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (mounted) setState(() {});
    });
    _loadSavedOutputs().then((_) {
      if (!mounted) return;
      _handleInitialAutoGeneration();
    });
  }

  @override
  void dispose() {
    _flashcardPageController.dispose();
    _tabController.dispose();
    super.dispose();
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

  List<QuizQuestion>? _parseSavedQuiz(dynamic raw) {
    if (raw is! List) return null;
    final parsed = raw
        .whereType<Map>()
        .map((item) => QuizQuestion.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return parsed;
  }

  List<Flashcard>? _parseSavedFlashcards(dynamic raw) {
    if (raw is! List) return null;
    final parsed = raw
        .whereType<Map>()
        .map((item) => Flashcard.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return parsed;
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
    setState(() {
      _isLoading = true;
      _loadingType = type;
      _error = null;
    });

    try {
      final useOcr = _supportsOcr && (_useOcr || _forceOcr);
      final forceOcr = _supportsOcr && _forceOcr;

      Map<String, dynamic> response;
      if (type == 'summary') {
        response = await _api.getAiSummary(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          ocrProvider: _ocrProvider,
          force: regenerate,
          includeSource: false,
          videoUrl: widget.videoUrl,
        );
        final data = response['data'];
        setState(() {
          _summary = data is String ? data : data?.toString();
          _cachedMap['summary'] = response['cached'] == true;
          _savedLocallyMap['summary'] = false;
        });
      } else if (type == 'quiz') {
        response = await _api.getAiQuiz(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          ocrProvider: _ocrProvider,
          force: regenerate,
          includeSource: false,
          videoUrl: widget.videoUrl,
        );
        final raw = (response['data'] as List?) ?? const [];
        final parsed = raw
            .whereType<Map>()
            .map((q) => QuizQuestion.fromJson(Map<String, dynamic>.from(q)))
            .toList();

        setState(() {
          _quiz = parsed;
          _selectedAnswers.clear();
          _showAnswers = false;
          _cachedMap['quiz'] = response['cached'] == true;
          _savedLocallyMap['quiz'] = false;
        });
      } else {
        response = await _api.getAiFlashcards(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          ocrProvider: _ocrProvider,
          force: regenerate,
          includeSource: false,
          videoUrl: widget.videoUrl,
        );
        final raw = (response['data'] as List?) ?? const [];
        final parsed = raw
            .whereType<Map>()
            .map((c) => Flashcard.fromJson(Map<String, dynamic>.from(c)))
            .toList();

        setState(() {
          _flashcards = parsed;
          _flippedCardIndexes.clear();
          _activeFlashcardIndex = 0;
          _cachedMap['flashcards'] = response['cached'] == true;
          _savedLocallyMap['flashcards'] = false;
        });
        _resetFlashcardDeckToStart();
      }
      _supabaseService.markAiTokenBalanceStale();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingType = null;
        });
      }
    }
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
                _useOcr
                    ? 'OCR on • ${_ocrProviderLabelFor(_ocrProvider)}'
                    : 'OCR off',
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
                    Text(
                      'Provider',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'google_vision',
                            label: Text('Google'),
                            icon: Icon(Icons.visibility_rounded, size: 16),
                          ),
                          ButtonSegment<String>(
                            value: 'sarvam',
                            label: Text('Sarvam'),
                            icon: Icon(Icons.bolt_rounded, size: 16),
                          ),
                        ],
                        selected: {_ocrProvider},
                        onSelectionChanged: _useOcr
                            ? (next) {
                                if (next.isEmpty) return;
                                setState(() => _ocrProvider = next.first);
                                setSheetState(() {});
                              }
                            : null,
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
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Image.asset(
                  'assets/images/ai_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.auto_awesome_rounded,
                    color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                    size: 15,
                  ),
                ),
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
                  if (hasOutput && _activeType == 'summary') ...[
                    _buildActionIconButton(
                      buttonKey: _pdfButtonKey,
                      icon: _isDownloadingSummary
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      tooltip: 'Download PDF',
                      onPressed: _isDownloadingSummary
                          ? null
                          : _downloadSummaryPdf,
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
    return input.replaceAll('**', '').trim();
  }

  TextSpan _summaryTextSpan({
    required String text,
    required Color color,
    required double fontSize,
    FontWeight baseWeight = FontWeight.w500,
  }) {
    final regex = RegExp(r'(\*\*[^*]+\*\*)');
    final matches = regex.allMatches(text);
    if (matches.isEmpty) {
      return TextSpan(
        text: _summaryPlain(text),
        style: GoogleFonts.inter(
          fontSize: fontSize,
          height: 1.55,
          color: color,
          fontWeight: baseWeight,
        ),
      );
    }

    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in matches) {
      if (match.start > last) {
        spans.add(
          TextSpan(
            text: text.substring(last, match.start),
            style: GoogleFonts.inter(
              fontSize: fontSize,
              height: 1.55,
              color: color,
              fontWeight: baseWeight,
            ),
          ),
        );
      }
      final chunk = match.group(0) ?? '';
      spans.add(
        TextSpan(
          text: _summaryPlain(chunk),
          style: GoogleFonts.inter(
            fontSize: fontSize,
            height: 1.55,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(last),
          style: GoogleFonts.inter(
            fontSize: fontSize,
            height: 1.55,
            color: color,
            fontWeight: baseWeight,
          ),
        ),
      );
    }
    return TextSpan(children: spans);
  }

  Widget _buildSummaryTab(bool isDark) {
    if (_isLoading && _loadingType == 'summary') {
      return const Center(
        child: BrandedLoader(
          compact: true,
          showQuotes: false,
          message: 'Generating summary...',
        ),
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
                      child: SelectableText.rich(
                        _summaryTextSpan(
                          text: block.text,
                          fontSize: 14.5,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                );
              case _SummaryBlockKind.paragraph:
                return SelectableText.rich(
                  _summaryTextSpan(
                    text: block.text,
                    fontSize: 14.5,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
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
      return const Center(
        child: BrandedLoader(
          compact: true,
          showQuotes: false,
          message: 'Building quiz...',
        ),
      );
    }

    if (_quiz == null || _quiz!.isEmpty) {
      return _buildEmptyState(
        isDark: isDark,
        icon: Icons.quiz_outlined,
        title: 'No quiz yet',
        subtitle: 'Generate MCQs for revision practice.',
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
                final correct = q.correct.toUpperCase() == label;
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
      return const Center(
        child: BrandedLoader(
          compact: true,
          showQuotes: false,
          message: 'Creating flashcards...',
        ),
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
                        final backStart = const Color(0xFF0284C7);
                        final backEnd = _studioBlue;

                        final gradientStart =
                            Color.lerp(frontStart, backStart, progress) ??
                            frontStart;
                        final gradientEnd =
                            Color.lerp(frontEnd, backEnd, progress) ?? frontEnd;
                        final glowColor =
                            Color.lerp(
                              _studioBlueDark,
                              _studioBlue,
                              progress,
                            ) ??
                            _studioBlueDark;

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
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
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
                                      child: Text(
                                        isBackFace ? card.back : card.front,
                                        key: ValueKey<String>(
                                          'flashcard_text_${idx}_'
                                          '${isBackFace ? 'back' : 'front'}',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 17,
                                          height: 1.45,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
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
                  if (widget.resourceId.isEmpty) return;
                  final ctx = ResourceContext(
                    fileId: widget.resourceId,
                    title: widget.resourceTitle,
                    subject: widget.subject,
                    semester: widget.semester,
                    branch: widget.branch,
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_rounded,
                      color: AppTheme.error,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _buildControlsPanel(isDark),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Container(
              height: 44,
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
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.summarize_rounded, size: 14),
                    text: 'Summary',
                  ),
                  Tab(icon: Icon(Icons.quiz_rounded, size: 14), text: 'Quiz'),
                  Tab(icon: Icon(Icons.style_rounded, size: 14), text: 'Cards'),
                  Tab(
                    icon: Icon(Icons.chat_bubble_rounded, size: 14),
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
