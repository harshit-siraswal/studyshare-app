import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiOutputLocalService {
  static const String _prefix = 'ai_output_v1';

  String _key(String resourceId, String type) {
    return '$_prefix::${Uri.encodeComponent(resourceId)}::${Uri.encodeComponent(type)}';
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
}
