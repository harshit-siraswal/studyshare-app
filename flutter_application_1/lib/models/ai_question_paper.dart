import 'package:flutter/foundation.dart';

class AiQuestionPaperSource {
  final String title;
  final String section;
  final String pages;
  final String note;

  const AiQuestionPaperSource({
    this.title = '',
    this.section = '',
    this.pages = '',
    this.note = '',
  });

  factory AiQuestionPaperSource.fromJson(Map<String, dynamic> json) {
    return AiQuestionPaperSource(
      title: json['title']?.toString() ?? '',
      section: json['section']?.toString() ?? '',
      pages: json['pages']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'title': title, 'section': section, 'pages': pages, 'note': note};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AiQuestionPaperSource &&
            runtimeType == other.runtimeType &&
            title == other.title &&
            section == other.section &&
            pages == other.pages &&
            note == other.note;
  }

  @override
  int get hashCode => Object.hash(title, section, pages, note);
}

class AiQuestionPaperQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final AiQuestionPaperSource source;

  AiQuestionPaperQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
    this.source = const AiQuestionPaperSource(),
  }) {
    if (options.isEmpty) {
      throw ArgumentError('options must not be empty');
    }
    if (correctIndex < 0 || correctIndex >= options.length) {
      throw ArgumentError(
        'Invalid correctIndex=$correctIndex for options length=${options.length}',
      );
    }
  }

  factory AiQuestionPaperQuestion.fromJson(Map<String, dynamic> json) {
    final optionsRaw = json['options'];
    var parsedOptions = <String>[];
    if (optionsRaw is List) {
      parsedOptions = optionsRaw.map((e) => e.toString()).toList();
    }
    if (parsedOptions.isEmpty) {
      parsedOptions = <String>[''];
    }
    final rawCorrectIndex = (json['correctIndex'] as num?)?.toInt() ?? 0;
    final boundedCorrectIndex = rawCorrectIndex.clamp(
      0,
      parsedOptions.length - 1,
    );
    return AiQuestionPaperQuestion(
      question: json['question']?.toString() ?? '',
      options: parsedOptions,
      correctIndex: boundedCorrectIndex,
      explanation: json['explanation']?.toString() ?? '',
      source: json['source'] is Map
          ? AiQuestionPaperSource.fromJson(
              Map<String, dynamic>.from(json['source'] as Map),
            )
          : const AiQuestionPaperSource(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      'options': options,
      'correctIndex': correctIndex,
      'explanation': explanation,
      'source': source.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AiQuestionPaperQuestion &&
            runtimeType == other.runtimeType &&
            question == other.question &&
            listEquals(options, other.options) &&
            correctIndex == other.correctIndex &&
            explanation == other.explanation &&
            source == other.source;
  }

  @override
  int get hashCode => Object.hash(
    question,
    Object.hashAll(options),
    correctIndex,
    explanation,
    source,
  );
}

class AiQuestionPaper {
  final String title;
  final String subject;
  final String semester;
  final String branch;
  final List<String> instructions;
  final List<AiQuestionPaperQuestion> questions;
  final DateTime generatedAt;
  final int pyqCount;

  AiQuestionPaper({
    required this.title,
    required this.subject,
    required this.semester,
    required this.branch,
    required this.instructions,
    required this.questions,
    required this.generatedAt,
    required this.pyqCount,
  });

  factory AiQuestionPaper.fromJson(Map<String, dynamic> json) {
    final rawInstructions = (json['instructions'] as List?) ?? const [];
    final rawQuestions = (json['questions'] as List?) ?? const [];
    final parsedQuestions = <AiQuestionPaperQuestion>[];
    for (var i = 0; i < rawQuestions.length; i++) {
      final item = rawQuestions[i];
      if (item is Map) {
        parsedQuestions.add(
          AiQuestionPaperQuestion.fromJson(Map<String, dynamic>.from(item)),
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
    return AiQuestionPaper(
      title: json['title']?.toString() ?? '',
      subject: json['subject']?.toString() ?? '',
      semester: json['semester']?.toString() ?? '',
      branch: json['branch']?.toString() ?? '',
      instructions: rawInstructions.map((e) => e.toString()).toList(),
      questions: parsedQuestions,
      generatedAt: parsedGeneratedAt ?? generatedAtFallback,
      pyqCount: (json['pyqCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'subject': subject,
      'semester': semester,
      'branch': branch,
      'instructions': instructions,
      'questions': questions.map((q) => q.toJson()).toList(),
      'generatedAt': generatedAt.toIso8601String(),
      'pyqCount': pyqCount,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AiQuestionPaper &&
            runtimeType == other.runtimeType &&
            title == other.title &&
            subject == other.subject &&
            semester == other.semester &&
            branch == other.branch &&
            listEquals(instructions, other.instructions) &&
            listEquals(questions, other.questions) &&
            generatedAt == other.generatedAt &&
            pyqCount == other.pyqCount;
  }

  @override
  int get hashCode => Object.hash(
    title,
    subject,
    semester,
    branch,
    Object.hashAll(instructions),
    Object.hashAll(questions),
    generatedAt,
    pyqCount,
  );
}
