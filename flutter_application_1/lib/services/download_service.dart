import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/resource.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  static const String _boxName = 'offline_resources';
  static const String _ownerSeparator = '::';

  late Box _box;
  bool _initialized = false;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox(_boxName);
    _initialized = true;
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _resourceKeyForOwner(String resourceId, String ownerEmail) {
    return '${_normalizeEmail(ownerEmail)}$_ownerSeparator$resourceId';
  }

  bool _matchesResourceId(String key, String resourceId) {
    return key == resourceId || key.endsWith('$_ownerSeparator$resourceId');
  }

  String? _ownerFromScopedKey(String key) {
    if (!key.contains(_ownerSeparator)) return null;
    final owner = key.split(_ownerSeparator).first.trim().toLowerCase();
    return owner.isEmpty ? null : owner;
  }

  Map<String, dynamic>? _toEntryMap(dynamic data) {
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      return {'local_path': data};
    }
    return null;
  }

  String? _extractPath(Map<String, dynamic> data) {
    final raw = data['local_path'];
    if (raw == null) return null;
    final path = raw.toString();
    return path.isEmpty ? null : path;
  }

  bool _entryFileExists(Map<String, dynamic> data) {
    final path = _extractPath(data);
    if (path == null) return false;
    return File(path).existsSync();
  }

  String? _entryOwner({
    required String key,
    required Map<String, dynamic> data,
  }) {
    final ownerFromData = data['owner_email']?.toString().trim().toLowerCase();
    if (ownerFromData != null && ownerFromData.isNotEmpty) {
      return ownerFromData;
    }
    return _ownerFromScopedKey(key);
  }

  bool _entryRequiresPremium(Map<String, dynamic> data) {
    final raw = data['requires_premium'] ?? data['is_premium_required'];
    if (raw is bool) return raw;
    if (raw is String) {
      return raw.trim().toLowerCase() == 'true';
    }
    // Secure default: downloaded files require premium access.
    return true;
  }

  Map<String, dynamic>? _findEntryForUser(
    String resourceId,
    String ownerEmail,
  ) {
    if (!_initialized) return null;
    final normalizedEmail = _normalizeEmail(ownerEmail);
    final scopedKey = _resourceKeyForOwner(resourceId, normalizedEmail);
    final scopedEntry = _toEntryMap(_box.get(scopedKey));
    if (scopedEntry != null) return scopedEntry;

    final legacyEntry = _toEntryMap(_box.get(resourceId));
    if (legacyEntry == null) return null;
    final legacyOwner = _entryOwner(key: resourceId, data: legacyEntry);
    if (legacyOwner == normalizedEmail) return legacyEntry;
    return null;
  }

  bool isDownloadedForUser(String resourceId, String ownerEmail) {
    if (!_initialized) return false;
    final entry = _findEntryForUser(resourceId, ownerEmail);
    if (entry == null) return false;
    return _entryFileExists(entry);
  }

  String? getLocalPathForUser(String resourceId, String ownerEmail) {
    if (!_initialized) return null;
    final entry = _findEntryForUser(resourceId, ownerEmail);
    if (entry == null || !_entryFileExists(entry)) return null;
    return _extractPath(entry);
  }

  String? getAccessibleLocalPath({
    required String resourceId,
    required String ownerEmail,
    required bool hasPremiumAccess,
  }) {
    if (!_initialized) return null;
    final entry = _findEntryForUser(resourceId, ownerEmail);
    if (entry == null || !_entryFileExists(entry)) return null;
    if (_entryRequiresPremium(entry) && !hasPremiumAccess) return null;
    return _extractPath(entry);
  }

  bool hasDownloadForAnotherUser(String resourceId, String ownerEmail) {
    if (!_initialized) return false;
    final normalizedEmail = _normalizeEmail(ownerEmail);
    for (final entry in _box.toMap().entries) {
      final key = entry.key.toString();
      if (!_matchesResourceId(key, resourceId)) continue;
      final data = _toEntryMap(entry.value);
      if (data == null || !_entryFileExists(data)) continue;
      final owner = _entryOwner(key: key, data: data);
      if (owner == null) continue;
      if (owner != normalizedEmail) return true;
    }
    return false;
  }

  bool isDownloaded(String resourceId) {
    if (!_initialized) return false;
    for (final entry in _box.toMap().entries) {
      final key = entry.key.toString();
      if (!_matchesResourceId(key, resourceId)) continue;
      final data = _toEntryMap(entry.value);
      if (data == null) continue;
      if (_entryFileExists(data)) return true;
    }
    return false;
  }

  String? getLocalPath(String resourceId) {
    if (!_initialized) return null;
    final entry = _toEntryMap(_box.get(resourceId));
    if (entry != null && _entryFileExists(entry)) {
      return _extractPath(entry);
    }
    for (final dataEntry in _box.toMap().entries) {
      final key = dataEntry.key.toString();
      if (!_matchesResourceId(key, resourceId)) continue;
      final data = _toEntryMap(dataEntry.value);
      if (data == null || !_entryFileExists(data)) continue;
      return _extractPath(data);
    }
    return null;
  }

  List<Resource> getAllDownloadedResources() {
    if (!_initialized) return [];
    final resources = <Resource>[];

    for (final boxEntry in _box.toMap().entries) {
      final data = _toEntryMap(boxEntry.value);
      if (data == null || !_entryFileExists(data)) continue;
      try {
        final resourceJson = data['resource_json'];
        if (resourceJson is! Map) continue;
        resources.add(
          Resource.fromJson(Map<String, dynamic>.from(resourceJson)),
        );
      } catch (e) {
        debugPrint('Error parsing cached resource: $e');
      }
    }
    return resources;
  }

  List<Resource> getAllDownloadedResourcesForUser(
    String ownerEmail, {
    bool hasPremiumAccess = true,
    bool includeLocked = false,
  }) {
    if (!_initialized) return [];
    final normalizedEmail = _normalizeEmail(ownerEmail);
    final resources = <Resource>[];

    for (final boxEntry in _box.toMap().entries) {
      final key = boxEntry.key.toString();
      final data = _toEntryMap(boxEntry.value);
      if (data == null || !_entryFileExists(data)) continue;
      final owner = _entryOwner(key: key, data: data);
      if (owner != normalizedEmail) continue;

      final requiresPremium = _entryRequiresPremium(data);
      if (requiresPremium && !hasPremiumAccess && !includeLocked) {
        continue;
      }

      try {
        final resourceJson = data['resource_json'];
        if (resourceJson is! Map) continue;
        resources.add(
          Resource.fromJson(Map<String, dynamic>.from(resourceJson)),
        );
      } catch (e) {
        debugPrint('Error parsing cached user resource: $e');
      }
    }

    resources.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return resources;
  }

  Future<void> downloadResource(
    String url,
    Resource resource, {
    required String ownerEmail,
    bool requiresPremiumContent = true,
    Function(int, int)? onProgress,
  }) async {
    if (!_initialized) await init();

    try {
      final normalizedOwner = _normalizeEmail(ownerEmail);
      final safeOwnerFolder = normalizedOwner.replaceAll(
        RegExp(r'[^a-z0-9._-]'),
        '_',
      );
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/downloads/$safeOwnerFolder');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final uri = Uri.tryParse(url);
      final lastSegment = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : '';
      final extensionMatch = RegExp(
        r'\.([a-zA-Z0-9]{1,6})$',
      ).firstMatch(lastSegment);
      final extension = extensionMatch?.group(1)?.toLowerCase() ?? 'bin';
      final safeName = resource.title
          .replaceAll(RegExp(r'[^\w\s\.-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final fileNameBase = safeName.isEmpty ? 'resource' : safeName;
      final safePath =
          '${saveDir.path}/${fileNameBase}_${resource.id}.$extension';

      await _dio.download(url, safePath, onReceiveProgress: onProgress);

      final data = {
        'local_path': safePath,
        'resource_json': resource.toJson(),
        'downloaded_at': DateTime.now().toIso8601String(),
        'owner_email': normalizedOwner,
        'requires_premium': requiresPremiumContent,
      };

      final scopedKey = _resourceKeyForOwner(resource.id, normalizedOwner);
      await _box.put(scopedKey, data);
      if (_box.containsKey(resource.id)) {
        await _box.delete(resource.id);
      }
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }

  Future<void> deleteResource(String resourceId, {String? ownerEmail}) async {
    if (!_initialized) await init();

    final keysToDelete = <dynamic>{};
    if (ownerEmail != null && ownerEmail.trim().isNotEmpty) {
      final scopedKey = _resourceKeyForOwner(resourceId, ownerEmail);
      keysToDelete.add(scopedKey);

      final legacy = _toEntryMap(_box.get(resourceId));
      if (legacy != null) {
        final owner = _entryOwner(key: resourceId, data: legacy);
        if (owner == _normalizeEmail(ownerEmail)) {
          keysToDelete.add(resourceId);
        }
      }
    } else {
      for (final key in _box.keys) {
        if (_matchesResourceId(key.toString(), resourceId)) {
          keysToDelete.add(key);
        }
      }
    }

    for (final key in keysToDelete) {
      final data = _toEntryMap(_box.get(key));
      final path = data == null ? null : _extractPath(data);
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await _box.delete(key);
    }
  }
}
