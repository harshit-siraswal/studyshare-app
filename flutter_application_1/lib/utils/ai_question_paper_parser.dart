import 'dart:convert';

import '../models/ai_question_paper.dart';

Map<String, dynamic>? decodeStructuredJsonMap(String raw) {
  if (raw.trim().isEmpty) return null;
  final decoded = _decodeStructuredValue(raw);
  final recovered = _recoverQuestionPaperJson(_stripCodeFence(raw).trim());
  if (decoded is Map) {
    final map = _stringKeyedMap(decoded);
    return recovered == null ? map : <String, dynamic>{...recovered, ...map};
  }
  if (decoded is List) {
    final items = decoded
        .whereType<Map>()
        .map((item) => _stringKeyedMap(item))
        .toList(growable: false);
    if (items.isNotEmpty) {
      final map = <String, dynamic>{'questions': items};
      return recovered == null ? map : <String, dynamic>{...recovered, ...map};
    }
  }
  return recovered;
}

AiQuestionPaper? parseAiQuestionPaper({
  required String rawResponse,
  required String semester,
  required String branch,
  required String fallbackSubject,
  required int contextResourceCount,
}) {
  final payload = _extractQuestionPayload(rawResponse);
  final questions = <AiQuestionPaperQuestion>[];
  var subject = fallbackSubject.trim();
  var title = 'Generated Question Paper';
  var instructions = <String>[];

  if (payload != null) {
    final metadata = payload.metadata;
    final parsedSubject = _firstNonEmptyString([
      metadata['subject'],
      metadata['topic'],
      metadata['course'],
    ]);
    if (parsedSubject != null) {
      subject = parsedSubject;
    }

    final parsedTitle = _firstNonEmptyString([
      metadata['title'],
      metadata['paper_title'],
      metadata['name'],
    ]);
    if (parsedTitle != null) {
      title = parsedTitle;
    }

    instructions = _extractInstructionList(
      metadata['instructions'] ?? metadata['rules'] ?? metadata['guidelines'],
    );

    for (final item in payload.items) {
      final parsed = _parseQuestionItem(item);
      if (parsed != null) {
        questions.add(parsed);
      }
    }
  }

  if (questions.isEmpty) {
    questions.addAll(_parsePlainTextMcqs(rawResponse));
  }
  if (questions.isEmpty) return null;
  if (subject.isEmpty) {
    subject = 'General';
  }

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

class _QuestionPayload {
  final Map<String, dynamic> metadata;
  final List<dynamic> items;

  const _QuestionPayload({required this.metadata, required this.items});
}

_QuestionPayload? _extractQuestionPayload(String raw) {
  final recovered = decodeStructuredJsonMap(raw);
  if (recovered != null) {
    return _extractQuestionPayloadFromValue(recovered);
  }
  final decoded = _decodeStructuredValue(raw);
  return _extractQuestionPayloadFromValue(decoded);
}

_QuestionPayload? _extractQuestionPayloadFromValue(dynamic raw) {
  if (raw is List) {
    return _QuestionPayload(metadata: const <String, dynamic>{}, items: raw);
  }
  if (raw is! Map) return null;

  final map = _stringKeyedMap(raw);
  final directList = _extractQuestionList(map);
  if (directList != null) {
    return _QuestionPayload(metadata: map, items: directList);
  }

  for (final value in map.values) {
    final nested = _extractQuestionPayloadFromValue(value);
    if (nested != null) {
      return _QuestionPayload(
        metadata: <String, dynamic>{...nested.metadata, ...map},
        items: nested.items,
      );
    }
  }

  return null;
}

List<dynamic>? _extractQuestionList(Map<String, dynamic> map) {
  const preferredKeys = <String>[
    'questions',
    'quiz',
    'quizzes',
    'mcqs',
    'items',
    'data',
    'result',
    'results',
  ];

  for (final key in preferredKeys) {
    final value = map[key];
    if (value is List) return value;
  }

  if (map.length == 1) {
    final value = map.values.first;
    if (value is List) return value;
  }

  return null;
}

AiQuestionPaperQuestion? _parseQuestionItem(dynamic raw) {
  final decoded = _decodeStructuredValue(raw);
  if (decoded is! Map) return null;

  final item = _stringKeyedMap(decoded);
  final questionRaw = _firstNonEmptyString([
    item['question'],
    item['question_text'],
    item['text'],
    item['prompt'],
    item['query'],
    item['title'],
  ]);
  final question = questionRaw == null
      ? null
      : _sanitizeQuestionPaperText(questionRaw);
  if (question == null || question.isEmpty) return null;

  final options = _extractOptionList(
    item['options'] ??
        item['choices'] ??
        item['answers'] ??
        item['mcq_options'] ??
        item['alternatives'],
  );
  if (options.length < 2) return null;

  final explicitCorrectIndex = _resolveExplicitCorrectIndex(
    item: item,
    optionsLength: options.length,
  );
  final correctIndex =
      explicitCorrectIndex ??
      _resolveAnswerIndex(
        answer:
            item['answer'] ??
            item['correct'] ??
            item['correct_answer'] ??
            item['correctOption'] ??
            item['correct_option'] ??
            item['solution'],
        options: options,
      );

  final source = _parseQuestionSource(item['source']);
  return AiQuestionPaperQuestion(
    question: question,
    options: options,
    correctIndex: correctIndex,
    explanation: _sanitizeQuestionPaperText(
      item['explanation']?.toString() ?? '',
    ),
    source: source,
  );
}

AiQuestionPaperSource _parseQuestionSource(dynamic raw) {
  final decoded = _decodeStructuredValue(raw);
  if (decoded is Map) {
    final item = _stringKeyedMap(decoded);
    return AiQuestionPaperSource(
      title: _sanitizeQuestionPaperText(item['title']?.toString() ?? ''),
      section: _sanitizeQuestionPaperText(item['section']?.toString() ?? ''),
      pages: _sanitizeQuestionPaperText(item['pages']?.toString() ?? ''),
      note: item['note']?.toString() ?? '',
    );
  }
  return AiQuestionPaperSource(note: raw?.toString() ?? '');
}

List<String> _extractInstructionList(dynamic raw) {
  final decoded = _decodeStructuredValue(raw);
  if (decoded is List) {
    return decoded
        .map((item) => _extractInstructionText(item))
        .whereType<String>()
        .toList(growable: false);
  }
  final single = _extractInstructionText(decoded);
  return single == null ? const <String>[] : <String>[single];
}

String? _extractInstructionText(dynamic raw) {
  final decoded = _decodeStructuredValue(raw);
  if (decoded is Map) {
    return _firstNonEmptyString([
      decoded['text'],
      decoded['instruction'],
      decoded['value'],
    ]);
  }
  if (decoded == null) return null;
  final value = _sanitizeQuestionPaperText(decoded.toString());
  return value.isEmpty ? null : value;
}

List<String> _extractOptionList(dynamic raw) {
  final decoded = _decodeStructuredValue(raw);
  final options = <String>[];

  if (decoded is List) {
    for (final item in decoded) {
      final option = _extractOptionText(item);
      if (option != null) {
        options.add(option);
      }
    }
  } else if (decoded is Map) {
    final item = _stringKeyedMap(decoded);
    const orderedKeys = <String>[
      'A',
      'B',
      'C',
      'D',
      'a',
      'b',
      'c',
      'd',
      '1',
      '2',
      '3',
      '4',
    ];
    for (final key in orderedKeys) {
      final option = _extractOptionText(item[key]);
      if (option != null) {
        options.add(option);
      }
    }
    if (options.length < 2) {
      for (final value in item.values) {
        final option = _extractOptionText(value);
        if (option != null) {
          options.add(option);
        }
      }
    }
  } else if (decoded is String) {
    for (final line in decoded.split(RegExp(r'[\r\n]+'))) {
      final option = _normalizeOptionText(line);
      if (option != null) {
        options.add(option);
      }
    }
  }

  return options.toSet().toList(growable: false);
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
  final trimmed = _sanitizeQuestionPaperText(raw);
  if (trimmed.isEmpty) return null;

  final cleaned = trimmed
      .replaceFirst(RegExp(r'^[A-Za-z][\)\.\:\-]\s*'), '')
      .replaceFirst(RegExp(r'^\d+[\)\.\:\-]\s*'), '')
      .replaceFirst(RegExp(r'^[-*•]\s*'), '')
      .trim();

  return cleaned.isEmpty ? null : cleaned;
}

String _sanitizeQuestionPaperText(String raw) {
  return raw
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), ' ')
      .replaceAll(RegExp(r'[①-⑳⓪❶-❿⓵-⓾]'), ' ')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s*[|]+\s*'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

String? _firstNonEmptyString(List<dynamic> candidates) {
  for (final candidate in candidates) {
    if (candidate == null) continue;
    final value = candidate.toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

int? _resolveExplicitCorrectIndex({
  required Map<String, dynamic> item,
  required int optionsLength,
}) {
  if (optionsLength <= 0) return 0;
  final raw = item['correctIndex'] ?? item['correct_index'];
  if (raw == null) return null;
  final parsed = int.tryParse(raw.toString().trim());
  if (parsed == null) return null;
  return parsed.clamp(0, optionsLength - 1);
}

int _resolveAnswerIndex({
  required dynamic answer,
  required List<String> options,
}) {
  if (options.isEmpty) return 0;
  final answerText = answer?.toString().trim() ?? '';
  if (answerText.isEmpty) return 0;

  final upper = answerText.toUpperCase();
  final letterPatterns = <RegExp>[
    RegExp(r'^[A-Z]$'),
    RegExp(r'^(?:OPTION|CHOICE)\s+([A-Z])$'),
    RegExp(r'^([A-Z])[\)\.\:\-]'),
  ];
  for (final pattern in letterPatterns) {
    final match = pattern.firstMatch(upper);
    final token = match?.groupCount == 1 ? match?.group(1) : match?.group(0);
    if (token == null || token.isEmpty) continue;
    final index = token.codeUnitAt(0) - 65;
    if (index >= 0 && index < options.length) {
      return index;
    }
  }

  final numericMatch = RegExp(r'\b(\d+)\b').firstMatch(answerText);
  final numeric = int.tryParse(numericMatch?.group(1) ?? '');
  if (numeric != null && numeric >= 1 && numeric <= options.length) {
    return numeric - 1;
  }
  if (numeric != null && numeric >= 0 && numeric < options.length) {
    return numeric;
  }

  final normalizedAnswer = _normalizeOptionText(answerText)?.toLowerCase();
  if (normalizedAnswer != null) {
    for (var i = 0; i < options.length; i++) {
      if (options[i].trim().toLowerCase() == normalizedAnswer) {
        return i;
      }
    }
  }

  return 0;
}

List<AiQuestionPaperQuestion> _parsePlainTextMcqs(String raw) {
  final lines = raw.split('\n');
  final questions = <AiQuestionPaperQuestion>[];

  String currentQuestion = '';
  final currentOptions = <String>[];
  var currentAnswer = 0;
  var currentExplanation = '';

  void flush() {
    if (currentQuestion.trim().isEmpty || currentOptions.length < 2) return;
    questions.add(
      AiQuestionPaperQuestion(
        question: currentQuestion.trim(),
        options: List<String>.from(currentOptions),
        correctIndex: currentAnswer.clamp(0, currentOptions.length - 1),
        explanation: currentExplanation,
      ),
    );
    currentQuestion = '';
    currentOptions.clear();
    currentAnswer = 0;
    currentExplanation = '';
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final questionMatch = RegExp(r'^\d+[\).]\s*(.+)$').firstMatch(line);
    if (questionMatch != null) {
      flush();
      currentQuestion = questionMatch.group(1)?.trim() ?? '';
      continue;
    }

    final optionMatch = RegExp(
      r'^(?:[A-Da-d]|[1-4])[\).:\-]\s*(.+)$',
    ).firstMatch(line);
    if (optionMatch != null) {
      final option = _normalizeOptionText(optionMatch.group(1) ?? '');
      if (option != null) {
        currentOptions.add(option);
      }
      continue;
    }

    final answerMatch = RegExp(
      r'^(?:answer|correct)\s*[:\-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (answerMatch != null) {
      currentAnswer = _resolveAnswerIndex(
        answer: answerMatch.group(1) ?? '',
        options: currentOptions,
      );
      continue;
    }

    final explanationMatch = RegExp(
      r'^(?:explanation|reason)\s*[:\-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (explanationMatch != null) {
      currentExplanation = explanationMatch.group(1)?.trim() ?? '';
      continue;
    }

    if (currentQuestion.isNotEmpty && currentOptions.isEmpty) {
      currentQuestion = '$currentQuestion $line'.trim();
    }
  }

  flush();
  return questions;
}

dynamic _decodeStructuredValue(dynamic raw) {
  dynamic current = raw;
  for (var i = 0; i < 3; i++) {
    if (current is! String) return current;
    final trimmed = _stripCodeFence(current).trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      final decoded = _tryDecodeJson(trimmed);
      if (decoded != null) {
        current = decoded;
        continue;
      }
    }

    final firstObject = trimmed.indexOf('{');
    final lastObject = trimmed.lastIndexOf('}');
    if (firstObject != -1 && lastObject > firstObject) {
      final objectSlice = trimmed.substring(firstObject, lastObject + 1);
      final decoded = _tryDecodeJson(objectSlice);
      if (decoded != null) {
        current = decoded;
        continue;
      }
    }

    final firstArray = trimmed.indexOf('[');
    final lastArray = trimmed.lastIndexOf(']');
    if (firstArray != -1 && lastArray > firstArray) {
      final arraySlice = trimmed.substring(firstArray, lastArray + 1);
      final decoded = _tryDecodeJson(arraySlice);
      if (decoded != null) {
        current = decoded;
        continue;
      }
    }

    return trimmed;
  }
  return current;
}

String _stripCodeFence(String raw) {
  final trimmed = raw.trim();
  final match = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return match?.group(1) ?? trimmed;
}

dynamic _tryDecodeJson(String source) {
  try {
    return jsonDecode(source);
  } catch (_) {
    final normalized = _escapeMultilineJsonStrings(source);
    if (normalized != source) {
      try {
        return jsonDecode(normalized);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

String _escapeMultilineJsonStrings(String source) {
  final buffer = StringBuffer();
  var inString = false;
  var escaped = false;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (inString) {
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        buffer.write(char);
        escaped = true;
        continue;
      }
      if (char == '"') {
        buffer.write(char);
        inString = false;
        continue;
      }
      if (char == '\r') {
        continue;
      }
      if (char == '\n') {
        buffer.write(r'\n');
        continue;
      }
      buffer.write(char);
      continue;
    }

    buffer.write(char);
    if (char == '"') {
      inString = true;
    }
  }

  return buffer.toString();
}

Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> raw) {
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, dynamic>? _recoverQuestionPaperJson(String source) {
  final questions = _extractQuestionObjectsFromPartialJson(source);
  if (questions.isEmpty) return null;

  final recovered = <String, dynamic>{'questions': questions};
  final title = _extractJsonStringField(source, 'title');
  final subject = _extractJsonStringField(source, 'subject');
  final instructions = _extractJsonStringArrayField(source, 'instructions');
  if (title != null) recovered['title'] = title;
  if (subject != null) recovered['subject'] = subject;
  if (instructions.isNotEmpty) recovered['instructions'] = instructions;
  return recovered;
}

List<Map<String, dynamic>> _extractQuestionObjectsFromPartialJson(
  String source,
) {
  final questionsMatch = RegExp(
    '"questions"\\s*:\\s*\\[',
    caseSensitive: false,
  ).firstMatch(source);
  if (questionsMatch == null) return const <Map<String, dynamic>>[];

  final parsed = <Map<String, dynamic>>[];
  var cursor = questionsMatch.end;
  while (cursor < source.length) {
    final char = source[cursor];
    if (char == ']') break;
    if (char != '{') {
      cursor++;
      continue;
    }

    final end = _findBalancedObjectEnd(source, cursor);
    if (end == -1) break;

    final objectSlice = source.substring(cursor, end + 1);
    final decoded = _tryDecodeJson(objectSlice);
    if (decoded is Map) {
      parsed.add(_stringKeyedMap(decoded));
    }
    cursor = end + 1;
  }

  return parsed;
}

int _findBalancedObjectEnd(String source, int startIndex) {
  if (startIndex < 0 ||
      startIndex >= source.length ||
      source[startIndex] != '{') {
    return -1;
  }

  var depth = 0;
  var inString = false;
  var escaped = false;

  for (var i = startIndex; i < source.length; i++) {
    final char = source[i];
    if (inString) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = false;
      }
      continue;
    }

    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == '{') {
      depth++;
      continue;
    }
    if (char == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }

  return -1;
}

String? _extractJsonStringField(String source, String field) {
  final pattern = RegExp(
    '"${RegExp.escape(field)}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(source);
  final raw = match?.group(1);
  if (raw == null) return null;

  final decoded = _tryDecodeJson('"$raw"');
  if (decoded is String && decoded.trim().isNotEmpty) {
    return decoded.trim();
  }
  return raw.trim().isEmpty ? null : raw.trim();
}

List<String> _extractJsonStringArrayField(String source, String field) {
  final fieldMatch = RegExp(
    '"${RegExp.escape(field)}"\\s*:\\s*\\[',
    caseSensitive: false,
  ).firstMatch(source);
  if (fieldMatch == null) return const <String>[];

  final values = <String>[];
  var inString = false;
  var escaped = false;
  final buffer = StringBuffer();

  for (var i = fieldMatch.end; i < source.length; i++) {
    final char = source[i];
    if (inString) {
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        final value = buffer.toString().trim();
        if (value.isNotEmpty) {
          values.add(value);
        }
        buffer.clear();
        inString = false;
        continue;
      }
      buffer.write(char);
      continue;
    }

    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == ']') {
      break;
    }
  }

  return values;
}
