import 'package:flutter/foundation.dart';

enum StepStatus { pending, inProgress, completed, needHelp, failed }

enum AnswerOrigin { notesOnly, notesPlusWeb, webOnly, insufficientNotes }

enum SourceBadge { notes, web, video }

extension StepStatusX on StepStatus {
  String get wireValue => switch (this) {
    StepStatus.pending => 'pending',
    StepStatus.inProgress => 'in-progress',
    StepStatus.completed => 'completed',
    StepStatus.needHelp => 'need-help',
    StepStatus.failed => 'failed',
  };

  static StepStatus fromWireValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'in-progress':
      case 'in_progress':
        return StepStatus.inProgress;
      case 'completed':
        return StepStatus.completed;
      case 'need-help':
      case 'need_help':
        return StepStatus.needHelp;
      case 'failed':
        return StepStatus.failed;
      case 'pending':
      default:
        return StepStatus.pending;
    }
  }
}

extension AnswerOriginX on AnswerOrigin {
  String get wireValue => switch (this) {
    AnswerOrigin.notesOnly => 'notes_only',
    AnswerOrigin.notesPlusWeb => 'notes_plus_web',
    AnswerOrigin.webOnly => 'web_only',
    AnswerOrigin.insufficientNotes => 'insufficient_notes',
  };

  static AnswerOrigin? fromWireValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'notes_only':
        return AnswerOrigin.notesOnly;
      case 'notes_plus_web':
        return AnswerOrigin.notesPlusWeb;
      case 'web_only':
        return AnswerOrigin.webOnly;
      case 'insufficient_notes':
        return AnswerOrigin.insufficientNotes;
      default:
        return null;
    }
  }
}

extension SourceBadgeX on SourceBadge {
  String get wireValue => switch (this) {
    SourceBadge.notes => 'notes',
    SourceBadge.web => 'web',
    SourceBadge.video => 'video',
  };

  static SourceBadge fromWireValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'web':
        return SourceBadge.web;
      case 'video':
      case 'youtube':
        return SourceBadge.video;
      case 'notes':
      default:
        return SourceBadge.notes;
    }
  }
}

@immutable
class PlanSource {
  const PlanSource({
    required this.title,
    required this.badge,
    this.page,
    this.timestamp,
    this.url,
    this.fileId,
    this.subject,
  });

  final String title;
  final SourceBadge badge;
  final int? page;
  final String? timestamp;
  final String? url;
  final String? fileId;
  final String? subject;

  bool get isClickable =>
      (badge == SourceBadge.notes && (fileId?.trim().isNotEmpty ?? false)) ||
      (badge != SourceBadge.notes && (url?.trim().isNotEmpty ?? false));

  PlanSource copyWith({
    String? title,
    SourceBadge? badge,
    int? page,
    String? timestamp,
    String? url,
    String? fileId,
    String? subject,
  }) {
    return PlanSource(
      title: title ?? this.title,
      badge: badge ?? this.badge,
      page: page ?? this.page,
      timestamp: timestamp ?? this.timestamp,
      url: url ?? this.url,
      fileId: fileId ?? this.fileId,
      subject: subject ?? this.subject,
    );
  }

  factory PlanSource.fromJson(Map<String, dynamic> json) {
    final rawPage = json['page'];
    return PlanSource(
      title: json['title']?.toString() ?? 'Source',
      badge: SourceBadgeX.fromWireValue(json['badge']?.toString()),
      page: rawPage is int ? rawPage : int.tryParse(rawPage?.toString() ?? ''),
      timestamp: json['timestamp']?.toString(),
      url: json['url']?.toString(),
      fileId: json['file_id']?.toString(),
      subject: json['subject']?.toString(),
    );
  }

  /// Compact representation for local chat persistence.
  Map<String, dynamic> toCompactJson() {
    return {
      'title': title,
      'badge': badge.wireValue,
      if (page != null) 'page': page,
      if (fileId != null && fileId!.trim().isNotEmpty) 'file_id': fileId,
    };
  }
}

@immutable
class PlanSubstep {
  const PlanSubstep({
    required this.id,
    required this.title,
    required this.status,
    this.detail,
    this.sources = const [],
  });

  final String id;
  final String title;
  final String? detail;
  final StepStatus status;
  final List<PlanSource> sources;

  PlanSubstep copyWith({
    String? id,
    String? title,
    String? detail,
    StepStatus? status,
    List<PlanSource>? sources,
  }) {
    return PlanSubstep(
      id: id ?? this.id,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      status: status ?? this.status,
      sources: sources ?? this.sources,
    );
  }

  factory PlanSubstep.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    return PlanSubstep(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString(),
      status: StepStatusX.fromWireValue(json['status']?.toString()),
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (entry) =>
                      PlanSource.fromJson(Map<String, dynamic>.from(entry)),
                )
                .toList(growable: false)
          : const [],
    );
  }

  /// Compact representation for local chat persistence.
  Map<String, dynamic> toCompactJson() {
    return {
      'id': id,
      'title': title,
      'status': status.wireValue,
      if (sources.isNotEmpty)
        'sources': sources.map((source) => source.toCompactJson()).toList(),
    };
  }
}

@immutable
class PlanStep {
  const PlanStep({
    required this.id,
    required this.title,
    required this.status,
    this.description,
    this.substeps = const [],
    this.sources = const [],
  });

  final String id;
  final String title;
  final String? description;
  final StepStatus status;
  final List<PlanSubstep> substeps;
  final List<PlanSource> sources;

  bool get hasDetails =>
      (description?.trim().isNotEmpty ?? false) ||
      substeps.isNotEmpty ||
      sources.isNotEmpty;

  PlanStep copyWith({
    String? id,
    String? title,
    String? description,
    StepStatus? status,
    List<PlanSubstep>? substeps,
    List<PlanSource>? sources,
  }) {
    return PlanStep(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      substeps: substeps ?? this.substeps,
      sources: sources ?? this.sources,
    );
  }

  factory PlanStep.fromJson(Map<String, dynamic> json) {
    final rawSubsteps = json['substeps'];
    final rawSources = json['sources'];
    return PlanStep(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      status: StepStatusX.fromWireValue(json['status']?.toString()),
      substeps: rawSubsteps is List
          ? rawSubsteps
                .whereType<Map>()
                .map(
                  (entry) =>
                      PlanSubstep.fromJson(Map<String, dynamic>.from(entry)),
                )
                .toList(growable: false)
          : const [],
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (entry) =>
                      PlanSource.fromJson(Map<String, dynamic>.from(entry)),
                )
                .toList(growable: false)
          : const [],
    );
  }

  /// Compact representation for local chat persistence.
  Map<String, dynamic> toCompactJson() {
    return {
      'id': id,
      'title': title,
      'status': status.wireValue,
      if (sources.isNotEmpty)
        'sources': sources.map((source) => source.toCompactJson()).toList(),
      if (substeps.isNotEmpty)
        'substeps': substeps.map((substep) => substep.toCompactJson()).toList(),
    };
  }
}
