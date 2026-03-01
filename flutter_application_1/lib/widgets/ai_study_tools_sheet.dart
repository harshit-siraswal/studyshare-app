import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../config/theme.dart';
import '../screens/ai_chat_screen.dart';
import '../services/ai_output_local_service.dart';
import '../services/backend_api_service.dart';
import '../services/summary_pdf_service.dart';
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

  final Map<String, bool> _cachedMap = {};
  final Map<String, bool> _savedLocallyMap = {};

  bool _isFullscreen = false;

  bool get _supportsOcr => widget.resourceType != 'video';

  final TextEditingController _ocrProviderController = TextEditingController();

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
    _ocrProviderController.text = _ocrProviderLabelFor(_ocrProvider);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (mounted) setState(() {});
    });
    _loadSavedOutputs();
  }

  @override
  void dispose() {
    _ocrProviderController.dispose();
    _tabController.dispose();
    super.dispose();
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

  bool _hasOutput(String type) {
    switch (type) {
      case 'summary':
        return _summary != null && _summary!.trim().isNotEmpty;
      case 'quiz':
        return _quiz != null && _quiz!.isNotEmpty;
      case 'flashcards':
        return _flashcards != null && _flashcards!.isNotEmpty;
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
          _cachedMap['flashcards'] = response['cached'] == true;
          _savedLocallyMap['flashcards'] = false;
        });
      }
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

  Widget _buildOptionChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    required bool isDark,
  }) {
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: selected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppTheme.primary,
      backgroundColor: isDark
          ? Colors.white10
          : Colors.black.withValues(alpha: 0.05),
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? Colors.transparent
              : (isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
    );
  }

  Widget _buildControls(bool isDark) {
    if (!_supportsOcr) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Extraction Mode',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildOptionChip(
                label: 'Use OCR',
                selected: _useOcr,
                onSelected: (val) {
                  setState(() {
                    _useOcr = val;
                    if (!val) _forceOcr = false;
                  });
                },
                isDark: isDark,
              ),
              const Spacer(),
              Text(
                'Provider:',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: DropdownMenu<String>(
                  controller: _ocrProviderController,
                  width: 100,
                  initialSelection: _ocrProvider,
                  enabled: _useOcr,
                  enableSearch: false,
                  requestFocusOnTap: false,
                  textStyle: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  inputDecorationTheme: InputDecorationTheme(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: isDark ? AppTheme.darkSurface : Colors.white,
                  ),
                  menuStyle: MenuStyle(
                    backgroundColor: WidgetStatePropertyAll<Color>(
                      isDark ? AppTheme.darkSurface : Colors.white,
                    ),
                  ),
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(
                      value: 'google_vision',
                      label: 'Google Vision',
                    ),
                    DropdownMenuEntry(value: 'sarvam', label: 'Sarvam'),
                  ],
                  onSelected: (String? val) {
                    if (val != null) {
                      setState(() {
                        _ocrProvider = val;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: blocks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final block = blocks[index];
        switch (block.kind) {
          case _SummaryBlockKind.heading:
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.text,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: 90,
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
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    block.text,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            );
          case _SummaryBlockKind.paragraph:
            return SelectableText(
              block.text,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.6,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
            );
        }
      },
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
      itemCount: _quiz!.length,
      itemBuilder: (context, idx) {
        final q = _quiz![idx];
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
                      'Q${idx + 1}',
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: _flashcards!.length,
      itemBuilder: (context, idx) {
        final card = _flashcards![idx];
        final flipped = _flippedCardIndexes.contains(idx);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (flipped) {
                _flippedCardIndexes.remove(idx);
              } else {
                _flippedCardIndexes.add(idx);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: flipped
                    ? [const Color(0xFF0EA5E9), _studioBlue]
                    : [const Color(0xFF60A5FA), _studioBlueDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: (flipped ? _studioBlue : _studioBlueDark).withValues(
                    alpha: 0.28,
                  ),
                  blurRadius: 16,
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
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
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
                    Icon(
                      flipped ? Icons.flip_to_back : Icons.flip_to_front,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  flipped ? 'Answer' : 'Question',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  flipped ? card.back : card.front,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tap card to flip',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatTab(bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
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
              child: const Icon(Icons.chat_bubble_outline_rounded, size: 36, color: _studioBlue),
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

      final isBullet = RegExp(r'^[-*]\s+').hasMatch(trimmedRaw);

      var line = trimmedRaw
          .replaceFirst(RegExp(r'^#+\s*'), '')
          .replaceFirst(RegExp(r'^[-*]+\s*'), '')
          .replaceAll('**', '');
      final plain = line.replaceAll(RegExp(r'[:\-\s]+$'), '').trim();
      final words = plain
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      final looksLikeHeading =
          trimmedRaw.startsWith('#') ||
          (!isBullet && trimmedRaw.endsWith(':')) ||
          (!isBullet && words <= 7 && RegExp(r'^[A-Z]').hasMatch(plain));

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

    return AnimatedContainer(
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
              ? [const Color(0xFF0A1120).withValues(alpha: 0.85), const Color(0xFF040810).withValues(alpha: 0.95)]
              : [const Color(0xFFFFFFFF).withValues(alpha: 0.9), const Color(0xFFF0F5FF).withValues(alpha: 0.95)],
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
          const SizedBox(height: 12),
          Container(
            width: 46,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white24
                  : _studioBlue.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 4),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_studioBlue, _studioBlueDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: _studioBlue.withValues(alpha: 0.24),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Image.asset(
                        'assets/images/ai_logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Semantics(
                            label: 'AI Studio logo unavailable',
                            child: const Center(
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Studio',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.resourceTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            letterSpacing: 0.05,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isFullscreen = !_isFullscreen;
                      });
                    },
                    icon: Icon(
                      _isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
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
          _buildControls(isDark),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF111A2A)
                    : const Color(0xFFF2F7FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF24324A)
                      : const Color(0xFFD5E4FF),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: _studioBlueDark,
                unselectedLabelColor: isDark
                    ? Colors.white70
                    : const Color(0xFF5B6D8D),
                indicator: BoxDecoration(
                  color: isDark ? Colors.white : const Color(0xFFE6F0FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white12
                        : _studioBlue.withValues(alpha: 0.28),
                  ),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: _studioBlue.withValues(alpha: 0.14),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
                tabs: const [
                  Tab(text: 'Summary'),
                  Tab(text: 'Quiz'),
                  Tab(text: 'Cards'),
                  Tab(text: 'Chat'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(isDark),
                Column(
                  children: [
                    SwitchListTile(
                      value: _showAnswers,
                      onChanged: (val) => setState(() => _showAnswers = val),
                      title: Text(
                        'Show answers',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                    ),
                    Expanded(child: _buildQuizTab(isDark)),
                  ],
                ),
                _buildFlashcardsTab(isDark),
                _buildChatTab(isDark),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_activeType != 'chat') ...[
                      if (_cachedMap[_activeType] == true)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Server cache',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      if (isSavedLocally)
                        Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Saved on device',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      if (!hasOutput)
                        ElevatedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => _generate(_activeType, regenerate: false),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generate'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _studioBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        )
                      else ...[
                        if (!isSavedLocally)
                          OutlinedButton.icon(
                            onPressed: _isSaving ? null : _saveActiveOutput,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined, size: 16),
                            label: const Text('Save'),
                          ),
                        if (!isSavedLocally) const SizedBox(width: 6),
                        if (_activeType == 'summary')
                          IconButton(
                            key: _pdfButtonKey,
                            tooltip: 'Download PDF',
                            onPressed: _isDownloadingSummary
                                ? null
                                : _downloadSummaryPdf,
                            icon: _isDownloadingSummary
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.picture_as_pdf_outlined),
                          ),
                        if (_activeType == 'summary') const SizedBox(width: 6),
                        ElevatedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => _generate(_activeType, regenerate: true),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Regenerate'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _studioBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SummaryBlockKind { heading, bullet, paragraph }

class _SummaryBlock {
  final _SummaryBlockKind kind;
  final String text;

  _SummaryBlock({required this.kind, required this.text});
}
