import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'ai_chat_local_service.dart';

class ChatSessionDeleteResult {
  final List<LocalAiChatSession> sessions;
  final bool deleted;

  const ChatSessionDeleteResult({
    required this.sessions,
    required this.deleted,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatSessionDeleteResult) return false;
    final thisPayload = sessions
        .map((session) => jsonEncode(session.toJson()))
        .toList(growable: false);
    final otherPayload = other.sessions
        .map((session) => jsonEncode(session.toJson()))
        .toList(growable: false);
    return deleted == other.deleted && listEquals(thisPayload, otherPayload);
  }

  @override
  int get hashCode {
    final payload = sessions
        .map((session) => jsonEncode(session.toJson()))
        .toList(growable: false);
    return Object.hash(deleted, Object.hashAll(payload));
  }
}

/// Handles loading/saving/deleting local AI chat sessions.
class ChatSessionRepository {
  ChatSessionRepository({AiChatLocalService? localService})
    : _localService = localService ?? AiChatLocalService();

  final AiChatLocalService _localService;

  String _maskEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final parts = normalized.split('@');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      return '[redacted_email]';
    }
    final local = parts[0];
    final domain = parts[1];
    final maskedLocal = '${local[0]}***';
    final domainParts = domain.split('.');
    if (domainParts.isEmpty) {
      return '$maskedLocal@***';
    }
    final domainHead = domainParts.first;
    final maskedDomainHead = domainHead.isEmpty ? '***' : '${domainHead[0]}***';
    final suffix = domainParts.length > 1
        ? '.${domainParts.sublist(1).join('.')}'
        : '';
    return '$maskedLocal@$maskedDomainHead$suffix';
  }

  String _shortSessionId(String sessionId) {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty) return 'unknown';
    return trimmed.length <= 8 ? trimmed : '${trimmed.substring(0, 8)}...';
  }

  void _logFailure(
    String operation, {
    required Object error,
    required StackTrace stackTrace,
    String? userEmail,
    required String collegeId,
    String? sessionId,
  }) {
    final maskedEmail = userEmail == null ? null : _maskEmail(userEmail);
    final shortSessionId = sessionId == null
        ? null
        : _shortSessionId(sessionId);
    final contextParts = <String>[
      if (maskedEmail != null) 'userEmail=$maskedEmail',
      'collegeId=$collegeId',
      if (shortSessionId != null) 'sessionId=$shortSessionId',
    ];
    developer.log(
      'ChatSessionRepository.$operation failed (${contextParts.join(' ')}).',
      name: 'chat.session.repository',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<List<LocalAiChatSession>> loadSessions({
    required String userEmail,
    required String collegeId,
  }) async {
    try {
      return await _localService.loadSessions(
        userEmail: userEmail,
        collegeId: collegeId,
      );
    } catch (e, stackTrace) {
      _logFailure(
        'loadSessions',
        error: e,
        stackTrace: stackTrace,
        userEmail: userEmail,
        collegeId: collegeId,
      );
      rethrow;
    }
  }

  Future<List<LocalAiChatSession>> upsertSession({
    required String userEmail,
    required String collegeId,
    required LocalAiChatSession session,
    required List<LocalAiChatSession> existingSessions,
  }) async {
    try {
      final updated = <LocalAiChatSession>[
        session,
        ...existingSessions.where((item) => item.id != session.id),
      ];
      await _localService.saveSessions(
        userEmail: userEmail,
        collegeId: collegeId,
        sessions: updated,
      );
      return updated;
    } catch (e, stackTrace) {
      _logFailure(
        'upsertSession',
        error: e,
        stackTrace: stackTrace,
        userEmail: userEmail,
        collegeId: collegeId,
        sessionId: session.id,
      );
      rethrow;
    }
  }

  Future<ChatSessionDeleteResult> deleteSession({
    required String userEmail,
    required String collegeId,
    required String sessionId,
    required List<LocalAiChatSession> existingSessions,
  }) async {
    try {
      final updated = existingSessions
          .where((session) => session.id != sessionId)
          .toList();
      final deleted = updated.length != existingSessions.length;
      await _localService.saveSessions(
        userEmail: userEmail,
        collegeId: collegeId,
        sessions: updated,
      );
      return ChatSessionDeleteResult(sessions: updated, deleted: deleted);
    } catch (e, stackTrace) {
      _logFailure(
        'deleteSession',
        error: e,
        stackTrace: stackTrace,
        userEmail: userEmail,
        collegeId: collegeId,
        sessionId: sessionId,
      );
      rethrow;
    }
  }
}
