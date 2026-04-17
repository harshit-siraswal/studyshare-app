import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiOutputLocalService {
  static const String _prefix = 'ai_output_v1';
  static const String _pendingPrefix = 'ai_pending_job_v1';

  String _key(String resourceId, String type) {
    return '$_prefix::${Uri.encodeComponent(resourceId)}::${Uri.encodeComponent(type)}';
  }

  String _pendingKey(String resourceId, String type) {
    return '$_pendingPrefix::${Uri.encodeComponent(resourceId)}::${Uri.encodeComponent(type)}';
  }

  Future<void> saveOutput({
    required String resourceId,
    required String type,
    required dynamic data,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'data': data,
    });
    await prefs.setString(_key(resourceId, type), payload);
  }

  Future<dynamic> loadOutput({
    required String resourceId,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(resourceId, type));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded['data'];
      }
    } catch (e) {
      debugPrint('AiOutputLocalService: Failed to decode stored output: $e');
      return null;
    }
    return null;
  }

  Future<void> clearOutput({
    required String resourceId,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(resourceId, type));
  }

  Future<void> savePendingJob({
    required String resourceId,
    required String type,
    required String jobId,
    String? runId,
    String? clientRequestId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'type': type,
      'job_id': jobId,
      'run_id': runId,
      'client_request_id': clientRequestId,
    });
    await prefs.setString(_pendingKey(resourceId, type), payload);
  }

  Future<Map<String, dynamic>?> loadPendingJob({
    required String resourceId,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey(resourceId, type));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (e) {
      debugPrint('AiOutputLocalService: Failed to decode pending job: $e');
      return null;
    }
    return null;
  }

  Future<void> clearPendingJob({
    required String resourceId,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey(resourceId, type));
  }
}
