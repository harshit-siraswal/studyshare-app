import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/ai_question_paper.dart';

class FlashcardPdfEntry {
  const FlashcardPdfEntry({required this.term, required this.definition});

  final String term;
  final String definition;
}

class SummaryPdfService {
  Future<File> saveSummaryPdf({
    required String title,
    required String summary,
    String subtitle = 'AI Study Summary',
    String watermarkText = 'StudyShare',
  }) async {
    final bytes = await generateSummaryPdfBytes(
      title: title,
      summary: summary,
      subtitle: subtitle,
      watermarkText: watermarkText,
    );
    return _writePdfFile(baseName: title, suffix: 'summary', bytes: bytes);
  }

  Future<File> saveQuestionPaperPdf({
    required AiQuestionPaper paper,
    String subtitle = 'AI Test Paper',
    String watermarkText = 'StudyShare Test',
  }) async {
    final bytes = await generateQuestionPaperPdfBytes(
      paper: paper,
      subtitle: subtitle,
      watermarkText: watermarkText,
    );
    return _writePdfFile(baseName: paper.title, suffix: 'quiz', bytes: bytes);
  }

  Future<File> saveFlashcardsPdf({
    required String title,
    required List<FlashcardPdfEntry> flashcards,
    String subtitle = 'AI Flashcards',
    String watermarkText = 'StudyShare Cards',
  }) async {
    final bytes = await generateFlashcardsPdfBytes(
      title: title,
      flashcards: flashcards,
      subtitle: subtitle,
      watermarkText: watermarkText,
    );
    return _writePdfFile(baseName: title, suffix: 'flashcards', bytes: bytes);
  }

  Future<Uint8List> generateSummaryPdfBytes({
    required String title,
    required String summary,
    String subtitle = 'AI Study Summary',
    String watermarkText = 'StudyShare',
  }) async {
    final palette = _PdfPalette.summary();
    final doc = pw.Document();
    final data = _parseSummary(summary);
    final displayTitle = _safeTitle(title, 'Study Summary');
    final metaLine = data.subjectHint.isEmpty
        ? 'Summary Report'
        : '${data.subjectHint.toUpperCase()} - Summary Report';

    doc.addPage(
      _multiPage(
        palette: palette,
        documentLabel: subtitle,
        shortTitle: displayTitle,
        build: (context) => [
          _pad(
            _buildHero(
              title: displayTitle,
              metaLine: metaLine,
              palette: palette,
            ),
          ),
          _pad(_buildSectionTitle('AI Summary', palette)),
          ...data.paragraphs.map((paragraph) => _pad(_bodyText(paragraph))),
          if (data.keyPoints.isNotEmpty) ...[
            _pad(pw.SizedBox(height: 10)),
            _pad(_eyebrow('Key Points', palette)),
            _pad(_buildNumberedHighlights(data.keyPoints, palette)),
          ],
          pw.NewPage(),
          _pad(_buildSectionTitle('Quick Review', palette)),
          _pad(_buildReviewTable(data.reviewRows, palette)),
          _pad(pw.SizedBox(height: 18)),
          _pad(_buildStatsGrid(data.stats, palette)),
        ],
      ),
    );

    return doc.save();
  }

  Future<Uint8List> generateQuestionPaperPdfBytes({
    required AiQuestionPaper paper,
    String subtitle = 'AI Test Paper',
    String watermarkText = 'StudyShare Test',
  }) async {
    final palette = _PdfPalette.quiz();
    final doc = pw.Document();
    final subject = paper.subject.trim();
    final displayTitle = _safeTitle(
      paper.title,
      subject.isEmpty ? 'Practice Quiz' : '$subject Practice Quiz',
    );

    doc.addPage(
      _multiPage(
        palette: palette,
        documentLabel: subtitle,
        shortTitle: subject.isEmpty ? displayTitle : subject,
        build: (context) => [
          _pad(
            _buildHero(
              title: displayTitle,
              metaLine:
                  '${paper.questions.length} questions - Multiple choice - Correct answers highlighted - Explanations included',
              palette: palette,
            ),
          ),
          ...paper.questions.asMap().entries.map(
            (entry) =>
                _pad(_buildQuizCard(entry.key + 1, entry.value, palette)),
          ),
          _pad(pw.SizedBox(height: 8)),
          _pad(_buildScoreStrip(palette)),
        ],
      ),
    );

    return doc.save();
  }

  Future<Uint8List> generateFlashcardsPdfBytes({
    required String title,
    required List<FlashcardPdfEntry> flashcards,
    String subtitle = 'AI Flashcards',
    String watermarkText = 'StudyShare Cards',
  }) async {
    final palette = _PdfPalette.flashcards();
    final doc = pw.Document();
    final displayTitle = _safeTitle(title, 'Study Flashcards');

    doc.addPage(
      _multiPage(
        palette: palette,
        documentLabel: subtitle,
        shortTitle: displayTitle,
        build: (context) => [
          _pad(
            _buildHero(
              title: displayTitle,
              metaLine:
                  '${flashcards.length} cards - Term / Definition format - Cover the right column to self-test',
              palette: palette,
            ),
          ),
          _pad(
            _instructionBanner(
              'How to use these flashcards: Cover the Definition column with a piece of paper or your hand. Read the Term, recall the definition, then reveal to check. Mark cards you struggled with and revisit them.',
              palette,
            ),
          ),
          _pad(_buildFlashcardTable(flashcards, palette)),
          pw.NewPage(),
          _pad(_buildSectionTitle('Progress Tracker', palette)),
          _pad(_buildProgressTracker(palette)),
        ],
      ),
    );

    return doc.save();
  }

  String buildQuestionPaperText(AiQuestionPaper paper) {
    final buffer = StringBuffer()
      ..writeln(paper.title)
      ..writeln('Subject: ${paper.subject}')
      ..writeln('Semester: ${paper.semester}')
      ..writeln('Branch: ${paper.branch}')
      ..writeln('');

    for (final entry in paper.questions.asMap().entries) {
      final question = entry.value;
      buffer.writeln('Q${entry.key + 1}. ${_pdfSafeText(question.question)}');
      for (final option in question.options.asMap().entries) {
        buffer.writeln(
          '${_optionLabel(option.key)}. ${_pdfSafeText(option.value)}',
        );
      }
      buffer.writeln('Answer: ${_optionLabel(question.correctIndex)}');
      if (question.explanation.trim().isNotEmpty) {
        buffer.writeln('Explanation: ${_pdfSafeText(question.explanation)}');
      }
      buffer.writeln('');
    }
    return buffer.toString().trim();
  }

  pw.MultiPage _multiPage({
    required _PdfPalette palette,
    required String documentLabel,
    required String shortTitle,
    required List<pw.Widget> Function(pw.Context context) build,
  }) {
    final generatedOn = DateFormat('MMM d, y').format(DateTime.now());
    return pw.MultiPage(
      pageTheme: const pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
      ),
      header: (context) => _header(documentLabel, shortTitle, palette),
      footer: (context) => _footer(generatedOn, context.pageNumber, palette),
      build: build,
    );
  }

  pw.Widget _header(String label, String title, _PdfPalette palette) {
    return pw.Container(
      height: 56,
      color: palette.primary,
      padding: const pw.EdgeInsets.fromLTRB(54, 16, 54, 14),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'studyshare',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            '${_pdfSafeText(label.trim())}  |  ${_ellipsize(_pdfSafeText(title), 32)}',
            style: pw.TextStyle(color: PdfColors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(String generatedOn, int pageNumber, _PdfPalette palette) {
    return pw.Container(
      height: 26,
      color: palette.footer,
      padding: const pw.EdgeInsets.fromLTRB(54, 7, 54, 7),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by studyshare AI  |  $generatedOn',
            style: pw.TextStyle(color: palette.mutedText, fontSize: 8.5),
          ),
          pw.Text(
            'Page $pageNumber',
            style: pw.TextStyle(color: palette.mutedText, fontSize: 8.5),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildHero({
    required String title,
    required String metaLine,
    required _PdfPalette palette,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 34),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          color: palette.hero,
          child: pw.Text(
            _pdfSafeText(title),
            style: pw.TextStyle(
              color: palette.heading,
              fontSize: 23,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          _pdfSafeText(metaLine),
          style: pw.TextStyle(color: palette.mutedText, fontSize: 9),
        ),
        pw.SizedBox(height: 22),
      ],
    );
  }

  pw.Widget _buildSectionTitle(String title, _PdfPalette palette) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(width: 4, height: 22, color: palette.primary),
        pw.SizedBox(width: 10),
        pw.Text(
          title,
          style: pw.TextStyle(
            color: palette.heading,
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _eyebrow(String label, _PdfPalette palette) => pw.Text(
    _pdfSafeText(label.toUpperCase()),
    style: pw.TextStyle(
      color: palette.mutedText,
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
    ),
  );

  pw.Widget _bodyText(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      _pdfSafeText(text),
      style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
    ),
  );

  pw.Widget _buildNumberedHighlights(
    List<_SummaryPoint> points,
    _PdfPalette palette,
  ) {
    return pw.Column(
      children: points
          .take(6)
          .map((point) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 22,
                    height: 22,
                    alignment: pw.Alignment.center,
                    color: palette.primary,
                    child: pw.Text(
                      '${point.index}',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Text(
                      '${point.label}: ${point.body}',
                      style: const pw.TextStyle(
                        fontSize: 10.5,
                        lineSpacing: 2.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }

  pw.Widget _buildReviewTable(List<_ReviewRow> rows, _PdfPalette palette) {
    final safeRows = rows.isEmpty
        ? const <_ReviewRow>[
            _ReviewRow(
              topic: 'Overview',
              takeaway: 'No structured highlights were available.',
            ),
          ]
        : rows.take(6).toList(growable: false);

    return _buildTable(
      headers: const ['Topic', 'Takeaway'],
      rows: safeRows
          .map((row) => <String>[row.topic, row.takeaway])
          .toList(growable: false),
      palette: palette,
      columnWidths: <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(150),
        1: const pw.FlexColumnWidth(),
      },
    );
  }

  pw.Widget _buildStatsGrid(List<_SummaryStat> stats, _PdfPalette palette) {
    return pw.Row(
      children: stats
          .asMap()
          .entries
          .map((entry) {
            final stat = entry.value;
            return pw.Expanded(
              child: pw.Container(
                height: 72,
                margin: pw.EdgeInsets.only(
                  right: entry.key == stats.length - 1 ? 0 : 8,
                ),
                decoration: pw.BoxDecoration(
                  color: palette.surface,
                  border: pw.Border.all(color: palette.line, width: 0.8),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      stat.value,
                      style: pw.TextStyle(
                        fontSize: 19,
                        fontWeight: pw.FontWeight.bold,
                        color: palette.heading,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      stat.label,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: palette.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  pw.Widget _buildQuizCard(
    int number,
    AiQuestionPaperQuestion question,
    _PdfPalette palette,
  ) {
    final sourceParts = <String>[
      question.source.title.trim(),
      question.source.section.trim(),
      question.source.pages.trim(),
    ].where((value) => value.isNotEmpty).toList(growable: false);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 26,
                height: 42,
                color: palette.primary,
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Q${number.toString().padLeft(2, '0')}',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  color: palette.surface,
                  child: pw.Text(
                    _pdfSafeText(question.question),
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: palette.heading,
                    ),
                  ),
                ),
              ),
            ],
          ),
          ...question.options.asMap().entries.map((option) {
            final isCorrect = option.key == question.correctIndex;
            return pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              decoration: pw.BoxDecoration(
                color: isCorrect ? palette.successSoft : PdfColors.white,
                border: pw.Border(
                  bottom: pw.BorderSide(color: palette.line, width: 0.8),
                ),
              ),
              child: pw.Text(
                '${isCorrect ? 'Correct: ' : ''}${_optionLabel(option.key)}. ${_pdfSafeText(option.value)}',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  color: isCorrect ? palette.successText : palette.body,
                  fontWeight: isCorrect
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            );
          }),
          if (question.explanation.trim().isNotEmpty)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 9),
              padding: const pw.EdgeInsets.all(10),
              color: palette.infoSoft,
              child: pw.Text(
                'Explanation: ${_pdfSafeText(question.explanation.trim())}',
                style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2),
              ),
            ),
          if (sourceParts.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                'Source: ${_pdfSafeText(sourceParts.join(' | '))}',
                style: pw.TextStyle(fontSize: 8.5, color: palette.mutedText),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildScoreStrip(_PdfPalette palette) {
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: palette.line)),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              child: pw.Text(
                'Score: ____ / 10',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: palette.primary,
                ),
              ),
            ),
          ),
          pw.Container(width: 1, height: 40, color: palette.line),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              child: pw.Text(
                'Date completed: ____________',
                style: pw.TextStyle(fontSize: 10.5, color: palette.mutedText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _instructionBanner(String text, _PdfPalette palette) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: palette.warningSoft,
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2),
      ),
    );
  }

  pw.Widget _buildFlashcardTable(
    List<FlashcardPdfEntry> flashcards,
    _PdfPalette palette,
  ) {
    final rows = flashcards.isEmpty
        ? const <List<String>>[
            [
              '1',
              'No cards yet',
              'Generate flashcards to export this sheet.',
              '',
            ],
          ]
        : flashcards
              .asMap()
              .entries
              .map((entry) {
                return <String>[
                  '${entry.key + 1}',
                  entry.value.term,
                  entry.value.definition,
                  '____',
                ];
              })
              .toList(growable: false);

    return _buildTable(
      headers: const ['#', 'TERM', 'DEFINITION', 'GOT IT'],
      rows: rows,
      palette: palette.copyWith(tableHeader: _color(0x1E203E)),
      columnWidths: <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(26),
        1: const pw.FixedColumnWidth(132),
        2: const pw.FlexColumnWidth(),
        3: const pw.FixedColumnWidth(52),
      },
      headerFontSize: 8.5,
      cellFontSize: 9.5,
    );
  }

  pw.Widget _buildProgressTracker(_PdfPalette palette) {
    return _buildTable(
      headers: const ['Round', 'Date', 'Cards Correct', 'Notes'],
      rows: List<List<String>>.generate(
        4,
        (index) => <String>[
          '${index + 1}',
          '____ / ____ / ______',
          '____ / 20',
          '',
        ],
      ),
      palette: palette,
      columnWidths: <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(56),
        1: const pw.FixedColumnWidth(140),
        2: const pw.FixedColumnWidth(110),
        3: const pw.FlexColumnWidth(),
      },
    );
  }

  pw.Widget _buildTable({
    required List<String> headers,
    required List<List<String>> rows,
    required _PdfPalette palette,
    required Map<int, pw.TableColumnWidth> columnWidths,
    double headerFontSize = 9,
    double cellFontSize = 10,
  }) {
    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: palette.line, width: 0.7),
        verticalInside: pw.BorderSide(color: palette.line, width: 0.7),
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: palette.tableHeader),
          children: headers
              .map(
                (header) => _tableCell(
                  header,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 8,
                  ),
                  style: pw.TextStyle(
                    fontSize: headerFontSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              )
              .toList(growable: false),
        ),
        ...rows.asMap().entries.map((entry) {
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: entry.key.isEven ? PdfColors.white : palette.surface,
            ),
            children: entry.value
                .map(
                  (cell) => _tableCell(
                    cell,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 8,
                    ),
                    style: pw.TextStyle(
                      fontSize: cellFontSize,
                      color: palette.body,
                    ),
                  ),
                )
                .toList(growable: false),
          );
        }),
      ],
    );
  }

  pw.Widget _tableCell(
    String value, {
    required pw.EdgeInsets padding,
    required pw.TextStyle style,
  }) {
    return pw.Padding(
      padding: padding,
      child: pw.Text(_pdfSafeText(value), style: style),
    );
  }

  Future<File> _writePdfFile({
    required String baseName,
    required String suffix,
    required Uint8List bytes,
  }) async {
    final directory = await _resolveDirectory();
    final file = File(
      p.join(
        directory.path,
        '${_sanitizeFileName(baseName)}_${suffix}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Directory> _resolveDirectory() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final directories = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (directories != null && directories.isNotEmpty) {
          final directory = directories.firstWhere(
            (item) => item.path.trim().isNotEmpty,
            orElse: () => directories.first,
          );
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }
          return directory;
        }
      }

      if (!kIsWeb && !Platform.isIOS && !Platform.isAndroid) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          if (!await downloads.exists()) {
            await downloads.create(recursive: true);
          }
          return downloads;
        }
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to resolve PDF output directory',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final appDocs = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(appDocs.path, 'exports'));
    if (!await exports.exists()) {
      await exports.create(recursive: true);
    }
    return exports;
  }

  String _sanitizeFileName(String raw) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), '_');
    final cleaned = compact.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (cleaned.isEmpty) return 'studyshare';
    return cleaned.length > 48 ? cleaned.substring(0, 48) : cleaned;
  }

  String _safeTitle(String value, String fallback) {
    final trimmed = _pdfSafeText(value).trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _ellipsize(String value, int limit) {
    if (value.length <= limit) return value;
    return '${value.substring(0, limit - 3).trimRight()}...';
  }

  String _optionLabel(int index) {
    if (index < 0) return '?';
    return index < 26 ? String.fromCharCode(65 + index) : '${index + 1}';
  }

  String _pdfSafeText(String value) {
    return value
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('−', '-')
        .replaceAll('•', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('…', '...')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trimRight();
  }

  pw.Widget _pad(pw.Widget child) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 54),
    child: child,
  );
}

_SummaryDocument _parseSummary(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').trim();
  final fallback = normalized.isEmpty
      ? 'No summary content was available for export.'
      : normalized;
  final paragraphs = fallback
      .split(RegExp(r'\n\s*\n'))
      .map((item) => item.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  final sentences = RegExp(r'[^.!?]+[.!?]?')
      .allMatches(fallback)
      .map((match) => match.group(0)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  final bulletLines = fallback
      .split('\n')
      .map((line) => line.trim())
      .where((line) => RegExp(r'^([-*]|[0-9]+\.)\s+').hasMatch(line))
      .map(
        (line) => line.replaceFirst(RegExp(r'^([-*]|[0-9]+\.)\s+'), '').trim(),
      )
      .toList(growable: false);

  final sourcePoints = bulletLines.isNotEmpty
      ? bulletLines
      : sentences.take(6).toList();
  final points = sourcePoints
      .asMap()
      .entries
      .map((entry) {
        final chunks = entry.value.split(RegExp(r'\s+-\s+|:\s+'));
        final fallbackWords = entry.value
            .trim()
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .toList(growable: false);
        final fallbackLabel = fallbackWords.take(4).join(' ');
        final fallbackBody = fallbackWords.skip(4).join(' ').trim();
        final firstChunk = chunks.first.trim();
        final useExplicitLabel =
            chunks.length > 1 && firstChunk.split(RegExp(r'\s+')).length <= 5;
        final label = useExplicitLabel
            ? firstChunk
            : (fallbackLabel.isEmpty
                  ? 'Point ${entry.key + 1}'
                  : fallbackLabel);
        final body = chunks.length > 1 && useExplicitLabel
            ? chunks.sublist(1).join(' - ').trim()
            : (fallbackBody.isEmpty ? entry.value.trim() : fallbackBody);
        return _SummaryPoint(index: entry.key + 1, label: label, body: body);
      })
      .toList(growable: false);

  final reviewRows = points.isEmpty
      ? <_ReviewRow>[
          _ReviewRow(
            topic: 'Summary',
            takeaway: paragraphs.isEmpty ? fallback : paragraphs.first,
          ),
        ]
      : points
            .take(6)
            .map(
              (point) => _ReviewRow(topic: point.label, takeaway: point.body),
            )
            .toList(growable: false);

  final wordCount = fallback
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .length;
  final readMinutes = (wordCount / 180).ceil().clamp(1, 99);

  return _SummaryDocument(
    paragraphs: paragraphs.isEmpty ? <String>[fallback] : paragraphs,
    keyPoints: points,
    reviewRows: reviewRows,
    stats: <_SummaryStat>[
      _SummaryStat(value: '${paragraphs.length}', label: 'Sections'),
      _SummaryStat(value: '${points.length}', label: 'Key ideas'),
      _SummaryStat(value: '$wordCount', label: 'Words'),
      _SummaryStat(value: '$readMinutes min', label: 'Read time'),
    ],
    subjectHint: paragraphs.isNotEmpty
        ? paragraphs.first.split(' ').take(4).join(' ')
        : '',
  );
}

class _SummaryDocument {
  const _SummaryDocument({
    required this.paragraphs,
    required this.keyPoints,
    required this.reviewRows,
    required this.stats,
    required this.subjectHint,
  });

  final List<String> paragraphs;
  final List<_SummaryPoint> keyPoints;
  final List<_ReviewRow> reviewRows;
  final List<_SummaryStat> stats;
  final String subjectHint;
}

class _SummaryPoint {
  const _SummaryPoint({
    required this.index,
    required this.label,
    required this.body,
  });

  final int index;
  final String label;
  final String body;
}

class _ReviewRow {
  const _ReviewRow({required this.topic, required this.takeaway});

  final String topic;
  final String takeaway;
}

class _SummaryStat {
  const _SummaryStat({required this.value, required this.label});

  final String value;
  final String label;
}

class _PdfPalette {
  const _PdfPalette({
    required this.primary,
    required this.hero,
    required this.surface,
    required this.footer,
    required this.heading,
    required this.body,
    required this.mutedText,
    required this.tableHeader,
    required this.line,
    required this.successSoft,
    required this.successText,
    required this.infoSoft,
    required this.warningSoft,
  });

  factory _PdfPalette.summary() {
    return _PdfPalette(
      primary: _color(0x1E203E),
      hero: _color(0xF5F2EA),
      surface: _color(0xF6F4EF),
      footer: _color(0xF0EEE8),
      heading: _color(0x20212D),
      body: _color(0x33343D),
      mutedText: _color(0x8D8E97),
      tableHeader: _color(0x1E203E),
      line: _color(0xD9D8D2),
      successSoft: _color(0xEAF4DF),
      successText: _color(0x4A7D1A),
      infoSoft: _color(0xEAF3FF),
      warningSoft: _color(0xFCEFD8),
    );
  }

  factory _PdfPalette.quiz() {
    return _PdfPalette(
      primary: _color(0x236CB5),
      hero: _color(0xE5F0FF),
      surface: _color(0xF8F7F2),
      footer: _color(0xF0EEE8),
      heading: _color(0x20212D),
      body: _color(0x33343D),
      mutedText: _color(0x8D8E97),
      tableHeader: _color(0x236CB5),
      line: _color(0xD9D8D2),
      successSoft: _color(0xEAF4DF),
      successText: _color(0x4A7D1A),
      infoSoft: _color(0xE5F0FF),
      warningSoft: _color(0xFCEFD8),
    );
  }

  factory _PdfPalette.flashcards() {
    return _PdfPalette(
      primary: _color(0x447D12),
      hero: _color(0xEEF7E0),
      surface: _color(0xF8F7F2),
      footer: _color(0xF0EEE8),
      heading: _color(0x20212D),
      body: _color(0x33343D),
      mutedText: _color(0x8D8E97),
      tableHeader: _color(0x1E203E),
      line: _color(0xD9D8D2),
      successSoft: _color(0xEAF4DF),
      successText: _color(0x4A7D1A),
      infoSoft: _color(0xE5F0FF),
      warningSoft: _color(0xFCEFD8),
    );
  }

  final PdfColor primary;
  final PdfColor hero;
  final PdfColor surface;
  final PdfColor footer;
  final PdfColor heading;
  final PdfColor body;
  final PdfColor mutedText;
  final PdfColor tableHeader;
  final PdfColor line;
  final PdfColor successSoft;
  final PdfColor successText;
  final PdfColor infoSoft;
  final PdfColor warningSoft;

  _PdfPalette copyWith({
    PdfColor? primary,
    PdfColor? hero,
    PdfColor? surface,
    PdfColor? footer,
    PdfColor? heading,
    PdfColor? body,
    PdfColor? mutedText,
    PdfColor? tableHeader,
    PdfColor? line,
    PdfColor? successSoft,
    PdfColor? successText,
    PdfColor? infoSoft,
    PdfColor? warningSoft,
  }) {
    return _PdfPalette(
      primary: primary ?? this.primary,
      hero: hero ?? this.hero,
      surface: surface ?? this.surface,
      footer: footer ?? this.footer,
      heading: heading ?? this.heading,
      body: body ?? this.body,
      mutedText: mutedText ?? this.mutedText,
      tableHeader: tableHeader ?? this.tableHeader,
      line: line ?? this.line,
      successSoft: successSoft ?? this.successSoft,
      successText: successText ?? this.successText,
      infoSoft: infoSoft ?? this.infoSoft,
      warningSoft: warningSoft ?? this.warningSoft,
    );
  }
}

PdfColor _color(int hex) {
  return PdfColor(
    ((hex >> 16) & 0xFF) / 255,
    ((hex >> 8) & 0xFF) / 255,
    (hex & 0xFF) / 255,
  );
}
