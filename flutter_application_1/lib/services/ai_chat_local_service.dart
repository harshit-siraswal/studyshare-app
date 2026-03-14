import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalAiChatMessage {
  final bool isUser;
  final String content;
  final List<Map<String, dynamic>> sources;
  final bool cached;
  final bool noLocal;
  final double? retrievalScore;
  final double? llmConfidenceScore;
  final double? combinedConfidence;
  final bool ocrFailureAffectsRetrieval;
  final List<Map<String, dynamic>> ocrErrors;
  final String? actionType;
  final Map<String, dynamic>? actionPayload;
  final String createdAt;

  const LocalAiChatMessage({
    required this.isUser,
    required this.content,
    required this.sources,
    required this.cached,
    required this.noLocal,
    this.retrievalScore,
    this.llmConfidenceScore,
    this.combinedConfidence,
    this.ocrFailureAffectsRetrieval = false,
    this.ocrErrors = const [],
    this.actionType,
    this.actionPayload,
    required this.createdAt,
  });

  factory LocalAiChatMessage.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    final rawOcrErrors = json['ocr_errors'];
    final rawActionType = json['action_type']?.toString();
    final rawActionPayload = json['action_payload'];
    Map<String, dynamic>? normalizedActionPayload;
    if (rawActionPayload is Map) {
      final mapped = Map<String, dynamic>.from(rawActionPayload);
      if (mapped.isNotEmpty) {
        normalizedActionPayload = mapped;
      }
    } else if (rawActionPayload is String) {
      final trimmed = rawActionPayload.trim();
      if (trimmed.isNotEmpty) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            final mapped = Map<String, dynamic>.from(decoded);
            if (mapped.isNotEmpty) {
              normalizedActionPayload = mapped;
            }
          }
        } catch (_) {
          // Ignore malformed legacy payloads and treat as missing.
        }
      }
    }

    return LocalAiChatMessage(
      isUser: json['is_user'] == true,
      content: json['content']?.toString() ?? '',
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList()
          : const [],
      cached: json['cached'] == true,
      noLocal: json['no_local'] == true,
      retrievalScore: json['retrieval_score'] is num
          ? (json['retrieval_score'] as num).toDouble()
          : double.tryParse(json['retrieval_score']?.toString() ?? ''),
      llmConfidenceScore: json['llm_confidence_score'] is num
          ? (json['llm_confidence_score'] as num).toDouble()
          : double.tryParse(json['llm_confidence_score']?.toString() ?? ''),
      combinedConfidence: json['combined_confidence'] is num
          ? (json['combined_confidence'] as num).toDouble()
          : double.tryParse(json['combined_confidence']?.toString() ?? ''),
      ocrFailureAffectsRetrieval:
          json['ocr_failure_affects_retrieval'] == true,
      ocrErrors: rawOcrErrors is List
          ? rawOcrErrors
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList()
          : const [],
      actionType: rawActionType == null || rawActionType.trim().isEmpty
          ? null
          : rawActionType.trim(),
      actionPayload: normalizedActionPayload,
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_user': isUser,
      'content': content,
      'sources': sources,
      'cached': cached,
      'no_local': noLocal,
      if (retrievalScore != null) 'retrieval_score': retrievalScore,
      if (llmConfidenceScore != null)
        'llm_confidence_score': llmConfidenceScore,
      if (combinedConfidence != null)
        'combined_confidence': combinedConfidence,
      'ocr_failure_affects_retrieval': ocrFailureAffectsRetrieval,
      if (ocrErrors.isNotEmpty) 'ocr_errors': ocrErrors,
      if (actionType != null && actionType!.isNotEmpty)
        'action_type': actionType,
      if (actionPayload != null && actionPayload!.isNotEmpty)
        'action_payload': actionPayload,
      'created_at': createdAt,
    };
  }
}

class LocalAiChatSession {
  final String id;
  final String title;
  final String updatedAt;
  final List<LocalAiChatMessage> messages;
  final List<Map<String, dynamic>> contextAttachments;

  const LocalAiChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
    this.contextAttachments = const [],
  });

  factory LocalAiChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final rawContextAttachments = json['context_attachments'];
    return LocalAiChatSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'New chat',
      updatedAt:
          json['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
      messages: rawMessages is List
          ? rawMessages
                .whereType<Map>()
                .map(
                  (entry) => LocalAiChatMessage.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .toList()
          : const [],
      contextAttachments: rawContextAttachments is List
          ? rawContextAttachments
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'updated_at': updatedAt,
      'messages': messages.map((message) => message.toJson()).toList(),
      if (contextAttachments.isNotEmpty)
        'context_attachments': contextAttachments,
    };
  }
}

class AiChatLocalService {
  static const String _prefix = 'ai_chat_sessions_v1';

  String _storageKey({required String userEmail, required String collegeId}) {
    final safeEmail = userEmail.trim().toLowerCase();
    final safeCollege = collegeId.trim().toLowerCase();
    return '$_prefix::$safeEmail::$safeCollege';
  }

  Future<List<LocalAiChatSession>> loadSessions({
    required String userEmail,
    required String collegeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      _storageKey(userEmail: userEmail, collegeId: collegeId),
    );
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                LocalAiChatSession.fromJson(Map<String, dynamic>.from(entry)),
          )
          .where((session) => session.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSessions({
    required String userEmail,
    required String collegeId,
    required List<LocalAiChatSession> sessions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      sessions.map((session) => session.toJson()).toList(),
    );
    await prefs.setString(
      _storageKey(userEmail: userEmail, collegeId: collegeId),
      payload,
    );
  }
}
