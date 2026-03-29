import 'package:flutter/foundation.dart';

enum AiLiveActivityStatus { pending, active, completed, warning, failed }

enum AiAnswerOrigin { notesOnly, notesPlusWeb, webOnly, insufficientNotes }

enum AiLiveSourceKind { notes, web, video }

extension AiLiveActivityStatusX on AiLiveActivityStatus {
  String get wireValue => switch (this) {
    AiLiveActivityStatus.pending => 'pending',
    AiLiveActivityStatus.active => 'active',
    AiLiveActivityStatus.completed => 'completed',
    AiLiveActivityStatus.warning => 'warning',
    AiLiveActivityStatus.failed => 'failed',
  };

  static AiLiveActivityStatus fromWireValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'active':
      case 'in-progress':
      case 'in_progress':
        return AiLiveActivityStatus.active;
      case 'completed':
        return AiLiveActivityStatus.completed;
      case 'warning':
      case 'need-help':
      case 'need_help':
        return AiLiveActivityStatus.warning;
      case 'failed':
        return AiLiveActivityStatus.failed;
      case 'pending':
      default:
        return AiLiveActivityStatus.pending;
    }
  }
}

extension AiAnswerOriginX on AiAnswerOrigin {
  String get wireValue => switch (this) {
    AiAnswerOrigin.notesOnly => 'notes_only',
    AiAnswerOrigin.notesPlusWeb => 'notes_plus_web',
    AiAnswerOrigin.webOnly => 'web_only',
    AiAnswerOrigin.insufficientNotes => 'insufficient_notes',
  };

  static AiAnswerOrigin? fromWireValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'notes_only':
        return AiAnswerOrigin.notesOnly;
      case 'notes_plus_web':
        return AiAnswerOrigin.notesPlusWeb;
      case 'web_only':
        return AiAnswerOrigin.webOnly;
      case 'insufficient_notes':
        return AiAnswerOrigin.insufficientNotes;
      default:
        return null;
    }
  }
}

extension AiLiveSourceKindX on AiLiveSourceKind {
  String get wireValue => switch (this) {
    AiLiveSourceKind.notes => 'notes',
    AiLiveSourceKind.web => 'web',
    AiLiveSourceKind.video => 'video',
  };

  static AiLiveSourceKind fromWireValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'web':
        return AiLiveSourceKind.web;
      case 'video':
      case 'youtube':
        return AiLiveSourceKind.video;
      case 'notes':
      default:
        return AiLiveSourceKind.notes;
    }
  }
}

@immutable
class AiLiveActivitySource {
  const AiLiveActivitySource({
    required this.title,
    required this.kind,
    this.page,
    this.timestamp,
    this.url,
    this.fileId,
    this.subject,
  });

  final String title;
  final AiLiveSourceKind kind;
  final int? page;
  final String? timestamp;
  final String? url;
  final String? fileId;
  final String? subject;

  bool get isClickable =>
      (kind == AiLiveSourceKind.notes &&
          (fileId?.trim().isNotEmpty ?? false)) ||
      (kind != AiLiveSourceKind.notes && (url?.trim().isNotEmpty ?? false));

  AiLiveActivitySource copyWith({
    String? title,
    AiLiveSourceKind? kind,
    int? page,
    String? timestamp,
    String? url,
    String? fileId,
    String? subject,
  }) {
    return AiLiveActivitySource(
      title: title ?? this.title,
      kind: kind ?? this.kind,
      page: page ?? this.page,
      timestamp: timestamp ?? this.timestamp,
      url: url ?? this.url,
      fileId: fileId ?? this.fileId,
      subject: subject ?? this.subject,
    );
  }

  factory AiLiveActivitySource.fromJson(Map<String, dynamic> json) {
    final rawPage = json['page'];
    return AiLiveActivitySource(
      title: json['title']?.toString() ?? 'Source',
      kind: AiLiveSourceKindX.fromWireValue(
        json['kind']?.toString() ?? json['badge']?.toString(),
      ),
      page: rawPage is int ? rawPage : int.tryParse(rawPage?.toString() ?? ''),
      timestamp: json['timestamp']?.toString(),
      url: json['url']?.toString(),
      fileId: json['file_id']?.toString(),
      subject: json['subject']?.toString(),
    );
  }

  Map<String, dynamic> toCompactJson() {
    return {
      'title': title,
      'kind': kind.wireValue,
      if (page != null) 'page': page,
      if (fileId != null && fileId!.trim().isNotEmpty) 'file_id': fileId,
      if (url != null && url!.trim().isNotEmpty) 'url': url,
      if (timestamp != null && timestamp!.trim().isNotEmpty)
        'timestamp': timestamp,
    };
  }
}

@immutable
class AiLiveActivityEvent {
  const AiLiveActivityEvent({
    required this.id,
    required this.title,
    required this.status,
    this.detail,
    this.sources = const [],
  });

  final String id;
  final String title;
  final AiLiveActivityStatus status;
  final String? detail;
  final List<AiLiveActivitySource> sources;

  AiLiveActivityEvent copyWith({
    String? id,
    String? title,
    AiLiveActivityStatus? status,
    String? detail,
    List<AiLiveActivitySource>? sources,
  }) {
    return AiLiveActivityEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      sources: sources ?? this.sources,
    );
  }

  factory AiLiveActivityEvent.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    return AiLiveActivityEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      status: AiLiveActivityStatusX.fromWireValue(json['status']?.toString()),
      detail: json['detail']?.toString(),
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (entry) => AiLiveActivitySource.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toCompactJson() {
    return {
      'id': id,
      'title': title,
      'status': status.wireValue,
      if (detail != null && detail!.trim().isNotEmpty) 'detail': detail,
      if (sources.isNotEmpty)
        'sources': sources.map((source) => source.toCompactJson()).toList(),
    };
  }
}

@immutable
class AiLiveActivityStep {
  const AiLiveActivityStep({
    required this.id,
    required this.title,
    required this.status,
    this.description,
    this.events = const [],
    this.sources = const [],
  });

  final String id;
  final String title;
  final AiLiveActivityStatus status;
  final String? description;
  final List<AiLiveActivityEvent> events;
  final List<AiLiveActivitySource> sources;

  bool get hasDetails =>
      (description?.trim().isNotEmpty ?? false) ||
      events.isNotEmpty ||
      sources.isNotEmpty;

  AiLiveActivityStep copyWith({
    String? id,
    String? title,
    AiLiveActivityStatus? status,
    String? description,
    List<AiLiveActivityEvent>? events,
    List<AiLiveActivitySource>? sources,
  }) {
    return AiLiveActivityStep(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      description: description ?? this.description,
      events: events ?? this.events,
      sources: sources ?? this.sources,
    );
  }

  factory AiLiveActivityStep.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['events'] ?? json['substeps'];
    final rawSources = json['sources'];
    return AiLiveActivityStep(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      status: AiLiveActivityStatusX.fromWireValue(json['status']?.toString()),
      description: json['description']?.toString(),
      events: rawEvents is List
          ? rawEvents
                .whereType<Map>()
                .map(
                  (entry) => AiLiveActivityEvent.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .toList(growable: false)
          : const [],
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (entry) => AiLiveActivitySource.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toCompactJson() {
    return {
      'id': id,
      'title': title,
      'status': status.wireValue,
      if (description != null && description!.trim().isNotEmpty)
        'description': description,
      if (events.isNotEmpty)
        'events': events.map((event) => event.toCompactJson()).toList(),
      if (sources.isNotEmpty)
        'sources': sources.map((source) => source.toCompactJson()).toList(),
    };
  }
}
