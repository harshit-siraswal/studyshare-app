import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../config/theme.dart';
import '../models/ai_question_paper.dart';
import '../services/summary_pdf_service.dart';

class _QuestionFigureNote {
  const _QuestionFigureNote({
    required this.plainNote,
    this.caption,
    this.imageBytes,
  });

  final String plainNote;
  final String? caption;
  final Uint8List? imageBytes;
}

class AiQuestionPaperQuizScreen extends StatefulWidget {
  final AiQuestionPaper paper;

  const AiQuestionPaperQuizScreen({super.key, required this.paper});

  @override
  State<AiQuestionPaperQuizScreen> createState() =>
      _AiQuestionPaperQuizScreenState();
}

class _AiQuestionPaperQuizScreenState extends State<AiQuestionPaperQuizScreen> {
  final SummaryPdfService _pdfService = SummaryPdfService();
  final PageController _pageController = PageController();
  final Map<int, int> _selectedOptions = <int, int>{};

  int _currentIndex = 0;
  bool _submitted = false;
  bool _reviewMode = false;
  bool _isDownloading = false;

  String _indexToLetter(int index) {
    if (index < 0) return '?';
    if (index < 26) return String.fromCharCode(65 + index);
    return (index + 1).toString();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _score {
    var score = 0;
    for (var i = 0; i < widget.paper.questions.length; i++) {
      final selected = _selectedOptions[i];
      if (selected == widget.paper.questions[i].correctIndex) {
        score++;
      }
    }
    return score;
  }

  Future<void> _downloadPaperPdf() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final file = await _pdfService.saveQuestionPaperPdf(
        paper: widget.paper,
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
          text: 'StudyShare test paper: ${widget.paper.title}',
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Failed to download question paper PDF: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to download PDF. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _showTheory(int questionIndex) {
    final source = widget.paper.questions[questionIndex].source;
    final figureNote = _parseQuestionFigureNote(source.note);
    final hasSource =
        source.title.trim().isNotEmpty ||
        source.section.trim().isNotEmpty ||
        source.pages.trim().isNotEmpty ||
        figureNote.plainNote.trim().isNotEmpty ||
        figureNote.imageBytes != null;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_rounded, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Theory Source',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!hasSource)
                  Text(
                    'Source details were not available for this question.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  )
                else ...[
                  if (figureNote.imageBytes != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        figureNote.imageBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                    if ((figureNote.caption ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        figureNote.caption!.trim(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  _buildSourceLine(
                    label: 'Document',
                    value: source.title,
                    isDark: isDark,
                  ),
                  _buildSourceLine(
                    label: 'Section',
                    value: source.section,
                    isDark: isDark,
                  ),
                  _buildSourceLine(
                    label: 'Pages',
                    value: source.pages,
                    isDark: isDark,
                  ),
                  _buildSourceLine(
                    label: 'Note',
                    value: figureNote.plainNote,
                    isDark: isDark,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceLine({
    required String label,
    required String value,
    required bool isDark,
  }) {
    final display = value.trim();
    if (display.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          text: '$label: ',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          children: [
            TextSpan(
              text: display,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.paper.questions.length;
    final progress = total == 0 ? 0.0 : (_currentIndex + 1) / total;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF05070F)
          : const Color(0xFFF3F7FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.paper.subject.isEmpty
              ? 'Question Paper Quiz'
              : widget.paper.subject,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Download PDF',
            onPressed: _isDownloading ? null : _downloadPaperPdf,
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: total == 0
          ? Center(
              child: Text(
                'No questions generated.',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: progress),
                          duration: const Duration(milliseconds: 260),
                          builder: (context, value, _) {
                            return LinearProgressIndicator(
                              value: value.clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: isDark
                                  ? Colors.white10
                                  : Colors.black12,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppTheme.primary,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Question ${_currentIndex + 1} of $total',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _submitted
                        ? _buildResultCard(isDark)
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: total,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              return _buildQuestionCard(index, isDark);
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildQuestionCard(int index, bool isDark) {
    final question = widget.paper.questions[index];
    final figureNote = _parseQuestionFigureNote(question.source.note);
    final selected = _selectedOptions[index];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.question,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 14),
            if (figureNote.imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  figureNote.imageBytes!,
                  fit: BoxFit.contain,
                ),
              ),
              if ((figureNote.caption ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  figureNote.caption!.trim(),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
              ],
              const SizedBox(height: 14),
            ],
            ...question.options.asMap().entries.map((entry) {
              final optionIndex = entry.key;
              final label = _indexToLetter(optionIndex);
              final text = entry.value;
              final isSelected = selected == optionIndex;
              final isCorrect = question.correctIndex == optionIndex;
              final showFeedback = _reviewMode;

              Color border = isDark
                  ? AppTheme.darkBorder
                  : const Color(0xFFE2E8F0);
              Color fill = isDark ? Colors.white10 : const Color(0xFFF8FAFC);
              Color textColor = isDark
                  ? Colors.white70
                  : const Color(0xFF334155);

              if (!showFeedback && isSelected) {
                border = AppTheme.primary.withValues(alpha: 0.6);
                fill = AppTheme.primary.withValues(alpha: 0.12);
                textColor = AppTheme.primary;
              } else if (showFeedback && isSelected && isCorrect) {
                border = AppTheme.success;
                fill = AppTheme.success.withValues(alpha: 0.14);
                textColor = AppTheme.success;
              } else if (showFeedback && isSelected && !isCorrect) {
                border = AppTheme.error;
                fill = AppTheme.error.withValues(alpha: 0.14);
                textColor = AppTheme.error;
              } else if (showFeedback && isCorrect) {
                border = AppTheme.success.withValues(alpha: 0.65);
                fill = AppTheme.success.withValues(alpha: 0.1);
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: _reviewMode
                      ? null
                      : () {
                          setState(() {
                            _selectedOptions[index] = optionIndex;
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
                      color: fill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: border),
                            color: isDark ? Colors.black26 : Colors.white,
                          ),
                          child: Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            text,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (_reviewMode && selected != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'Your answer: '
                    '${_indexToLetter(selected)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Correct: '
                    '${_indexToLetter(question.correctIndex)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showTheory(index),
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: const Text('View Theory'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _reviewMode
                      ? () {
                          if (_currentIndex ==
                              widget.paper.questions.length - 1) {
                            setState(() {
                              _submitted = true;
                              _reviewMode = false;
                            });
                          } else {
                            setState(() => _currentIndex++);
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        }
                      : selected == null
                      ? null
                      : () {
                          if (_currentIndex ==
                              widget.paper.questions.length - 1) {
                            setState(() => _submitted = true);
                          } else {
                            setState(() => _currentIndex++);
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    _reviewMode
                        ? (_currentIndex == widget.paper.questions.length - 1
                              ? 'Results'
                              : 'Next')
                        : (_currentIndex == widget.paper.questions.length - 1
                              ? 'Submit'
                              : 'Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(bool isDark) {
    final total = widget.paper.questions.length;
    final score = _score;
    final percent = total == 0 ? 0 : ((score / total) * 100).round();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withValues(alpha: 0.14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$percent%',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your Score: $score / $total',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _submitted = false;
                          _reviewMode = false;
                          _selectedOptions.clear();
                          _currentIndex = 0;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_pageController.hasClients) {
                            _pageController.jumpToPage(0);
                          }
                        });
                      },
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: const Text('Retake'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _submitted = false;
                          _reviewMode = true;
                          _currentIndex = 0;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_pageController.hasClients) {
                            _pageController.jumpToPage(0);
                          }
                        });
                      },
                      icon: const Icon(Icons.fact_check_rounded, size: 16),
                      label: const Text('Review Answers'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadPaperPdf,
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('Download PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _QuestionFigureNote _parseQuestionFigureNote(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) {
      return _QuestionFigureNote(plainNote: trimmed);
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return _QuestionFigureNote(plainNote: trimmed);
      }
      final map = Map<String, dynamic>.from(decoded);
      return _QuestionFigureNote(
        plainNote: map['plainNote']?.toString() ?? '',
        caption: map['caption']?.toString(),
        imageBytes: _decodeDataUrlBytes(map['imageDataUrl']?.toString() ?? ''),
      );
    } catch (_) {
      return _QuestionFigureNote(plainNote: trimmed);
    }
  }

  Uint8List? _decodeDataUrlBytes(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('data:')) return null;
    final commaIndex = trimmed.indexOf(',');
    if (commaIndex <= 0 || commaIndex >= trimmed.length - 1) return null;
    try {
      return base64Decode(trimmed.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }
}
