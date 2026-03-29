import 'package:flutter/foundation.dart';

class Resource {
  static const String approvedStatus = 'approved';
  static const String pendingStatus = 'pending';
  static const String rejectedStatus = 'rejected';
  static const Set<String> approvedStatusAliases = <String>{
    approvedStatus,
    'accepted',
    'published',
    'live',
    'active',
  };
  static const Set<String> pendingStatusAliases = <String>{
    pendingStatus,
    'review',
    'in_review',
    'under_review',
    'submitted',
  };
  static const Set<String> rejectedStatusAliases = <String>{
    rejectedStatus,
    'declined',
    'denied',
    'retracted',
    'withdrawn',
    'removed',
  };

  final String id;
  final String title;
  final String type; // notes, video, pyq
  final String fileUrl;
  final String? thumbnailUrl;
  final String? semester;
  final String? branch;
  final String? subject;
  final ResourcePrimaryScope? primaryScope;
  final List<ResourceScope> scopes;
  final String? chapter;
  final String? topic;
  final String? description; // Added for notices
  final int upvotes;
  final int downvotes;
  final String uploadedByEmail;
  final String? uploadedByName;
  final String collegeId;
  final String status; // pending, approved, rejected
  final bool isApproved;
  final bool isTeacherUpload;
  final DateTime createdAt;

  Resource({
    required this.id,
    required this.title,
    required this.type,
    required this.fileUrl,
    this.thumbnailUrl,
    this.semester,
    this.branch,
    this.subject,
    this.primaryScope,
    this.scopes = const <ResourceScope>[],
    this.chapter,
    this.topic,
    this.description,
    this.upvotes = 0,
    this.downvotes = 0,
    required this.uploadedByEmail,
    this.uploadedByName,
    required this.collegeId,
    this.status = 'approved',
    this.isApproved = true,
    this.isTeacherUpload = false,
    required this.createdAt,
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    final resolvedStatus = normalizeStatusValue(
      _resolveStatusValue(json),
      isApproved: json['is_approved'] ?? json['isApproved'],
    );
    final resolvedFileUrl = _resolveFileUrl(json);
    final resolvedPrimaryScope = ResourcePrimaryScope.fromJson(
      (json['primaryScope'] is Map)
          ? Map<String, dynamic>.from(json['primaryScope'] as Map)
          : ((json['primary_scope'] is Map)
                ? Map<String, dynamic>.from(json['primary_scope'] as Map)
                : const <String, dynamic>{}),
    );
    final resolvedScopesRaw =
        (json['scopes'] as List?) ??
        (json['resource_scopes'] as List?) ??
        const [];
    final resolvedScopes = resolvedScopesRaw
        .whereType<Map>()
        .map((item) => ResourceScope.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final effectiveSemester =
        resolvedPrimaryScope?.semester ?? json['semester'];
    final effectiveBranch = resolvedPrimaryScope?.branch ?? json['branch'];
    final effectiveSubject = resolvedPrimaryScope?.subject ?? json['subject'];

    return Resource(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'notes',
      fileUrl: resolvedFileUrl,
      thumbnailUrl: json['thumbnail_url'],
      semester: effectiveSemester?.toString(),
      branch: effectiveBranch?.toString(),
      subject: effectiveSubject?.toString(),
      primaryScope: resolvedPrimaryScope,
      scopes: resolvedScopes,
      chapter: json['chapter'],
      topic: json['topic'],
      description:
          json['description'] ??
          json['content'], // Map content to description for flexibility
      upvotes: json['upvotes'] ?? 0,
      downvotes: json['downvotes'] ?? 0,
      uploadedByEmail: json['uploaded_by_email'] ?? '',
      uploadedByName: json['uploaded_by_name'],
      collegeId: json['college_id'] ?? '',
      status: resolvedStatus,
      isApproved: isApprovedStatusValue(resolvedStatus),
      isTeacherUpload: _resolveTeacherUpload(json),
      createdAt: _parseCreatedAt(json),
    );
  }

  static String _resolveStatusValue(Map<String, dynamic> json) {
    const candidateKeys = <String>[
      'status',
      'resource_status',
      'resourceStatus',
      'moderation_status',
      'moderationStatus',
      'approval_status',
      'approvalStatus',
    ];

    for (final key in candidateKeys) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _coerceBooleanFlag(dynamic rawValue) {
    if (rawValue is bool) return rawValue;
    if (rawValue is num) return rawValue != 0;
    final normalized = rawValue?.toString().trim().toLowerCase() ?? '';
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  static bool _resolveTeacherUpload(Map<String, dynamic> json) {
    final uploaderRole =
        json['uploader_role']?.toString().trim().toLowerCase() ?? '';
    final source = json['source']?.toString().trim().toLowerCase() ?? '';

    if (uploaderRole == 'teacher' ||
        uploaderRole == 'admin' ||
        uploaderRole == 'moderator') {
      return true;
    }

    if (source == 'teacher') return true;
    return _coerceBooleanFlag(json['is_teacher_upload']);
  }

  static String _normalizeStatusToken(String? rawStatus) {
    final normalized = rawStatus?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return '';
    if (approvedStatusAliases.contains(normalized)) return approvedStatus;
    if (rejectedStatusAliases.contains(normalized)) return rejectedStatus;
    if (pendingStatusAliases.contains(normalized)) return pendingStatus;
    if (kDebugMode) {
      debugPrint(
        '_normalizeStatusToken: unrecognized status "$rawStatus" '
        '(normalized: "$normalized") — not in approvedStatusAliases, '
        'rejectedStatusAliases, or pendingStatusAliases. Returning as-is.',
      );
    }
    return normalized;
  }

  static String normalizeStatusValue(
    dynamic rawStatus, {
    dynamic isApproved,
    dynamic isRejected,
  }) {
    final normalized = _normalizeStatusToken(rawStatus?.toString());
    if (normalized.isNotEmpty) return normalized;
    if (_coerceBooleanFlag(isApproved)) return approvedStatus;
    if (_coerceBooleanFlag(isRejected)) return rejectedStatus;
    return pendingStatus;
  }

  static bool isApprovedStatusValue(dynamic rawStatus, {dynamic isApproved}) {
    return normalizeStatusValue(rawStatus, isApproved: isApproved) ==
        approvedStatus;
  }

  static Set<String> expandStatusAliases(Iterable<String> statuses) {
    final expanded = <String>{};
    for (final status in statuses) {
      switch (_normalizeStatusToken(status)) {
        case approvedStatus:
          expanded.addAll(approvedStatusAliases);
          break;
        case rejectedStatus:
          expanded.addAll(rejectedStatusAliases);
          break;
        case pendingStatus:
          expanded.addAll(pendingStatusAliases);
          break;
        case final normalized when normalized.isNotEmpty:
          expanded.add(normalized);
          break;
      }
    }
    return expanded;
  }

  /// Builds a PostgREST-style comma-separated OR filter for the given
  /// [statuses], e.g. `"status.eq.approved,status.eq.published"`.
  ///
  /// Each entry in [statuses] is first normalized via [_normalizeStatusToken]
  /// and then expanded through [expandStatusAliases] so that callers can pass
  /// either canonical constants (`approvedStatus`) or raw aliases (`"live"`).
  ///
  /// When [includeLegacyApprovalFlag] is `true` **and** the normalized set
  /// contains [approvedStatus], the clause `"is_approved.eq.true"` is
  /// appended for backward-compatible queries.
  ///
  /// Returns an empty string when no valid (non-empty) statuses remain after
  /// normalization.
  static String buildStatusOrFilter(
    Iterable<String> statuses, {
    bool includeLegacyApprovalFlag = false,
  }) {
    final normalizedStatuses = statuses
        .map(_normalizeStatusToken)
        .where((status) => status.isNotEmpty)
        .toSet();
    if (normalizedStatuses.isEmpty) return '';

    final clauses = expandStatusAliases(
      normalizedStatuses,
    ).map((status) => 'status.eq.$status').toList()..sort();
    if (includeLegacyApprovalFlag &&
        normalizedStatuses.contains(approvedStatus)) {
      clauses.add('is_approved.eq.true');
    }
    return clauses.join(',');
  }

  static String _resolveFileUrl(Map<String, dynamic> json) {
    const candidateKeys = <String>[
      'file_url',
      'fileUrl',
      'pdf_url',
      'pdfUrl',
      'video_url',
      'videoUrl',
      'attachment_url',
      'attachmentUrl',
      'public_url',
      'publicUrl',
      'url',
    ];

    for (final key in candidateKeys) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static DateTime _parseCreatedAt(Map<String, dynamic> json) {
    final raw = json['created_at'];
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) {
      debugPrint(
        'Resource Warning: Invalid created_at "$raw" for ID ${json['id']}. Fallback to epoch.',
      );
      return DateTime.utc(1970, 1, 1);
    }
    return parsed;
  }

  Map<String, dynamic> toJson() {
    final normalizedStatus = normalizeStatusValue(
      status,
      isApproved: isApproved,
    );
    return {
      'id': id,
      'title': title,
      'type': type,
      'file_url': fileUrl,
      'thumbnail_url': thumbnailUrl,
      'semester': semester,
      'branch': branch,
      'subject': subject,
      'primaryScope': primaryScope?.toJson(),
      'scopes': scopes.map((scope) => scope.toJson()).toList(),
      'chapter': chapter,
      'topic': topic,
      'description': description,
      'content': description, // Ensure content mirrors description
      'upvotes': upvotes,
      'downvotes': downvotes,
      'uploaded_by_email': uploadedByEmail,
      'uploaded_by_name': uploadedByName,
      'college_id': collegeId,
      'status': normalizedStatus,
      'is_approved': normalizedStatus == approvedStatus,
      'is_teacher_upload': isTeacherUpload,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get _normalizedStatus => _normalizeStatusToken(status);

  bool get isApprovedStatus => _normalizedStatus == approvedStatus;

  bool get isPendingStatus => _normalizedStatus == pendingStatus;

  bool get isRejectedStatus => _normalizedStatus == rejectedStatus;

  /// Get vote score
  int get score => upvotes - downvotes;

  /// Check if resource is a PDF
  bool get isPdf {
    final path =
        Uri.tryParse(fileUrl)?.path.toLowerCase() ?? fileUrl.toLowerCase();
    return path.endsWith('.pdf');
  }

  /// Check if resource is a video
  bool get isVideo {
    final url = fileUrl.toLowerCase();
    return url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.webm') ||
        url.contains('youtube.com') ||
        url.contains('youtu.be');
  }

  /// Get resource type icon name
  String get iconName {
    switch (type.toLowerCase()) {
      case 'video':
        return 'video';
      case 'pyq':
        return 'quiz';
      case 'notes':
      default:
        return 'description';
    }
  }

  /// Get formatted date
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes <= 0) {
          return 'just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }
}

class ResourcePrimaryScope {
  final String branch;
  final String semester;
  final String subject;

  const ResourcePrimaryScope({
    required this.branch,
    required this.semester,
    required this.subject,
  });

  static ResourcePrimaryScope? fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return null;
    final branch = json['branch']?.toString().trim() ?? '';
    final semester = json['semester']?.toString().trim() ?? '';
    final subject = json['subject']?.toString().trim() ?? '';
    if (branch.isEmpty || semester.isEmpty || subject.isEmpty) {
      return null;
    }
    return ResourcePrimaryScope(
      branch: branch,
      semester: semester,
      subject: subject,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'branch': branch,
    'semester': semester,
    'subject': subject,
  };
}

class ResourceScope {
  final String branch;
  final String semester;
  final String subject;
  final String? subjectKey;
  final bool isPrimary;
  final String? source;

  const ResourceScope({
    required this.branch,
    required this.semester,
    required this.subject,
    this.subjectKey,
    this.isPrimary = false,
    this.source,
  });

  factory ResourceScope.fromJson(Map<String, dynamic> json) {
    return ResourceScope(
      branch: json['branch']?.toString().trim() ?? '',
      semester: json['semester']?.toString().trim() ?? '',
      subject: json['subject']?.toString().trim() ?? '',
      subjectKey:
          json['subjectKey']?.toString() ?? json['subject_key']?.toString(),
      isPrimary: json['isPrimary'] == true || json['is_primary'] == true,
      source: json['source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'branch': branch,
    'semester': semester,
    'subject': subject,
    'subjectKey': subjectKey,
    'isPrimary': isPrimary,
    'source': source,
  };
}
