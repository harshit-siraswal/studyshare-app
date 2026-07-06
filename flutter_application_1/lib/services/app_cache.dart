import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Disk-backed JSON cache used for cached-first rendering.
///
/// Stores each entry as `{'ts': epochMs, 'data': jsonString}` inside a single
/// Hive box so screens can render the last-known payload instantly on cold
/// start while a network refresh runs in the background.
class AppCache {
  AppCache._();

  static const String _boxName = 'app_cache';
  static Box<dynamic>? _box;

  static Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
    } catch (e) {
      debugPrint('AppCache: failed to open box, retrying fresh: $e');
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        _box = await Hive.openBox<dynamic>(_boxName);
      } catch (retryError) {
        debugPrint('AppCache: disabled (box unavailable): $retryError');
        _box = null;
      }
    }
  }

  static bool get isAvailable => _box != null && _box!.isOpen;

  static Future<void> putJson(String key, Object? json) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    try {
      await box.put(key, <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': jsonEncode(json),
      });
    } catch (e) {
      debugPrint('AppCache: put failed for $key: $e');
    }
  }

  /// Returns the cached JSON value for [key], or null when missing, invalid,
  /// or older than [maxAge] (when provided).
  static dynamic getJson(String key, {Duration? maxAge}) {
    final box = _box;
    if (box == null || !box.isOpen) return null;
    try {
      final raw = box.get(key);
      if (raw is! Map) return null;
      if (maxAge != null) {
        final ts = raw['ts'];
        final ageMs = DateTime.now().millisecondsSinceEpoch -
            (ts is int ? ts : 0);
        if (ageMs > maxAge.inMilliseconds) return null;
      }
      final data = raw['data'];
      if (data is! String) return null;
      return jsonDecode(data);
    } catch (e) {
      debugPrint('AppCache: get failed for $key: $e');
      return null;
    }
  }

  static Future<void> remove(String key) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    try {
      await box.delete(key);
    } catch (e) {
      debugPrint('AppCache: remove failed for $key: $e');
    }
  }

  /// Removes user-scoped entries (auth gate, profile, composer access, feeds).
  /// Called on sign-out so the next account never sees stale data.
  static Future<void> clearUserScoped() async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    try {
      final keys = box.keys
          .whereType<String>()
          .where(
            (key) =>
                key.startsWith('auth_gate_ok:') ||
                key.startsWith('user_profile:') ||
                key.startsWith('composer_access:') ||
                key.startsWith('study_resources:') ||
                key.startsWith('filter_values:') ||
                key.startsWith('rooms:') ||
                key.startsWith('room_posts:'),
          )
          .toList();
      await box.deleteAll(keys);
    } catch (e) {
      debugPrint('AppCache: clearUserScoped failed: $e');
    }
  }
}
