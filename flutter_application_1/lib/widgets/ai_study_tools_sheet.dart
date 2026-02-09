import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../services/backend_api_service.dart';
import '../widgets/branded_loader.dart';

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
}

class Flashcard {
  final String front;
  final String back;

  Flashcard({
    required this.front,
    required this.back,
  });

  factory Flashcard.fromJson(Map<String, dynamic> json) {
    return Flashcard(
      front: json['front']?.toString() ?? '',
      back: json['back']?.toString() ?? '',
    );
  }
}

class AiStudyToolsSheet extends StatefulWidget {
  final String resourceId;
  final String resourceTitle;
  final String? collegeId;
  final String resourceType;
  final String? videoUrl;

  const AiStudyToolsSheet({
    super.key,
    required this.resourceId,
    required this.resourceTitle,
    this.collegeId,
    this.resourceType = 'notes',
    this.videoUrl,
  });

  @override
  State<AiStudyToolsSheet> createState() => _AiStudyToolsSheetState();
}

class _AiStudyToolsSheetState extends State<AiStudyToolsSheet> with SingleTickerProviderStateMixin {
  final BackendApiService _api = BackendApiService();

  late TabController _tabController;
  bool _isLoading = false;
  String? _loadingType;
  String? _error;

  String? _summary;
  List<QuizQuestion>? _quiz;
  List<Flashcard>? _flashcards;

  bool _freshRun = true;
  bool _useOcr = false;
  bool _forceOcr = false;
  String _ocrProvider = 'google';
  bool _includeSource = false;
  bool _showAnswers = false;
  final Map<int, String> _selectedAnswers = {};
  String? _sourceText;
  String? _sourceType;
  String? _sourceProvider;
  bool _showSource = false;

  final Map<String, bool> _cachedMap = {};

  bool get _supportsOcr => widget.resourceType != 'video';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _activeType {
    switch (_tabController.index) {
      case 1:
        return 'quiz';
      case 2:
        return 'flashcards';
      default:
        return 'summary';
    }
  }

  Future<void> _generate(String type) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _loadingType = type;
      _error = null;
      _sourceText = null;
      _sourceType = null;
      _sourceProvider = null;
      _showSource = false;
    });

    try {
      Map<String, dynamic> response;
      final useOcr = _supportsOcr && (_useOcr || _forceOcr);
      final forceOcr = _supportsOcr && _forceOcr;
      final includeSource = _includeSource;

      if (type == 'summary') {
        response = await _api.getAiSummary(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          ocrProvider: _ocrProvider,
          force: _freshRun,
          includeSource: includeSource,
          videoUrl: widget.videoUrl,
        );
        final data = response['data'];
        setState(() {
          _summary = data is String ? data : data?.toString();
          _cachedMap['summary'] = response['cached'] == true;
        });
      } else if (type == 'quiz') {
        response = await _api.getAiQuiz(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          ocrProvider: _ocrProvider,
          force: _freshRun,
          includeSource: includeSource,
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
        });
      } else {
        response = await _api.getAiFlashcards(
          fileId: widget.resourceId,
          collegeId: widget.collegeId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          ocrProvider: _ocrProvider,
          force: _freshRun,
          includeSource: includeSource,
          videoUrl: widget.videoUrl,
        );
        final raw = (response['data'] as List?) ?? const [];
        final parsed = raw
            .whereType<Map>()
            .map((c) => Flashcard.fromJson(Map<String, dynamic>.from(c)))
            .toList();
        setState(() {
          _flashcards = parsed;
          _cachedMap['flashcards'] = response['cached'] == true;
        });
      }

      final source = response['source'] as Map<String, dynamic>?;
      if (source != null) {
        setState(() {
          _sourceText = source['text']?.toString();
          _sourceType = source['type']?.toString();
          _sourceProvider = source['ocrProvider']?.toString();
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
          color: selected
              ? (isDark ? Colors.white : Colors.white)
              : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppTheme.primary,
      backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
      showCheckmark: false,
    );
  }

  Widget _buildOptions(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildOptionChip(
              label: 'Fresh run',
              selected: _freshRun,
              onSelected: (val) => setState(() => _freshRun = val),
              isDark: isDark,
            ),
            if (_supportsOcr)
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
            if (_supportsOcr)
              _buildOptionChip(
                label: 'Force OCR',
                selected: _forceOcr,
                onSelected: (val) {
                  setState(() {
                    _forceOcr = val;
                    if (val) _useOcr = true;
                  });
                },
                isDark: isDark,
              ),
            _buildOptionChip(
              label: 'Include source',
              selected: _includeSource,
              onSelected: (val) => setState(() => _includeSource = val),
              isDark: isDark,
            ),
          ],
        ),
        if (_supportsOcr) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'OCR Provider:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _ocrProvider,
                underline: const SizedBox.shrink(),
                dropdownColor: isDark ? AppTheme.darkSurface : Colors.white,
                items: const [
                  DropdownMenuItem(value: 'google', child: Text('Google Vision')),
                  DropdownMenuItem(value: 'sarvam', child: Text('Sarvam OCR')),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _ocrProvider = val);
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSource(bool isDark) {
    if (_sourceText == null || _sourceText!.isEmpty) return const SizedBox.shrink();
    final label = _sourceType == null
        ? 'Source'
        : _sourceType == 'transcript'
            ? 'Transcript'
            : 'OCR Output';
    final provider = _sourceProvider != null ? ' (${_sourceProvider!})' : '';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: ExpansionTile(
        initiallyExpanded: _showSource,
        onExpansionChanged: (val) => setState(() => _showSource = val),
        title: Text(
          '$label$provider',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          SelectableText(
            _sourceText!,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
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
    if (_summary == null) {
      return Center(
        child: Text(
          'Generate a summary from this document.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            _summary!,
            style: GoogleFonts.inter(fontSize: 13, height: 1.4),
          ),
          _buildSource(isDark),
        ],
      ),
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
      return Center(
        child: Text(
          'Generate MCQs for quick revision.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _quiz!.length,
      itemBuilder: (context, idx) {
        final q = _quiz![idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Q${idx + 1}. ${q.question}',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
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
                        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder);
                final fillColor = isCorrect
                    ? AppTheme.success.withValues(alpha: 0.15)
                    : isWrong
                        ? AppTheme.error.withValues(alpha: 0.15)
                        : (isDark ? AppTheme.darkCard : Colors.white);
                final textColor = isCorrect
                    ? AppTheme.success
                    : isWrong
                        ? AppTheme.error
                        : (isDark ? Colors.white : AppTheme.lightTextPrimary);
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor, width: 1),
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
                              color: isCorrect
                                  ? AppTheme.success.withValues(alpha: 0.2)
                                  : isWrong
                                      ? AppTheme.error.withValues(alpha: 0.2)
                                      : (isDark ? AppTheme.darkSurface : AppTheme.lightSurface),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              opt,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: textColor,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isCorrect)
                            const Icon(Icons.check_circle, size: 18, color: AppTheme.success),
                          if (isWrong)
                            const Icon(Icons.cancel, size: 18, color: AppTheme.error),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
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
      return Center(
        child: Text(
          'Generate flashcards for quick recall.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _flashcards!.length,
      itemBuilder: (context, idx) {
        final card = _flashcards![idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
          ),
          child: ExpansionTile(
            title: Text(
              card.front,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Text(
                card.back,
                style: GoogleFonts.inter(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'AI Study Tools',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.warning_rounded, color: AppTheme.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.error),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: _buildOptions(isDark),
          ),
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: isDark ? Colors.white70 : Colors.black54,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'Summary'),
              Tab(text: 'Quiz'),
              Tab(text: 'Cards'),
            ],
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
                        style: GoogleFonts.inter(fontSize: 12),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    Expanded(child: _buildQuizTab(isDark)),
                  ],
                ),
                _buildFlashcardsTab(isDark),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  if (_cachedMap[_activeType] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Cached',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _generate(_activeType),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Generate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
