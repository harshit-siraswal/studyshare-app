import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/resource.dart';

class DownloadCancelledException implements Exception {
  final String message;

  DownloadCancelledException([this.message = 'Download cancelled']);

  @override
  String toString() => message;
}

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  static const String _boxName = 'offline_resources';
  static const String _ownerSeparator = '::';

  late Box _box;
  bool _initialized = false;
  Future<void>? _initFuture;
  bool _resourceOwnersIndexReady = false;
  final Map<String, Set<String>> _resourceOwnersIndex = {};
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
  CancelToken? _cancelToken;

  Future<void> init() async {
    if (_initialized) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    _initFuture = () async {
      _box = await _openBoxWithHiveFallback();
      await _rebuildResourceOwnersIndex();
      _initialized = true;
    }();

    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<Box> _openBoxWithHiveFallback() async {
    try {
      return await Hive.openBox(_boxName);
    } catch (e) {
      final message = e.toString().toLowerCase();
      final needsInit =
          message.contains('you need to initialize hive') ||
          message.contains('initialize hive');
      if (!needsInit) rethrow;

      await Hive.initFlutter();
      return Hive.openBox(_boxName);
    }
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

  String _resourceIdFromKey(String key) {
    if (!key.contains(_ownerSeparator)) return key;
    return key.split(_ownerSeparator).last;
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

  Future<bool> _entryFileExists(Map<String, dynamic> data) async {
    final path = _extractPath(data);
    if (path == null) return false;
    return File(path).exists();
  }

  Future<void> _rebuildResourceOwnersIndex() async {
    _resourceOwnersIndex.clear();
    for (final key in _box.keys) {
      final keyString = key.toString();
      final data = _toEntryMap(_box.get(key));
      if (data == null) continue;
      final path = _extractPath(data);
      if (path == null || !await File(path).exists()) continue;
      final owner = _entryOwner(key: keyString, data: data);
      if (owner == null || owner.isEmpty) continue;
      _indexOwner(resourceId: _resourceIdFromKey(keyString), owner: owner);
    }
    _resourceOwnersIndexReady = true;
  }

  void _indexOwner({required String resourceId, required String owner}) {
    final normalizedOwner = _normalizeEmail(owner);
    if (resourceId.isEmpty || normalizedOwner.isEmpty) return;
    final owners = _resourceOwnersIndex.putIfAbsent(
      resourceId,
      () => <String>{},
    );
    owners.add(normalizedOwner);
  }

  void _unindexOwner({required String resourceId, required String owner}) {
    final normalizedOwner = _normalizeEmail(owner);
    final owners = _resourceOwnersIndex[resourceId];
    if (owners == null) return;
    owners.remove(normalizedOwner);
    if (owners.isEmpty) {
      _resourceOwnersIndex.remove(resourceId);
    }
  }

  void cancelDownload() {
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('user_cancelled');
    }
    _cancelToken = null;
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

  Future<bool> isDownloadedForUser(String resourceId, String ownerEmail) async {
    if (!_initialized) await init();
    final entry = _findEntryForUser(resourceId, ownerEmail);
    if (entry == null) return false;
    return _entryFileExists(entry);
  }

  Future<String?> getLocalPathForUser(
    String resourceId,
    String ownerEmail,
  ) async {
    if (!_initialized) await init();
    final entry = _findEntryForUser(resourceId, ownerEmail);
    if (entry == null || !await _entryFileExists(entry)) return null;
    return _extractPath(entry);
  }

  Future<String?> getAccessibleLocalPath({
    required String resourceId,
    required String ownerEmail,
    required bool hasPremiumAccess,
  }) async {
    if (!_initialized) await init();
    final entry = _findEntryForUser(resourceId, ownerEmail);
    if (entry == null || !await _entryFileExists(entry)) return null;
    if (_entryRequiresPremium(entry) && !hasPremiumAccess) return null;
    return _extractPath(entry);
  }

  Future<bool> hasDownloadForAnotherUser(
    String resourceId,
    String ownerEmail,
  ) async {
    if (!_initialized) await init();
    final normalizedEmail = _normalizeEmail(ownerEmail);
    if (_resourceOwnersIndexReady) {
      final owners = _resourceOwnersIndex[resourceId];
      if (owners != null) {
        return owners.any((owner) => owner != normalizedEmail);
      }
    }
    return _scanHasDownloadForAnotherUser(resourceId, normalizedEmail);
  }

  Future<bool> _scanHasDownloadForAnotherUser(
    String resourceId,
    String normalizedEmail,
  ) async {
    final discoveredOwners = <String>{};
    for (final key in _box.keys) {
      final keyString = key.toString();
      if (!_matchesResourceId(keyString, resourceId)) continue;
      final data = _toEntryMap(_box.get(key));
      if (data == null || !await _entryFileExists(data)) continue;
      final owner = _entryOwner(key: keyString, data: data);
      if (owner == null) continue;
      discoveredOwners.add(owner);
      if (owner != normalizedEmail) {
        _resourceOwnersIndex[resourceId] = discoveredOwners;
        _resourceOwnersIndexReady = true;
        return true;
      }
    }
    if (discoveredOwners.isEmpty) {
      _resourceOwnersIndex.remove(resourceId);
    } else {
      _resourceOwnersIndex[resourceId] = discoveredOwners;
    }
    _resourceOwnersIndexReady = true;
    return false;
  }

  Future<bool> isDownloaded(String resourceId) async {
    if (!_initialized) await init();
    for (final key in _box.keys) {
      final keyString = key.toString();
      if (!_matchesResourceId(keyString, resourceId)) continue;
      final data = _toEntryMap(_box.get(key));
      if (data == null) continue;
      if (await _entryFileExists(data)) return true;
    }
    return false;
  }

  Future<String?> getLocalPath(String resourceId) async {
    if (!_initialized) await init();
    final entry = _toEntryMap(_box.get(resourceId));
    if (entry != null && await _entryFileExists(entry)) {
      return _extractPath(entry);
    }
    for (final key in _box.keys) {
      final keyString = key.toString();
      if (!_matchesResourceId(keyString, resourceId)) continue;
      final data = _toEntryMap(_box.get(key));
      if (data == null || !await _entryFileExists(data)) continue;
      return _extractPath(data);
    }
    return null;
  }

  Future<List<Resource>> getAllDownloadedResources() async {
    if (!_initialized) await init();
    final resources = <Resource>[];

    for (final key in _box.keys) {
      final data = _toEntryMap(_box.get(key));
      if (data == null || !await _entryFileExists(data)) continue;
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

  Future<List<Resource>> getAllDownloadedResourcesForUser(
    String ownerEmail, {
    bool hasPremiumAccess = true,
    bool includeLocked = false,
  }) async {
    if (!_initialized) await init();
    final normalizedEmail = _normalizeEmail(ownerEmail);
    final resources = <Resource>[];

    for (final key in _box.keys) {
      final keyString = key.toString();
      final data = _toEntryMap(_box.get(key));
      if (data == null || !await _entryFileExists(data)) continue;
      final owner = _entryOwner(key: keyString, data: data);
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

  @Deprecated('Use async methods that avoid sync file checks.')
  bool hasDownloadForAnotherUserSync(String resourceId, String ownerEmail) {
    if (!_initialized || !_resourceOwnersIndexReady) return false;
    final normalizedEmail = _normalizeEmail(ownerEmail);
    final owners = _resourceOwnersIndex[resourceId];
    if (owners == null) return false;
    return owners.any((owner) => owner != normalizedEmail);
  }

  Future<void> downloadResource(
    String url,
    Resource resource, {
    required String ownerEmail,
    bool requiresPremiumContent = true,
    Function(int, int)? onProgress,
  }) async {
    if (!_initialized) await init();
    CancelToken? activeToken;

    try {
      final currentToken = _cancelToken;
      if (currentToken != null && !currentToken.isCancelled) {
        currentToken.cancel('superseded_by_new_download');
      }
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
      if (uri == null || uri.scheme.toLowerCase() != 'https') {
        throw Exception('Only HTTPS download URLs are allowed.');
      }
      final lastSegment = uri.pathSegments.isNotEmpty
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

      activeToken = CancelToken();
      _cancelToken = activeToken;
      await _dio.download(
        url,
        safePath,
        onReceiveProgress: onProgress,
        cancelToken: activeToken,
      );

      final data = {
        'local_path': safePath,
        'resource_json': resource.toJson(),
        'downloaded_at': DateTime.now().toIso8601String(),
        'owner_email': normalizedOwner,
        'requires_premium': requiresPremiumContent,
      };

      final scopedKey = _resourceKeyForOwner(resource.id, normalizedOwner);
      try {
        await _box.put(scopedKey, data);
        _indexOwner(resourceId: resource.id, owner: normalizedOwner);
      } catch (e) {
        final file = File(safePath);
        if (await file.exists()) {
          await file.delete();
        }
        rethrow;
      }
      if (_box.containsKey(resource.id)) {
        final legacy = _toEntryMap(_box.get(resource.id));
        final legacyOwner = legacy == null
            ? null
            : _entryOwner(key: resource.id, data: legacy);
        final legacyPath = legacy == null ? null : _extractPath(legacy);
        if (legacyPath != null && legacyPath != safePath) {
          try {
            final legacyFile = File(legacyPath);
            if (await legacyFile.exists()) {
              await legacyFile.delete();
            }
          } catch (deleteError) {
            debugPrint('Failed to delete legacy download file: $deleteError');
          }
        }
        await _box.delete(resource.id);
        if (legacyOwner != null && legacyOwner != normalizedOwner) {
          _unindexOwner(resourceId: resource.id, owner: legacyOwner);
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw DownloadCancelledException(e.message ?? 'Download cancelled');
      }
      throw Exception('Download failed: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('Download failed: $e');
    } finally {
      if (identical(_cancelToken, activeToken)) {
        _cancelToken = null;
      }
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
      final keyString = key.toString();
      final data = _toEntryMap(_box.get(key));
      final path = data == null ? null : _extractPath(data);
      final owner = data == null
          ? null
          : _entryOwner(key: keyString, data: data);
      final indexedResourceId = _resourceIdFromKey(keyString);
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await _box.delete(key);
      if (owner != null) {
        _unindexOwner(resourceId: indexedResourceId, owner: owner);
      } else {
        _resourceOwnersIndex.remove(indexedResourceId);
      }
    }
  }
}
