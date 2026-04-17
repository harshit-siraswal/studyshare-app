import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';

class AiFormattedText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final Color bulletColor;
  final Color headingColor;

  /// When true, lines <= 8 words ending with ":" are treated as headings.
  final bool detectColonHeadings;

  const AiFormattedText({
    super.key,
    required this.text,
    required this.baseStyle,
    required this.bulletColor,
    required this.headingColor,
    this.detectColonHeadings = true,
  });

  static const int _maxInlineDepth = 5;
  static final RegExp _bulletPattern = RegExp(
    '^([-*\\u2022]|\\d+[.)])\\s+(.+)\$',
  );
  static final RegExp _quoteBulletPattern = RegExp(
    r'^(?:>\s*)+(?:[-*\u2022]|\d+[.)])?\s*(.+)$',
  );
  static final RegExp _mathSegmentPattern = RegExp(
    r'(\$\$[\s\S]+?\$\$|\$[^$\n]+\$|\\\[[\s\S]+?\\\]|\\\([^\n]+?\\\))',
    multiLine: true,
  );

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizeBlockText(text);
    final lines = normalized.split('\n');
    final widgets = <Widget>[];

    var i = 0;
    while (i < lines.length) {
      final trimmed = lines[i].trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        i++;
        continue;
      }

      final tableBlock = _tryParseTableBlock(lines, i);
      if (tableBlock != null) {
        widgets.add(_buildTable(tableBlock));
        i = tableBlock.nextIndex;
        continue;
      }

      final headingMatch = RegExp(r'^#{1,3}\s+(.+)$').firstMatch(trimmed);
      final boldHeadingMatch = RegExp(
        r'^\*\*([^*\n][^*\n]{1,120})\*\*$',
      ).firstMatch(trimmed);
      final inlineSectionMatch = RegExp(
        r'^\*\*([^*\n][^*\n]{1,120})\*\*(?:\s*:?\s*)(.+)$',
      ).firstMatch(trimmed);
      final bulletMatch = _bulletPattern.firstMatch(trimmed);
      final quoteBulletMatch = _quoteBulletPattern.firstMatch(trimmed);

      final isColonHeading =
          detectColonHeadings &&
          headingMatch == null &&
          trimmed.endsWith(':') &&
          trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length <=
              8 &&
          RegExp(r'^[A-Z]').hasMatch(trimmed) &&
          !RegExp(
            r'^(Please|Note|For|To|If|When|This|See|Do|Use)\b',
            caseSensitive: true,
          ).hasMatch(trimmed);

      if (headingMatch != null || isColonHeading) {
        final headingText =
            headingMatch?.group(1)?.trim() ??
            trimmed.replaceFirst(RegExp(r':\s*$'), '');
        widgets.add(_buildHeading(headingText, i == 0 ? 0 : 6));
        i++;
        continue;
      }

      if (boldHeadingMatch != null) {
        widgets.add(
          _buildHeading(boldHeadingMatch.group(1)!.trim(), i == 0 ? 0 : 6),
        );
        i++;
        continue;
      }

      if (inlineSectionMatch != null) {
        final headingText = inlineSectionMatch.group(1)?.trim() ?? '';
        final bodyText = inlineSectionMatch.group(2)?.trim() ?? '';
        if (headingText.isNotEmpty && bodyText.isNotEmpty) {
          widgets.add(_buildHeading(headingText, i == 0 ? 0 : 6));
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _buildInlineContent(bodyText, baseStyle),
            ),
          );
        }
        i++;
        continue;
      }

      if (bulletMatch != null || quoteBulletMatch != null) {
        final marker = bulletMatch?.group(1)?.trim() ?? '*';
        final body =
            bulletMatch?.group(2)?.trim() ??
            quoteBulletMatch?.group(1)?.trim() ??
            '';
        final isNumericMarker =
            bulletMatch != null && RegExp(r'^\d').hasMatch(marker);

        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: isNumericMarker
                      ? Text(
                          marker,
                          style: GoogleFonts.inter(
                            fontSize: baseStyle.fontSize,
                            height: baseStyle.height,
                            fontWeight: FontWeight.w700,
                            color: bulletColor,
                          ),
                        )
                      : Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: bulletColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
                Expanded(child: _buildInlineContent(body, baseStyle)),
              ],
            ),
          ),
        );
        i++;
        continue;
      }

      widgets.add(_buildInlineContent(trimmed, baseStyle));
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  String _normalizeBlockText(String raw) {
    return raw
        .replaceAll('\r', '')
        .replaceAllMapped(
          RegExp(r'(##\s+[^\n#*]{2,80})(?=\*\*[A-Za-z])'),
          (match) => '${match.group(1)}\n\n',
        )
        .replaceAllMapped(
          RegExp(r'([^\n])(\d+\.\s+\*\*(?:CO\d+|Unit\s+\d+:))'),
          (match) => '${match.group(1)}\n${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(
            r'(\*\*(?:Course Objective|Pre-requisites|Prerequisites|Course Outcomes|Unit-wise Syllabus|Assessment \/ Evaluation)\*\*)(?=\S)',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}\n',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  Widget _buildHeading(String headingText, double topPadding) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: _buildInlineContent(
        headingText,
        baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 14) + 1.5,
          fontWeight: FontWeight.w800,
          color: headingColor,
          height: 1.4,
        ),
      ),
    );
  }

  _TableBlock? _tryParseTableBlock(List<String> lines, int startIndex) {
    if (startIndex + 1 >= lines.length) return null;

    final headerLine = lines[startIndex].trim();
    final dividerLine = lines[startIndex + 1].trim();
    if (!_looksLikeTableRow(headerLine) || !_looksLikeTableDivider(dividerLine)) {
      return null;
    }

    final headers = _splitTableCells(headerLine);
    if (headers.length < 2) return null;

    final rows = <List<String>>[];
    var rowIndex = startIndex + 2;
    while (rowIndex < lines.length) {
      final rowLine = lines[rowIndex].trim();
      if (rowLine.isEmpty || !_looksLikeTableRow(rowLine)) break;
      final rowCells = _splitTableCells(rowLine);
      if (rowCells.isEmpty) break;
      rows.add(rowCells);
      rowIndex++;
    }

    return _TableBlock(
      headers: headers,
      rows: rows,
      nextIndex: rowIndex,
    );
  }

  bool _looksLikeTableRow(String line) {
    if (!line.contains('|')) return false;
    return _splitTableCells(line).length >= 2;
  }

  bool _looksLikeTableDivider(String line) {
    final cells = _splitTableCells(line);
    if (cells.length < 2) return false;
    final dividerPattern = RegExp(r'^:?-{3,}:?$');
    return cells.every((cell) => dividerPattern.hasMatch(cell.replaceAll(' ', '')));
  }

  List<String> _splitTableCells(String rowLine) {
    var row = rowLine.trim();
    if (row.startsWith('|')) row = row.substring(1);
    if (row.endsWith('|')) row = row.substring(0, row.length - 1);
    final cells = row.split('|').map((cell) => cell.trim()).toList();
    if (cells.length < 2) return <String>[];
    return cells;
  }

  Widget _buildTable(_TableBlock tableBlock) {
    var columnCount = tableBlock.headers.length;
    for (final row in tableBlock.rows) {
      if (row.length > columnCount) {
        columnCount = row.length;
      }
    }

    final borderColor = (baseStyle.color ?? Colors.black).withValues(alpha: 0.2);
    final headerStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: headingColor,
    );

    List<Widget> buildCells(List<String> values, TextStyle cellStyle) {
      return List<Widget>.generate(columnCount, (index) {
        final value = index < values.length ? values[index] : '';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: _buildInlineContent(value, cellStyle),
        );
      });
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 260),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(
              color: borderColor,
              width: 1,
            ),
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: headingColor.withValues(alpha: 0.08),
                ),
                children: buildCells(tableBlock.headers, headerStyle),
              ),
              for (final row in tableBlock.rows)
                TableRow(
                  children: buildCells(row, baseStyle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineContent(String input, TextStyle style) {
    final segments = _splitMathSegments(input);
    if (segments.every((segment) => !segment.isMath)) {
      return SelectableText.rich(_inlineSpan(input, style));
    }

    final blockMathOnly =
        segments.length == 1 &&
        segments.first.isMath &&
        _looksLikeBlockMath(input.trim());
    if (blockMathOnly) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: _buildMathWidget(
            segments.first.value,
            style,
            displayStyle: true,
          ),
        ),
      );
    }

    final children = <InlineSpan>[];
    for (final segment in segments) {
      if (segment.value.isEmpty) continue;
      if (segment.isMath) {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
              child: _buildMathWidget(segment.value, style),
            ),
          ),
        );
      } else {
        children.add(_inlineSpan(segment.value, style));
      }
    }

    return RichText(
      text: TextSpan(style: style, children: children),
      textScaler: TextScaler.noScaling,
    );
  }

  Widget _buildMathWidget(
    String rawExpression,
    TextStyle style, {
    bool displayStyle = false,
  }) {
    final expression = _normalizeMathExpression(rawExpression);
    final fallbackText = _stripMathDelimiters(rawExpression);

    return Math.tex(
      expression,
      mathStyle: displayStyle ? MathStyle.display : MathStyle.text,
      textStyle: style.copyWith(
        color: style.color,
        fontSize: style.fontSize ?? 15,
        height: style.height,
      ),
      onErrorFallback: (FlutterMathException error) => Text(
        fallbackText,
        style: GoogleFonts.robotoMono(
          fontSize: style.fontSize ?? 14,
          height: style.height,
          fontWeight: FontWeight.w600,
          color: (style.color ?? Colors.black).withValues(alpha: 0.72),
        ),
      ),
    );
  }

  String _normalizeMathExpression(String rawExpression) {
    var cleaned = _stripMathDelimiters(rawExpression)
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAllMapped(
          RegExp(r'(?<!\\)(sin|cos|tan|log|ln|lim)\b'),
          (match) => '\\${match.group(1)}',
        )
        .replaceAll('→', r'\rightarrow ')
        .replaceAll('≤', r'\le ')
        .replaceAll('≥', r'\ge ')
        .replaceAll('×', r'\times ')
        .replaceAll('÷', r'\div ')
        .replaceAll('−', '-')
        .replaceAll('π', r'\pi ')
        .replaceAll('α', r'\alpha ')
        .replaceAll('β', r'\beta ')
        .replaceAll('θ', r'\theta ')
        .replaceAll('λ', r'\lambda ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) {
      cleaned = rawExpression.trim();
    }
    return cleaned;
  }

  String _stripMathDelimiters(String rawExpression) {
    final trimmed = rawExpression.trim();
    if (trimmed.startsWith(r'$$') && trimmed.endsWith(r'$$')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith(r'$') && trimmed.endsWith(r'$')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    if (trimmed.startsWith(r'\[') && trimmed.endsWith(r'\]')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith(r'\(') && trimmed.endsWith(r'\)')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    return trimmed;
  }

  bool _looksLikeBlockMath(String input) {
    return input.startsWith(r'$$') ||
        input.startsWith(r'\[') ||
        (input.startsWith(r'$') && input.endsWith(r'$'));
  }

  List<_MathSegment> _splitMathSegments(String input) {
    final segments = <_MathSegment>[];
    var cursor = 0;

    for (final match in _mathSegmentPattern.allMatches(input)) {
      if (match.start > cursor) {
        segments.add(
          _MathSegment(
            isMath: false,
            value: input.substring(cursor, match.start),
          ),
        );
      }
      segments.add(
        _MathSegment(
          isMath: true,
          value: match.group(0) ?? '',
        ),
      );
      cursor = match.end;
    }

    if (cursor < input.length) {
      segments.add(
        _MathSegment(
          isMath: false,
          value: input.substring(cursor),
        ),
      );
    }

    if (segments.isEmpty) {
      return <_MathSegment>[
        _MathSegment(isMath: false, value: input),
      ];
    }

    return segments;
  }

  TextSpan _inlineSpan(String input, TextStyle style, {int depth = 0}) {
    if (depth >= _maxInlineDepth) {
      return TextSpan(text: input, style: style);
    }

    final spans = <InlineSpan>[];
    final matcher = RegExp(
      r'(\*\*[^*\n]+\*\*)|(_[^_\n]+_)|(?<!\*)\*([^*\n]+)\*(?!\*)',
    );
    var cursor = 0;

    for (final match in matcher.allMatches(input)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: input.substring(cursor, match.start), style: style),
        );
      }

      final token = match.group(0) ?? '';
      if (token.startsWith('**') && token.endsWith('**')) {
        final inner = token.substring(2, token.length - 2);
        spans.add(
          _inlineSpan(
            inner,
            style.copyWith(fontWeight: FontWeight.w800),
            depth: depth + 1,
          ),
        );
      } else if (token.startsWith('_') && token.endsWith('_')) {
        final inner = token.substring(1, token.length - 1);
        spans.add(
          _inlineSpan(
            inner,
            style.copyWith(fontStyle: FontStyle.italic),
            depth: depth + 1,
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          _inlineSpan(
            match.group(3)!,
            style.copyWith(fontStyle: FontStyle.italic),
            depth: depth + 1,
          ),
        );
      }

      cursor = match.end;
    }

    if (cursor < input.length) {
      spans.add(TextSpan(text: input.substring(cursor), style: style));
    }

    return TextSpan(
      style: style,
      text: spans.isEmpty ? input : null,
      children: spans.isEmpty ? null : spans,
    );
  }
}

class _MathSegment {
  final bool isMath;
  final String value;

  const _MathSegment({
    required this.isMath,
    required this.value,
  });
}

class _TableBlock {
  final List<String> headers;
  final List<List<String>> rows;
  final int nextIndex;

  const _TableBlock({
    required this.headers,
    required this.rows,
    required this.nextIndex,
  });
}
