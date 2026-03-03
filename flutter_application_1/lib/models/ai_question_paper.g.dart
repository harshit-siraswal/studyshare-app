// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_question_paper.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AiQuestionPaperSource _$AiQuestionPaperSourceFromJson(
  Map<String, dynamic> json,
) => _AiQuestionPaperSource(
  title: json['title'] as String? ?? '',
  section: json['section'] as String? ?? '',
  pages: json['pages'] as String? ?? '',
  note: json['note'] as String? ?? '',
);

Map<String, dynamic> _$AiQuestionPaperSourceToJson(
  _AiQuestionPaperSource instance,
) => <String, dynamic>{
  'title': instance.title,
  'section': instance.section,
  'pages': instance.pages,
  'note': instance.note,
};

_AiQuestionPaperQuestion _$AiQuestionPaperQuestionFromJson(
  Map<String, dynamic> json,
) => _AiQuestionPaperQuestion(
  question: json['question'] as String,
  options: (json['options'] as List<dynamic>).map((e) => e as String).toList(),
  correctIndex: (json['correctIndex'] as num).toInt(),
  explanation: json['explanation'] as String? ?? '',
  source: json['source'] == null
      ? const AiQuestionPaperSource()
      : AiQuestionPaperSource.fromJson(json['source'] as Map<String, dynamic>),
);

Map<String, dynamic> _$AiQuestionPaperQuestionToJson(
  _AiQuestionPaperQuestion instance,
) => <String, dynamic>{
  'question': instance.question,
  'options': instance.options,
  'correctIndex': instance.correctIndex,
  'explanation': instance.explanation,
  'source': instance.source,
};

_AiQuestionPaper _$AiQuestionPaperFromJson(Map<String, dynamic> json) =>
    _AiQuestionPaper(
      title: json['title'] as String,
      subject: json['subject'] as String,
      semester: json['semester'] as String,
      branch: json['branch'] as String,
      instructions: (json['instructions'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      questions: (json['questions'] as List<dynamic>)
          .map(
            (e) => AiQuestionPaperQuestion.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      pyqCount: (json['pyqCount'] as num).toInt(),
    );

Map<String, dynamic> _$AiQuestionPaperToJson(_AiQuestionPaper instance) =>
    <String, dynamic>{
      'title': instance.title,
      'subject': instance.subject,
      'semester': instance.semester,
      'branch': instance.branch,
      'instructions': instance.instructions,
      'questions': instance.questions,
      'generatedAt': instance.generatedAt.toIso8601String(),
      'pyqCount': instance.pyqCount,
    };
