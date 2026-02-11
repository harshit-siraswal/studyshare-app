import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalAiChatMessage {
  final bool isUser;
  final String content;
  final List<Map<String, dynamic>> sources;
  final bool cached;
  final bool noLocal;
  final String createdAt;

  const LocalAiChatMessage({
    required this.isUser,
    required this.content,
    required this.sources,
    required this.cached,
    required this.noLocal,
    required this.createdAt,
  });

  factory LocalAiChatMessage.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
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
      'created_at': createdAt,
    };
  }
}

class LocalAiChatSession {
  final String id;
  final String title;
  final String updatedAt;
  final List<LocalAiChatMessage> messages;

  const LocalAiChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  factory LocalAiChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'updated_at': updatedAt,
      'messages': messages.map((message) => message.toJson()).toList(),
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
