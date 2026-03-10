import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SummaryPdfService {
  Future<File> saveSummaryPdf({
    required String title,
    required String summary,
    String subtitle = 'AI Study Summary',
    String watermarkText = 'StudyShare',
  }) async {
    final directory = await _resolveDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeTitle = _sanitizeFileName(title);
    final filename = '${safeTitle}_summary_$timestamp.pdf';
    final outputFile = File(p.join(directory.path, filename));

    final bytes = _buildPdfBytes(
      title: title.trim().isEmpty ? 'Study Summary' : title.trim(),
      subtitle: subtitle,
      watermarkText: watermarkText,
      summary: summary,
    );

    await outputFile.writeAsBytes(bytes, flush: true);
    return outputFile;
  }

  Future<Directory> _resolveDirectory() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final directories = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (directories != null) {
          for (final directory in directories) {
            if (directory.path.trim().isEmpty) continue;
            if (!await directory.exists()) {
              await directory.create(recursive: true);
            }
            return directory;
          }
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
    } catch (e, st) {
      developer.log(
        'Failed to resolve downloads directory',
        error: e,
        stackTrace: st,
      );
    }
    final appDocs = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(appDocs.path, 'exports'));
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    return exportsDir;
  }

  String _sanitizeFileName(String raw) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), '_');
    final sanitized = compact.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
    if (sanitized.isEmpty) return 'studyshare';
    return sanitized.length > 40 ? sanitized.substring(0, 40) : sanitized;
  }

  Uint8List _buildPdfBytes({
    required String title,
    required String subtitle,
    required String watermarkText,
    required String summary,
    String? headerBrandName,
  }) {
    final lines = _buildWrappedLines(
      title: title,
      subtitle: subtitle,
      summary: summary,
    );
    const int maxLinesPerPage = 42;

    final pages = <List<String>>[];
    for (var i = 0; i < lines.length; i += maxLinesPerPage) {
      final end = min(i + maxLinesPerPage, lines.length);
      pages.add(lines.sublist(i, end));
    }
    if (pages.isEmpty) {
      pages.add(const ['No content available']);
    }

    final objectMap = <int, String>{};
    final pageObjectIds = <int>[];
    final contentObjectIds = <int>[];

    var nextObjectId = 3; // 1: catalog, 2: pages
    for (var i = 0; i < pages.length; i++) {
      final pageId = nextObjectId++;
      final contentId = nextObjectId++;
      pageObjectIds.add(pageId);
      contentObjectIds.add(contentId);
    }
    final regularFontId = nextObjectId++;
    final boldFontId = nextObjectId++;

    objectMap[regularFontId] =
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
    objectMap[boldFontId] =
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>';

    for (var i = 0; i < pages.length; i++) {
      final pageId = pageObjectIds[i];
      final contentId = contentObjectIds[i];
      final stream = _buildPageStream(
        pages[i],
        watermarkText: watermarkText.trim().isEmpty ? (headerBrandName ?? 'StudyShare') : watermarkText.trim(),
      );

      objectMap[contentId] =
          '<< /Length ${utf8.encode(stream).length} >>\n'
          'stream\n'
          '$stream\n'
          'endstream';

      objectMap[pageId] =
          '<< /Type /Page /Parent 2 0 R '
          '/MediaBox [0 0 595 842] '
          '/Resources << /Font << /F1 $regularFontId 0 R /F2 $boldFontId 0 R >> >> '
          '/Contents $contentId 0 R >>';
    }

    objectMap[1] = '<< /Type /Catalog /Pages 2 0 R >>';
    objectMap[2] =
        '<< /Type /Pages /Kids [${pageObjectIds.map((id) => '$id 0 R').join(' ')}] /Count ${pageObjectIds.length} >>';

    final totalObjects = nextObjectId - 1;
    final offsets = List<int>.filled(totalObjects + 1, 0);

    final buffer = StringBuffer();
    buffer.write('%PDF-1.4\n');
    var currentOffset = utf8.encode('%PDF-1.4\n').length;

    for (var id = 1; id <= totalObjects; id++) {
      offsets[id] = currentOffset;
      final objectBody = objectMap[id] ?? '';
      final objectBlock = '$id 0 obj\n$objectBody\nendobj\n';
      buffer.write(objectBlock);
      currentOffset += utf8.encode(objectBlock).length;
    }

    final xrefOffset = currentOffset;
    buffer.write('xref\n');
    buffer.write('0 ${totalObjects + 1}\n');
    buffer.write('0000000000 65535 f \n');

    for (var id = 1; id <= totalObjects; id++) {
      final entry = '${offsets[id].toString().padLeft(10, '0')} 00000 n \n';
      buffer.write(entry);
    }

    buffer.write('trailer\n');
    buffer.write('<< /Size ${totalObjects + 1} /Root 1 0 R >>\n');
    buffer.write('startxref\n');
    buffer.write('$xrefOffset\n');
    buffer.write('%%EOF');

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  List<String> _buildWrappedLines({
    required String title,
    required String subtitle,
    required String summary,
  }) {
    final generatedAt = DateTime.now().toLocal().toIso8601String().replaceFirst(
      'T',
      ' ',
    );
    final output = <String>[
      '[H]$title',
      subtitle.trim().isEmpty ? 'Generated by StudyShare AI' : subtitle.trim(),
      'Generated on: ${generatedAt.split('.').first}',
      '',
    ];

    final rawLines = summary.replaceAll('\r', '\n').split('\n');
    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        output.add('');
        continue;
      }

      final withoutHashes = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      final collapsed = withoutHashes.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (collapsed.isEmpty) continue;

      if (_looksLikeHeadingLine(collapsed)) {
        output.add('[H]$collapsed');
        output.add('');
        continue;
      }

      var cleaned = collapsed;
      if (RegExp(r'^([-*])\s+').hasMatch(cleaned)) {
        cleaned = cleaned.replaceFirst(RegExp(r'^([-*])\s+'), '- ');
      } else if (RegExp(r'^\d+[.)]\s+').hasMatch(cleaned)) {
        cleaned = cleaned.replaceFirst(RegExp(r'^(\d+)[.)]\s+'), r'$1. ');
      }
      if (cleaned.isEmpty) continue;

      output.addAll(_wrapLine(cleaned, 84));
    }

    return output.map(_toPdfSafeText).toList();
  }

  bool _looksLikeHeadingLine(String line) {
    final plain = line.replaceAll('**', '').trim();
    if (plain.isEmpty) return false;
    if (plain.endsWith(':')) return true;
    if (RegExp(
      r'^(unit|module|chapter)\s+\d+',
      caseSensitive: false,
    ).hasMatch(plain)) {
      return true;
    }

    final wordsList = plain
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final words = wordsList.length;
    if (words == 0 || words > 7) return false;
    if (plain.endsWith('.') || plain.endsWith('!') || plain.endsWith('?')) {
      return false;
    }

    final firstWord = wordsList.first;
    final firstWordAllCaps =
        firstWord == firstWord.toUpperCase() &&
        firstWord != firstWord.toLowerCase();
    final uppercaseWordStarts = wordsList
        .where((word) => RegExp(r'^[A-Z]').hasMatch(word))
        .length;
    return firstWordAllCaps || (uppercaseWordStarts >= 2 && words >= 3);
  }

  List<String> _wrapLine(String line, int maxChars) {
    if (line.length <= maxChars) return [line];

    final words = line
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final wrapped = <String>[];
    final current = StringBuffer();

    for (final word in words) {
      if (word.isEmpty) continue;
      if (current.isEmpty) {
        current.write(word);
        continue;
      }

      final projected = '${current.toString()} $word';
      if (projected.length <= maxChars) {
        current.write(' $word');
      } else {
        wrapped.add(current.toString());
        current
          ..clear()
          ..write(word);
      }
    }

    if (current.isNotEmpty) {
      wrapped.add(current.toString());
    }
    return wrapped;
  }

  String _buildPageStream(
    List<String> lines, {
    required String watermarkText,
  }) {
    final stream = StringBuffer();
    final watermark = _escapePdfText(
      watermarkText.trim().isEmpty ? 'StudyShare' : watermarkText.trim(),
    );

    stream.writeln('q');
    stream.writeln('0.95 0.97 1 rg');
    stream.writeln('40 780 515 42 re f');
    stream.writeln('Q');

    stream.writeln('BT');
    stream.writeln('0.15 0.28 0.55 rg');
    stream.writeln('/F2 15 Tf');
    stream.writeln('1 0 0 1 48 805 Tm');
    stream.writeln('(${_escapePdfText('StudyShare')}) Tj');
    stream.writeln('/F1 10 Tf');
    stream.writeln('1 0 0 1 48 790 Tm');
    stream.writeln('(${_escapePdfText('Professional AI Document')}) Tj');
    stream.writeln('ET');

    stream.writeln('q');
    stream.writeln('0.93 g');
    stream.writeln('BT');
    stream.writeln('/F2 34 Tf');
    stream.writeln('1 0 0 1 145 410 Tm');
    stream.writeln('($watermark) Tj');
    stream.writeln('ET');
    stream.writeln('Q');

    stream.writeln('BT');
    var y = 748.0;
    for (final raw in lines) {
      if (raw.trim().isEmpty) {
        y -= 10;
        if (y < 40) break;
        continue;
      }

      final isHeading = raw.startsWith('[H]');
      final text = isHeading ? raw.substring(3).trim() : raw.trim();
      if (text.isEmpty) {
        y -= 10;
        if (y < 40) break;
        continue;
      }

      stream.writeln(isHeading ? '/F2 13 Tf' : '/F1 11 Tf');
      stream.writeln('1 0 0 1 48 ${y.toStringAsFixed(1)} Tm');
      stream.writeln('(${_escapePdfText(text)}) Tj');
      y -= isHeading ? 18 : 15;
      if (y < 40) break;
    }
    stream.writeln('ET');

    return stream.toString();
  }

  String _toPdfSafeText(String text) {
    final buffer = StringBuffer();
    for (final code in text.runes) {
      if (code >= 32 && code <= 126) {
        buffer.writeCharCode(code);
      } else {
        buffer.writeCharCode(32);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trimRight();
  }

  String _escapePdfText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }
}
