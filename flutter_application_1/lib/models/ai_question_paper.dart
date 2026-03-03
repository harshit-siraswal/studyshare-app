import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_question_paper.freezed.dart';
part 'ai_question_paper.g.dart';

@freezed
abstract class AiQuestionPaperSource with _$AiQuestionPaperSource {
  const factory AiQuestionPaperSource({
    @Default('') String title,
    @Default('') String section,
    @Default('') String pages,
    @Default('') String note,
  }) = _AiQuestionPaperSource;

  factory AiQuestionPaperSource.fromJson(Map<String, dynamic> json) =>
      _$AiQuestionPaperSourceFromJson(_normalizeSourceJson(json));

  static Map<String, dynamic> _normalizeSourceJson(Map<String, dynamic> json) {
    return {
      'title': json['title']?.toString() ?? '',
      'section': json['section']?.toString() ?? '',
      'pages': json['pages']?.toString() ?? '',
      'note': json['note']?.toString() ?? '',
    };
  }
}

@freezed
abstract class AiQuestionPaperQuestion with _$AiQuestionPaperQuestion {
  @Assert('options.isNotEmpty', 'options must not be empty')
  @Assert(
    'correctIndex >= 0 && correctIndex < options.length',
    'Invalid correctIndex for options length',
  )
  factory AiQuestionPaperQuestion({
    required String question,
    required List<String> options,
    required int correctIndex,
    @Default('') String explanation,
    @Default(AiQuestionPaperSource()) AiQuestionPaperSource source,
  }) = _AiQuestionPaperQuestion;

  factory AiQuestionPaperQuestion.fromJson(Map<String, dynamic> json) =>
      _$AiQuestionPaperQuestionFromJson(_normalizeQuestionJson(json));

  static Map<String, dynamic> _normalizeQuestionJson(
    Map<String, dynamic> json,
  ) {
    final optionsRaw = json['options'];
    var parsedOptions = <String>[];
    if (optionsRaw is List) {
      parsedOptions = optionsRaw
          .map((e) => e?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    }
    if (parsedOptions.isEmpty) {
      throw FormatException(
        'AiQuestionPaperQuestion.fromJson: missing/empty options for '
        'question "${json['question']}". Payload: $json',
      );
    }

    final rawCorrectIndex = (json['correctIndex'] as num?)?.toInt() ?? 0;
    final boundedCorrectIndex = rawCorrectIndex.clamp(
      0,
      parsedOptions.length - 1,
    );

    final sourceRaw = json['source'];
    final parsedSource = sourceRaw is Map
        ? AiQuestionPaperSource.fromJson(Map<String, dynamic>.from(sourceRaw))
        : const AiQuestionPaperSource();

    return {
      'question': json['question']?.toString() ?? '',
      'options': parsedOptions,
      'correctIndex': boundedCorrectIndex,
      'explanation': json['explanation']?.toString() ?? '',
      'source': parsedSource.toJson(),
    };
  }
}

@freezed
abstract class AiQuestionPaper with _$AiQuestionPaper {
  const factory AiQuestionPaper({
    required String title,
    required String subject,
    required String semester,
    required String branch,
    required List<String> instructions,
    required List<AiQuestionPaperQuestion> questions,
    required DateTime generatedAt,
    required int pyqCount,
  }) = _AiQuestionPaper;

  factory AiQuestionPaper.fromJson(Map<String, dynamic> json) =>
      _$AiQuestionPaperFromJson(_normalizePaperJson(json));

  static Map<String, dynamic> _normalizePaperJson(Map<String, dynamic> json) {
    final rawInstructions = (json['instructions'] as List?) ?? const [];
    final rawQuestions = (json['questions'] as List?) ?? const [];
    final parsedInstructions = <String>[];
    final parsedQuestions = <Map<String, dynamic>>[];

    for (var i = 0; i < rawInstructions.length; i++) {
      final item = rawInstructions[i];
      if (item is String) {
        final instruction = item.trim();
        if (instruction.isNotEmpty) {
          parsedInstructions.add(instruction);
        }
        continue;
      }
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final candidate = map['text'] ?? map['instruction'] ?? map['value'];
        final instruction = candidate?.toString().trim() ?? '';
        if (instruction.isNotEmpty) {
          parsedInstructions.add(instruction);
        } else {
          debugPrint(
            'AiQuestionPaper.fromJson ignored malformed instruction '
            'at index $i: $item',
          );
        }
        continue;
      }
      debugPrint(
        'AiQuestionPaper.fromJson ignored non-string instruction '
        'at index $i: $item',
      );
    }

    for (var i = 0; i < rawQuestions.length; i++) {
      final item = rawQuestions[i];
      if (item is Map) {
        parsedQuestions.add(
          AiQuestionPaperQuestion._normalizeQuestionJson(
            Map<String, dynamic>.from(item),
          ),
        );
      } else {
        debugPrint(
          'AiQuestionPaper.fromJson ignored malformed question '
          'at index $i: $item',
        );
      }
    }

    final generatedAtFallback = DateTime.fromMillisecondsSinceEpoch(
      0,
      isUtc: true,
    );
    final generatedAtRaw = json['generatedAt']?.toString();
    final parsedGeneratedAt = generatedAtRaw == null
        ? null
        : DateTime.tryParse(generatedAtRaw);
    if (generatedAtRaw != null && parsedGeneratedAt == null) {
      debugPrint(
        'AiQuestionPaper.fromJson invalid generatedAt value: $generatedAtRaw',
      );
    }

    return {
      'title': json['title']?.toString() ?? '',
      'subject': json['subject']?.toString() ?? '',
      'semester': json['semester']?.toString() ?? '',
      'branch': json['branch']?.toString() ?? '',
      'instructions': parsedInstructions,
      'questions': parsedQuestions,
      'generatedAt': (parsedGeneratedAt ?? generatedAtFallback)
          .toIso8601String(),
      'pyqCount': (json['pyqCount'] as num?)?.toInt() ?? 0,
    };
  }
}
