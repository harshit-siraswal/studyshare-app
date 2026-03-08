import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AiFormattedText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final Color bulletColor;
  final Color headingColor;
  /// When true, lines ≤ 8 words ending with ":" are treated as headings.
  final bool detectColonHeadings;

  const AiFormattedText({
    super.key,
    required this.text,
    required this.baseStyle,
    required this.bulletColor,
    required this.headingColor,
    this.detectColonHeadings = true,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = text.replaceAll('\r', '');
    final lines = normalized.split('\n');
    final widgets = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final trimmed = rawLine.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      final headingMatch = RegExp(r'^#{1,3}\s+(.+)$').firstMatch(trimmed);
      final bulletMatch = RegExp(r'^([-*•]|\d+[.)])\s+(.+)$').firstMatch(trimmed);

      // Colon-heading: only when enabled, ≤ 8 words, and starts with an
      // uppercase letter that isn't a common sentence-starter.
      final isColonHeading = detectColonHeadings &&
          headingMatch == null &&
          trimmed.endsWith(':') &&
          trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).length <= 8 &&
          RegExp(r'^[A-Z]').hasMatch(trimmed) &&
          !RegExp(r'^(Please|Note|For|To|If|When|This|See|Do|Use)\b', caseSensitive: true)
              .hasMatch(trimmed);

      final looksLikeHeading = headingMatch != null || isColonHeading;

      if (looksLikeHeading) {
        final headingText = headingMatch?.group(1)?.trim() ?? trimmed.replaceFirst(RegExp(r':\s*$'), '');
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: SelectableText.rich(
              _inlineSpan(
                headingText,
                baseStyle.copyWith(
                  fontSize: (baseStyle.fontSize ?? 14) + 1.5,
                  fontWeight: FontWeight.w800,
                  color: headingColor,
                  height: 1.4,
                ),
              ),
            ),
          ),
        );
        continue;
      }

      if (bulletMatch != null) {
        final marker = bulletMatch.group(1)?.trim() ?? '•';
        final body = bulletMatch.group(2)?.trim() ?? '';
        final isNumericMarker = RegExp(r'^\d').hasMatch(marker);

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
                Expanded(
                  child: SelectableText.rich(_inlineSpan(body, baseStyle)),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      widgets.add(SelectableText.rich(_inlineSpan(trimmed, baseStyle)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  static const int _maxInlineDepth = 5;

  TextSpan _inlineSpan(String input, TextStyle style, {int depth = 0}) {
    if (depth >= _maxInlineDepth) {
      return TextSpan(text: input, style: style);
    }
    final spans = <InlineSpan>[];
    // Uses a positive lookbehind for single-star italic: match **bold**,
    // _italic_, or a single *italic* that isn't part of **.
    final matcher = RegExp(
      r'(\*\*[^*]+\*\*)'        // bold
      r'|(_[^_]+_)'             // underscore italic
      r'|(?:^|(?<=\s))\*([^*]+)\*(?=[^*]|$)', // single-star italic
    );
    var cursor = 0;

    for (final match in matcher.allMatches(input)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: input.substring(cursor, match.start), style: style));
      }

      final token = match.group(0) ?? '';
      if (token.startsWith('**') && token.endsWith('**')) {
        // Bold — recursively parse inner content for nested italic.
        final inner = token.substring(2, token.length - 2);
        spans.add(
          _inlineSpan(inner, style.copyWith(fontWeight: FontWeight.w800), depth: depth + 1),
        );
      } else if (token.startsWith('_') && token.endsWith('_')) {
        final inner = token.substring(1, token.length - 1);
        spans.add(
          _inlineSpan(inner, style.copyWith(fontStyle: FontStyle.italic), depth: depth + 1),
        );
      } else if (match.group(3) != null) {
        // Single-star italic via capture group 3.
        final inner = match.group(3)!;
        spans.add(
          _inlineSpan(inner, style.copyWith(fontStyle: FontStyle.italic), depth: depth + 1),
        );
      }

      cursor = match.end;
    }

    if (cursor < input.length) {
      spans.add(TextSpan(text: input.substring(cursor), style: style));
    }

    return TextSpan(children: spans.isNotEmpty ? spans : null, text: spans.isEmpty ? input : null, style: style);
  }
}
